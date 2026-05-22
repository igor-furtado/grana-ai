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

    /// Pré-cadastra as instituições "ricamente suportadas" (com auto-detect
    /// via FID do OFX e ícone próprio). Hoje só Inter — adicionar Itaú,
    /// Bradesco etc. = uma linha aqui + um caso no enum `InstitutionKind`.
    private static func seedInstitutionsIfEmpty(container: AppContainer) async throws {
        let existing = try await container.institutions.getAll()
        guard existing.isEmpty else { return }

        let now = Date()
        let inter = Institution(
            id: UUID(),
            code: InstitutionKind.inter.defaultCode ?? "077",
            name: InstitutionKind.inter.displayName,
            kind: .inter,
            createdAt: now,
            updatedAt: now
        )
        try await container.institutions.insert(inter)
        log.database.info("Seed: instituições padrão inseridas (Inter)")
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
