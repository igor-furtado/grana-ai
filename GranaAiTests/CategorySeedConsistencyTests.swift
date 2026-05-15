import Foundation
import Testing
@testable import GranaAi

/// Garante que o seed e o mapping `slug → CategoryIcon` não derivam.
///
/// Sem isso: alguém adiciona uma categoria nova em `CategorySeedData` e
/// esquece de incluir o slug em `CategoryIcon+Slug.swift`. O app insere a
/// linha, mas a UI renderiza sem ícone — silenciosamente. Esse teste pega
/// o drift em CI antes de subir.
@Suite("CategorySeedData ↔ CategoryIcon+Slug consistency")
struct CategorySeedConsistencyTests {

    @Test("toda raiz do seed tem ícone resolvido pelo mapping")
    func everySeedSlugHasIcon() {
        for definition in CategorySeedData.categories {
            #expect(
                CategoryIcon.forSlug(definition.slug) != nil,
                "Slug '\(definition.slug)' está em CategorySeedData mas não tem entrada em CategoryIcon+Slug.swift"
            )
        }
    }

    @Test("slugs do seed são únicos")
    func slugsAreUnique() {
        let slugs = CategorySeedData.categories.map(\.slug)
        let uniqueSlugs = Set(slugs)
        #expect(slugs.count == uniqueSlugs.count, "Slug duplicado em CategorySeedData")
    }
}
