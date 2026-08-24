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
        switch self {
        case let .contains(value):
            description.range(
                of: value,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        case let .hasPrefix(value):
            description.range(
                of: value,
                options: [.caseInsensitive, .diacriticInsensitive, .anchored]
            ) != nil
        }
    }
}

enum DeterministicRuleCatalog {
    private static let appRideShare = TaxonomySelection(categoryID: "mobilidade", subcategoryID: "uber-e-99")
    private static let foodDelivery = TaxonomySelection(categoryID: "alimentacao", subcategoryID: "delivery-de-comida")
    private static let bakeries = TaxonomySelection(categoryID: "alimentacao", subcategoryID: "padarias")
    private static let airlineTickets = TaxonomySelection(categoryID: "viagem", subcategoryID: "passagens-aereas")
    private static let lodging = TaxonomySelection(categoryID: "viagem", subcategoryID: "hospedagem")

    // Primeiras regras derivadas de descrições recorrentes em faturas Inter.
    static let current = [
        DeterministicRule(
            descriptionPattern: .contains("UBER"),
            selection: appRideShare
        ),
        DeterministicRule(
            descriptionPattern: .contains("99APP"),
            selection: appRideShare
        ),
        DeterministicRule(
            descriptionPattern: .contains("99 RIDE"),
            selection: appRideShare
        ),
        DeterministicRule(
            descriptionPattern: .contains("IFOOD"),
            selection: foodDelivery
        ),
        DeterministicRule(
            descriptionPattern: .contains("PADARIA"),
            selection: bakeries
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("LATAM"),
            selection: airlineTickets
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("AZUL "),
            selection: airlineTickets
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("LUXOR HOTEL"),
            selection: lodging
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("HOTEL CASA DE PRAIA"),
            selection: lodging
        ),
    ]
}
