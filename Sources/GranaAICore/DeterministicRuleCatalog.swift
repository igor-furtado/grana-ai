struct DeterministicRuleGroup: Sendable {
    let selection: TaxonomySelection
    let patterns: [TransactionDescriptionPattern]

    var rules: [DeterministicRule] {
        patterns.map { pattern in
            DeterministicRule(descriptionPattern: pattern, selection: selection)
        }
    }
}

enum DeterministicRuleCatalog {
    static let current = groups.flatMap(\.rules)

    private static let groups: [DeterministicRuleGroup] = [
        group(.mobilidade("uber-e-99"), [
            .contains("UBER"),
            .contains("99APP"),
            .contains("99 RIDE"),
        ]),

        group(.alimentacao("delivery-de-comida"), [
            .contains("IFOOD"),
            .hasPrefix("A DE C BRITO DE SOUSA"),
            .hasPrefix("FOOD PARK DAMAMEL"),
            .hasPrefix("FACEBURGUER"),
            .hasPrefix("MP FACELANCHE"),
            .hasPrefix("REI DO CHURRASCO"),
            .hasPrefix("IFD FACE LANCHES"),
        ]),
        group(.alimentacao("padarias"), [
            .contains("PADARIA"),
        ]),
        group(.alimentacao("restaurantes"), [
            .hasPrefix("ARABIAN GRILL"),
            .hasPrefix("ESPETO NORDESTINO"),
        ]),
        group(.alimentacao("acougues"), [
            .hasPrefix("R M RODRIGUES DE SOUSA"),
        ]),
        group(.alimentacao("mercearias"), [
            .hasPrefix("FRIBAL"),
            .hasPrefix("MERCADAO LIMA VERDE"),
            .hasPrefix("FRUTARIA DO LOURO"),
            .hasPrefix("FRUTARIA BIANCA"),
            .hasPrefix("PG TON MERCEARIA"),
        ]),
        group(.alimentacao("supermercados"), [
            .contains("MATEUS SUPERMERCADOS"),
            .hasPrefix("SUPER MERCADINHOS"),
        ]),
        group(.alimentacao("lanchonetes"), [
            .hasPrefix("PG TON DANIELE RODR"),
            .hasPrefix("GUGA LANCHES"),
        ]),

        group(.festas("bares"), [
            .hasPrefix("SERESTA DO PRESIDENTE"),
            .hasPrefix("SILENCIO"),
            .hasPrefix("BARKABAO"),
            .hasPrefix("DIGITALAUDIOELUZ"),
        ]),
        group(.festas("baladas-e-boates"), [
            .hasPrefix("GALERIA"),
        ]),
        group(.festas("shows-e-festivais"), [
            .hasPrefix("INGRESSO COM"),
            .hasPrefix("SHOWSYSTEM"),
        ]),

        group(.danca("bailes"), [
            .hasPrefix("MP EXPRESSAR"),
        ]),
        group(.danca("congressos"), [
            .hasPrefix("PIRATA BAR TURISMO"),
        ]),
        group(.danca("workshops"), [
            .hasPrefix("MP VILLERMONTELES"),
        ]),

        group(.streamingEApps("streaming-de-video"), [
            .hasPrefix("AMAZON SERVICOS DE VAR"),
            .hasPrefix("AMAZONPRIMEBR"),
            .hasPrefix("NETFLIX"),
        ]),
        group(.streamingEApps("apps-e-softwares"), [
            .hasPrefix("APPLE COM BILL"),
            .hasPrefix("LAGOFAST"),
            .hasPrefix("AC NORD VPNCOM"),
            .hasPrefix("PPRO MICROSOFT"),
        ]),
        group(.streamingEApps("jogos"), [
            .hasPrefix("PAG STEAM"),
        ]),

        group(.exercicios("academia"), [
            .contains("SELFIT"),
        ]),
        group(.exercicios("personal-trainer"), [
            .hasPrefix("MARCO AURELIO"),
            .hasPrefix("MARCO AURELI"),
        ]),

        group(.compras("roupas-e-calcados"), [
            .hasPrefix("LOJAS RENNER"),
            .hasPrefix("BROOKSFIELD"),
            .hasPrefix("RUTRA"),
            .hasPrefix("RL DOIS VENDAS"),
            .hasPrefix("ZARA.COM"),
            .hasPrefix("ZARA COM BRASIL"),
            .hasPrefix("CEA RIB"),
            .hasPrefix("MP UNDIESSTORE"),
            .hasPrefix("POLYELLE"),
            .hasPrefix("PONTO DA MODA"),
            .hasPrefix("SAOLUISMEIAS"),
            .hasPrefix("TRACKFIELD"),
        ]),
        group(.compras("acessorios-e-joias"), [
            .hasPrefix("CHILLI BEANS"),
        ]),
        group(.compras("perfumaria"), [
            .contains("J MARTINS PERFU"),
            .hasPrefix("GRANADO PHARMACIAS"),
        ]),

        group(.servicosProfissionais("contabilidade"), [
            .hasPrefix("CERTISI"),
        ]),
        group(.conectividade("celular"), [
            .hasPrefix("SERVICOS CLA"),
        ]),
        group(.saude("farmacias-e-medicamentos"), [
            .contains("EXTRAFARMA"),
            .contains("PAGUE MENOS"),
            .hasPrefix("BIOFORMULA"),
        ]),
        group(.saude("exames"), [
            .hasPrefix("GASPAR MATRIZ"),
        ]),

        group(.viagem("passagens-aereas"), [
            .hasPrefix("LATAM"),
            .hasPrefix("AZUL "),
        ]),
        group(.viagem("hospedagem"), [
            .hasPrefix("LUXOR HOTEL"),
            .hasPrefix("HOTEL CASA DE PRAIA"),
        ]),

        group(.trabalho("hardware"), [
            .hasPrefix("KABUM"),
        ]),
        group(.moradia("moveis"), [
            .hasPrefix("COMFY COM BR"),
        ]),
        group(.impostos("iof"), [
            .hasPrefix("IOF INTERNACIONAL"),
            .hasPrefix("IOF DIARIO"),
            .hasPrefix("IOF ADICIONAL"),
        ]),
        group(.impostos("taxas-bancarias"), [
            .hasPrefix("JUROS DE MORA"),
            .hasPrefix("ENCARGOS ROTATIVO"),
        ]),
    ]

    private static func group(
        _ selection: TaxonomySelection,
        _ patterns: [TransactionDescriptionPattern]
    ) -> DeterministicRuleGroup {
        DeterministicRuleGroup(selection: selection, patterns: patterns)
    }
}

private extension TaxonomySelection {
    static func alimentacao(_ subcategoryID: String) -> TaxonomySelection {
        TaxonomySelection(categoryID: "alimentacao", subcategoryID: subcategoryID)
    }

    static func compras(_ subcategoryID: String) -> TaxonomySelection {
        TaxonomySelection(categoryID: "compras", subcategoryID: subcategoryID)
    }

    static func conectividade(_ subcategoryID: String) -> TaxonomySelection {
        TaxonomySelection(categoryID: "conectividade", subcategoryID: subcategoryID)
    }

    static func exercicios(_ subcategoryID: String) -> TaxonomySelection {
        TaxonomySelection(categoryID: "exercicios", subcategoryID: subcategoryID)
    }

    static func festas(_ subcategoryID: String) -> TaxonomySelection {
        TaxonomySelection(categoryID: "festas", subcategoryID: subcategoryID)
    }

    static func danca(_ subcategoryID: String) -> TaxonomySelection {
        TaxonomySelection(categoryID: "danca", subcategoryID: subcategoryID)
    }

    static func impostos(_ subcategoryID: String) -> TaxonomySelection {
        TaxonomySelection(categoryID: "impostos", subcategoryID: subcategoryID)
    }

    static func mobilidade(_ subcategoryID: String) -> TaxonomySelection {
        TaxonomySelection(categoryID: "mobilidade", subcategoryID: subcategoryID)
    }

    static func moradia(_ subcategoryID: String) -> TaxonomySelection {
        TaxonomySelection(categoryID: "moradia", subcategoryID: subcategoryID)
    }

    static func saude(_ subcategoryID: String) -> TaxonomySelection {
        TaxonomySelection(categoryID: "saude", subcategoryID: subcategoryID)
    }

    static func servicosProfissionais(_ subcategoryID: String) -> TaxonomySelection {
        TaxonomySelection(categoryID: "servicos-profissionais", subcategoryID: subcategoryID)
    }

    static func streamingEApps(_ subcategoryID: String) -> TaxonomySelection {
        TaxonomySelection(categoryID: "streaming-e-apps", subcategoryID: subcategoryID)
    }

    static func trabalho(_ subcategoryID: String) -> TaxonomySelection {
        TaxonomySelection(categoryID: "trabalho", subcategoryID: subcategoryID)
    }

    static func viagem(_ subcategoryID: String) -> TaxonomySelection {
        TaxonomySelection(categoryID: "viagem", subcategoryID: subcategoryID)
    }
}
