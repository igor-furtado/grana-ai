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

private extension String {
    func normalizedForRuleMatching() -> String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

enum DeterministicRuleCatalog {
    private static let appRideShare = TaxonomySelection(categoryID: "mobilidade", subcategoryID: "uber-e-99")
    private static let foodDelivery = TaxonomySelection(categoryID: "alimentacao", subcategoryID: "delivery-de-comida")
    private static let bakeries = TaxonomySelection(categoryID: "alimentacao", subcategoryID: "padarias")
    private static let restaurants = TaxonomySelection(categoryID: "alimentacao", subcategoryID: "restaurantes")
    private static let butchers = TaxonomySelection(categoryID: "alimentacao", subcategoryID: "acougues")
    private static let groceries = TaxonomySelection(categoryID: "alimentacao", subcategoryID: "mercearias")
    private static let supermarkets = TaxonomySelection(categoryID: "alimentacao", subcategoryID: "supermercados")
    private static let bars = TaxonomySelection(categoryID: "festas", subcategoryID: "bares")
    private static let clubs = TaxonomySelection(categoryID: "festas", subcategoryID: "baladas-e-boates")
    private static let concertsAndFestivals = TaxonomySelection(categoryID: "festas", subcategoryID: "shows-e-festivais")
    private static let videoStreaming = TaxonomySelection(categoryID: "streaming-e-apps", subcategoryID: "streaming-de-video")
    private static let appsAndSoftware = TaxonomySelection(categoryID: "streaming-e-apps", subcategoryID: "apps-e-softwares")
    private static let games = TaxonomySelection(categoryID: "streaming-e-apps", subcategoryID: "jogos")
    private static let gym = TaxonomySelection(categoryID: "exercicios", subcategoryID: "academia")
    private static let personalTrainer = TaxonomySelection(categoryID: "exercicios", subcategoryID: "personal-trainer")
    private static let clothesAndShoes = TaxonomySelection(categoryID: "compras", subcategoryID: "roupas-e-calcados")
    private static let accessoriesAndJewelry = TaxonomySelection(categoryID: "compras", subcategoryID: "acessorios-e-joias")
    private static let perfumery = TaxonomySelection(categoryID: "compras", subcategoryID: "perfumaria")
    private static let accounting = TaxonomySelection(categoryID: "servicos-profissionais", subcategoryID: "contabilidade")
    private static let cellular = TaxonomySelection(categoryID: "conectividade", subcategoryID: "celular")
    private static let pharmaciesAndMedicines = TaxonomySelection(categoryID: "saude", subcategoryID: "farmacias-e-medicamentos")
    private static let medicalExams = TaxonomySelection(categoryID: "saude", subcategoryID: "exames")
    private static let airlineTickets = TaxonomySelection(categoryID: "viagem", subcategoryID: "passagens-aereas")
    private static let lodging = TaxonomySelection(categoryID: "viagem", subcategoryID: "hospedagem")
    private static let hardware = TaxonomySelection(categoryID: "trabalho", subcategoryID: "hardware")
    private static let furniture = TaxonomySelection(categoryID: "moradia", subcategoryID: "moveis")
    private static let iof = TaxonomySelection(categoryID: "impostos", subcategoryID: "iof")

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
        DeterministicRule(
            descriptionPattern: .hasPrefix("A DE C BRITO DE SOUSA"),
            selection: foodDelivery
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("SERESTA DO PRESIDENTE"),
            selection: bars
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("AMAZON SERVICOS DE VAR"),
            selection: videoStreaming
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("AMAZONPRIMEBR"),
            selection: videoStreaming
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("NETFLIX"),
            selection: videoStreaming
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("APPLE COM BILL"),
            selection: appsAndSoftware
        ),
        DeterministicRule(
            descriptionPattern: .contains("SELFIT"),
            selection: gym
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("FRIBAL"),
            selection: groceries
        ),
        DeterministicRule(
            descriptionPattern: .contains("MATEUS SUPERMERCADOS"),
            selection: supermarkets
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("LOJAS RENNER"),
            selection: clothesAndShoes
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("BROOKSFIELD"),
            selection: clothesAndShoes
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("RUTRA"),
            selection: clothesAndShoes
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("RL DOIS VENDAS"),
            selection: clothesAndShoes
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("CERTISI"),
            selection: accounting
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("KABUM"),
            selection: hardware
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("FOOD PARK DAMAMEL"),
            selection: foodDelivery
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("FACEBURGUER"),
            selection: foodDelivery
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("MP FACELANCHE"),
            selection: foodDelivery
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("ARABIAN GRILL"),
            selection: restaurants
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("ESPETO NORDESTINO"),
            selection: restaurants
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("SERVICOS CLA"),
            selection: cellular
        ),
        DeterministicRule(
            descriptionPattern: .contains("EXTRAFARMA"),
            selection: pharmaciesAndMedicines
        ),
        DeterministicRule(
            descriptionPattern: .contains("PAGUE MENOS"),
            selection: pharmaciesAndMedicines
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("GASPAR MATRIZ"),
            selection: medicalExams
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("MARCO AURELIO"),
            selection: personalTrainer
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("MERCADAO LIMA VERDE"),
            selection: groceries
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("FRUTARIA DO LOURO"),
            selection: groceries
        ),
        DeterministicRule(
            descriptionPattern: .contains("J MARTINS PERFU"),
            selection: perfumery
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("GRANADO PHARMACIAS"),
            selection: perfumery
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("GALERIA"),
            selection: clubs
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("CHILLI BEANS"),
            selection: accessoriesAndJewelry
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("IOF INTERNACIONAL"),
            selection: iof
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("R M RODRIGUES DE SOUSA"),
            selection: butchers
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("INGRESSO COM"),
            selection: concertsAndFestivals
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("COMFY COM BR"),
            selection: furniture
        ),
        DeterministicRule(
            descriptionPattern: .hasPrefix("PAG STEAM"),
            selection: games
        ),
    ]
}
