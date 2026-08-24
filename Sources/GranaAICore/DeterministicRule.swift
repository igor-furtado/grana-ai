import Foundation

struct DeterministicRule: Sendable {
    let descriptionPattern: String
    let selection: TaxonomySelection

    func outcome(for transaction: Transaction, taxonomy: Taxonomy) -> ClassificationOutcome? {
        guard transaction.description.range(
            of: descriptionPattern,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil else {
            return nil
        }

        guard taxonomy.contains(selection) else {
            return nil
        }

        return .classified(
            categoryID: selection.categoryID,
            subcategoryID: selection.subcategoryID
        )
    }
}

struct TaxonomySelection: Equatable, Sendable {
    let categoryID: String
    let subcategoryID: String
}

enum DeterministicRuleCatalog {
    static let current = [
        DeterministicRule(
            descriptionPattern: "PADARIA",
            selection: TaxonomySelection(categoryID: "alimentacao", subcategoryID: "padaria")
        ),
    ]
}
