import Foundation
import OSLog
import PowerSync

/// Popula o banco com dados iniciais (contas padrão + taxonomia do Apêndice A
/// do PROJECT.md) na primeira execução.
///
/// **Por que checar "se vazio" em vez de uma flag "já rodou":** simples,
/// barato, e robusto a casos de banco apagado/recriado (ex: trocar de máquina,
/// reset durante desenvolvimento). Idempotente por design.
enum Seed {
    /// Resultado de uma sincronização aditiva contra `CategorySeedData`.
    /// Usado pela UI ("Sincronizar categorias padrão") pra dar feedback do
    /// que efetivamente foi inserido — diferenciando "tudo já estava lá"
    /// de "entraram X coisas novas".
    struct SyncResult: Sendable {
        let rootsAdded: Int
        let subcategoriesAdded: Int

        var didChange: Bool { rootsAdded > 0 || subcategoriesAdded > 0 }
    }

    static func runIfNeeded(container: AppContainer) async throws {
        try await seedInstitutionsIfEmpty(container: container)
        try await seedCategoriesIfEmpty(container: container)
    }

    /// Sincroniza o banco existente com `CategorySeedData` de forma **aditiva**:
    /// insere roots cujo `slug` ainda não existe e subcategorias cujo `name`
    /// ainda não existe sob a root correspondente. **Nunca remove nem renomeia
    /// nada** — categorias órfãs do seed seguem intactas porque podem ter
    /// transações apontando pra elas.
    ///
    /// Idempotente por design: rodar de novo após mudar nada vira no-op.
    /// Diferente de `seedCategoriesIfEmpty` que só roda no primeiro boot, esta
    /// é destinada a aplicar mudanças do seed em bancos já populados.
    static func syncFromSeedData(container: AppContainer) async throws -> SyncResult {
        let existingRoots = try await container.categories.getRootCategories()
        let rootsBySlug: [String: Category] = Dictionary(
            uniqueKeysWithValues: existingRoots.compactMap { root in
                root.slug.map { ($0, root) }
            }
        )

        // Subcategorias por parentId (snapshot pra não bater no banco N vezes).
        var subsByParent: [UUID: Set<String>] = [:]
        for root in existingRoots {
            let subs = try await container.categories.getSubcategoriesOf(parentId: root.id)
            subsByParent[root.id] = Set(subs.map { $0.name })
        }

        // Snapshots locais (Sendable) consumidos dentro do closure @Sendable.
        let rootIdBySlug: [String: UUID] = rootsBySlug.mapValues { $0.id }
        let result: SyncResult = try await container.db.writeTransaction { tx in
            let nowString = Converters.dateToString(Date())
            let insertSQL = """
            INSERT INTO categories
                (id, parent_id, name, kind, slug, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """

            var rootsAdded = 0
            var subsAdded = 0

            for definition in CategorySeedData.categories {
                let parentId: UUID
                let existingSubs: Set<String>

                if let existingId = rootIdBySlug[definition.slug] {
                    parentId = existingId
                    existingSubs = subsByParent[existingId] ?? []
                } else {
                    parentId = UUID()
                    try tx.execute(
                        sql: insertSQL,
                        parameters: [
                            parentId.uuidString,
                            nil,
                            definition.name,
                            definition.kind.rawValue,
                            definition.slug,
                            nowString,
                        ]
                    )
                    rootsAdded += 1
                    existingSubs = []
                }

                for subName in definition.subcategories where !existingSubs.contains(subName) {
                    try tx.execute(
                        sql: insertSQL,
                        parameters: [
                            UUID().uuidString,
                            parentId.uuidString,
                            subName,
                            definition.kind.rawValue,
                            nil,
                            nowString,
                        ]
                    )
                    subsAdded += 1
                }
            }

            return SyncResult(rootsAdded: rootsAdded, subcategoriesAdded: subsAdded)
        }

        if result.didChange {
            log.database
                .info("Seed sync: \(result.rootsAdded) raízes + \(result.subcategoriesAdded) subcategorias inseridas")
        }

        return result
    }

    /// Pré-cadastra todas as instituições "ricamente suportadas" — qualquer
    /// `InstitutionKind` com `defaultCode` não-nulo. Idempotente por código
    /// FEBRABAN: insere só os kinds ausentes, então adicionar um novo caso no
    /// enum entra automaticamente na próxima execução sem migration.
    private static func seedInstitutionsIfEmpty(container: AppContainer) async throws {
        let existing = try await container.institutions.getAll()
        let existingCodes = Set(existing.map { $0.code })

        let now = Date()
        var inserted: [String] = []
        for kind in InstitutionKind.supported {
            guard let code = kind.defaultCode, !existingCodes.contains(code) else { continue }
            let institution = Institution(
                id: UUID(),
                code: code,
                name: kind.displayName,
                kind: kind,
                createdAt: now,
                updatedAt: now
            )
            try await container.institutions.insert(institution)
            inserted.append(kind.displayName)
        }

        if !inserted.isEmpty {
            log.database.info("Seed: instituições inseridas (\(inserted.joined(separator: ", ")))")
        }
    }

    private static func seedCategoriesIfEmpty(container: AppContainer) async throws {
        let existing = try await container.categories.getAll()
        guard existing.isEmpty else { return }

        // Toda a inserção em UMA transação atômica: se qualquer execute falhar,
        // tudo é desfeito (writeTransaction garante rollback automático em
        // throw). Importante porque queremos "ou todas as categorias entram,
        // ou nenhuma" — não podemos ficar com taxonomia pela metade.
        //
        // Fonte da verdade: `CategorySeedData.categories`.
        try await container.db.writeTransaction { tx in
            let nowString = Converters.dateToString(Date())

            let insertSQL = """
            INSERT INTO categories
                (id, parent_id, name, kind, slug, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """

            for definition in CategorySeedData.categories {
                let parentId = UUID()
                try tx.execute(
                    sql: insertSQL,
                    parameters: [
                        parentId.uuidString,
                        nil, // raiz
                        definition.name,
                        definition.kind.rawValue,
                        definition.slug, // slug só na raiz; ícone resolve via CategoryIcon.forSlug
                        nowString,
                    ]
                )

                // Subcategoria herda o kind do pai — uma sub de "Despesa" é
                // necessariamente despesa, não faz sentido misturar.
                // Slug fica NULL: a UI cai no ícone do pai via
                // `TransactionStore.icon(for:)`. Sub ganha slug próprio quando
                // a Fase 4 (IA) precisar — hoje não há consumidor.
                for subName in definition.subcategories {
                    try tx.execute(
                        sql: insertSQL,
                        parameters: [
                            UUID().uuidString,
                            parentId.uuidString,
                            subName,
                            definition.kind.rawValue,
                            nil,
                            nowString,
                        ]
                    )
                }
            }
        }

        let total = CategorySeedData.categories.reduce(0) { $0 + 1 + $1.subcategories.count }
        log.database
            .info(
                "Seed: \(CategorySeedData.categories.count) raízes + \(total - CategorySeedData.categories.count) subcategorias inseridas (transacional)"
            )
    }
}
