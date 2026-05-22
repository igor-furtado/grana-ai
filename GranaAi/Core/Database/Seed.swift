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
    static func runIfNeeded(container: AppContainer) async throws {
        try await seedAccountsIfEmpty(container: container)
        try await seedInstitutionsIfEmpty(container: container)
        try await seedCategoriesIfEmpty(container: container)
    }

    private static func seedAccountsIfEmpty(container: AppContainer) async throws {
        let existing = try await container.accounts.getAll()
        guard existing.isEmpty else { return }

        // Apenas "Carteira" como padrão na Fase 3 em diante. Contas bancárias
        // são criadas pelo usuário (manualmente) ou pelo importer OFX —
        // criar uma "Conta Corrente" genérica no seed era enganoso porque
        // não tinha instituição associada.
        let now = Date()
        let wallet = Account(
            id: UUID(),
            name: "Carteira",
            type: .wallet,
            initialBalance: 0,
            archived: false,
            createdAt: now,
            updatedAt: now
        )
        try await container.accounts.insert(wallet)
        log.database.info("Seed: conta padrão 'Carteira' inserida")
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
                        nil,                            // raiz
                        definition.name,
                        definition.kind.rawValue,
                        definition.slug,                // slug só na raiz; ícone resolve via CategoryIcon.forSlug
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
        log.database.info("Seed: \(CategorySeedData.categories.count) raízes + \(total - CategorySeedData.categories.count) subcategorias inseridas (transacional)")
    }
}
