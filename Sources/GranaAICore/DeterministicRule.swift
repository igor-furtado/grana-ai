import Foundation

struct DeterministicRule: Sendable {
    let descriptionPattern: TransactionDescriptionPattern
    let selection: TaxonomySelection

    func outcome(for transaction: Transaction, taxonomy: Taxonomy) -> ClassificationOutcome? {
        guard descriptionPattern.matches(transaction.description) else {
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

enum TransactionDescriptionPattern: Sendable {
    case contains(String)
    case hasPrefix(String)

    func matches(_ description: String) -> Bool {
        let normalizedDescription = description.normalizedForRuleMatching()

        switch self {
        case let .contains(value):
            return normalizedDescription.range(
                of: value.normalizedForRuleMatching(),
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        case let .hasPrefix(value):
            return normalizedDescription.range(
                of: value.normalizedForRuleMatching(),
                options: [.caseInsensitive, .diacriticInsensitive, .anchored]
            ) != nil
        }
    }
}
