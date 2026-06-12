import Foundation

/// Taxonomia padrão de categorias (espelha `CategoriesSeedData.dart` do
/// projeto anterior do mesmo usuário). Cada categoria raiz tem N subcategorias.
///
/// Subcategoria sempre herda o `CategoryKind` da raiz — não há mistura de
/// kinds dentro de uma mesma árvore.
///
/// **`slug` é id estável da raiz.** Resolve duas coisas: (1) lookup do ícone
/// via `CategoryIcon.forSlug(_:)` sem precisar gravar `icon` no banco,
/// (2) anchor estável pra IA na Fase 4 (few-shot prompting). UUIDs do seed
/// são aleatórios e mudam a cada banco recriado — slug não.
///
/// **Invariante:** ao adicionar uma raiz nova aqui, **DEVE** existir uma
/// entrada correspondente em `CategoryIcon+Slug.swift` mapeando o slug pro
/// ícone — caso contrário a UI renderiza sem ícone (silencioso). O teste
/// `CategorySeedConsistencyTests.everySeedSlugHasIcon` quebra em CI se o
/// mapping ficar faltando.
struct CategorySeedDefinition {
    let slug: String
    let name: String
    let kind: CategoryKind
    let subcategories: [String]
}

// `nonisolated`: acessado de dentro do closure `@Sendable` do `writeTransaction`
// no Seed — não pode ser MainActor.
nonisolated enum CategorySeedData {
    static let categories: [CategorySeedDefinition] = [
        // MARK: - Receitas

        CategorySeedDefinition(slug: "renda-e-pagamentos", name: "Renda e Pagamentos", kind: .income, subcategories: [
            "Salário",
            "Freelance",
            "13º Salário",
            "Férias",
            "PLR",
            "Juros de Investimentos",
            "Dividendos",
            "Restituição de IR",
            "Cashback",
            "Reembolso",
        ]),

        // MARK: - Despesas

        CategorySeedDefinition(slug: "compras", name: "Compras", kind: .expense, subcategories: [
            "Roupas e Calçados",
            "Acessórios e Joias",
            "Presentes",
            "Artigos Esportivos",
            "Hobbies e Coleções",
        ]),

        CategorySeedDefinition(slug: "cuidados-pessoais", name: "Cuidados Pessoais", kind: .expense, subcategories: [
            "Barbearia",
            "Massagem",
            "Cosméticos e Higiene",
        ]),

        CategorySeedDefinition(slug: "mobilidade", name: "Mobilidade", kind: .expense, subcategories: [
            "Uber e 99",
            "Táxi",
            "Transporte Público",
            "Pedágio",
        ]),

        CategorySeedDefinition(slug: "moto", name: "Moto", kind: .expense, subcategories: [
            "Combustível",
            "Manutenção e Mecânica",
            "Estacionamento",
            "Licenciamento",
            "Multas de Trânsito",
            "Seguro Moto",
            "Equipamentos e Acessórios",
        ]),

        CategorySeedDefinition(slug: "viagem", name: "Viagem", kind: .expense, subcategories: [
            "Passagens Aéreas",
            "Hospedagem",
            "Pacotes de Viagem",
            "Bagagem",
            "Seguro Viagem",
            "Passeios e Atrações",
            "Câmbio",
        ]),

        CategorySeedDefinition(
            slug: "entretenimento",
            name: "Entretenimento",
            kind: .expense,
            subcategories: [
                "Cinema",
                "Teatro",
                "Parques e Diversões",
                "Loterias",
            ]
        ),

        CategorySeedDefinition(
            slug: "festas",
            name: "Festas",
            kind: .expense,
            subcategories: [
                "Bares",
                "Baladas e Boates",
                "Festas e Eventos",
                "Shows e Festivais",
            ]
        ),

        CategorySeedDefinition(
            slug: "danca",
            name: "Dança",
            kind: .expense,
            subcategories: [
                "Escola de Dança",
                "Bailes",
                "Workshops",
                "Congressos",
            ]
        ),

        CategorySeedDefinition(slug: "trabalho", name: "Trabalho", kind: .expense, subcategories: [
            "Hardware",
            "Conferências e Eventos Tech",
        ]),

        CategorySeedDefinition(slug: "educacao", name: "Educação", kind: .expense, subcategories: [
            "Mensalidades",
            "Cursos",
            "Certificações",
            "Livros",
            "Material Escolar",
        ]),

        CategorySeedDefinition(
            slug: "alimentacao",
            name: "Alimentação",
            kind: .expense,
            subcategories: [
                "Supermercados",
                "Mercearias",
                "Açougues",
                "Padarias",
                "Restaurantes",
                "Lanchonetes",
                "Delivery de Comida",
                "Cafeterias",
                "Feira e Hortifrúti",
            ]
        ),

        CategorySeedDefinition(slug: "moradia", name: "Moradia", kind: .expense, subcategories: [
            "Aluguel",
            "Entrada e Encargos",
            "Condomínio",
            "Energia Elétrica",
            "Água",
            "Gás",
            "IPTU",
            "Financiamento Imobiliário",
            "Reforma",
            "Móveis",
            "Decoração",
            "Eletrônicos",
            "Utensílios Domésticos",
            "Ferramentas",
        ]),

        CategorySeedDefinition(slug: "streaming-e-apps", name: "Streaming e Apps", kind: .expense, subcategories: [
            "Streaming de Vídeo",
            "Streaming de Música",
            "IA e Produtividade",
            "Apps e Softwares",
            "Jogos",
        ]),

        CategorySeedDefinition(slug: "conectividade", name: "Conectividade", kind: .expense, subcategories: [
            "Internet Banda Larga",
            "Celular",
        ]),

        CategorySeedDefinition(slug: "exercicios", name: "Exercícios", kind: .expense, subcategories: [
            "Academia",
            "Personal Trainer",
            "Crossfit",
            "Pilates",
        ]),

        CategorySeedDefinition(
            slug: "servicos-profissionais",
            name: "Serviços Profissionais",
            kind: .expense,
            subcategories: [
                "Contabilidade",
                "Jurídico e Advocacia",
                "Consultoria",
                "Limpeza Doméstica",
            ]
        ),

        CategorySeedDefinition(slug: "saude", name: "Saúde", kind: .expense, subcategories: [
            "Plano de Saúde",
            "Consultas Médicas",
            "Consultas Dentárias",
            "Nutricionista",
            "Psicoterapia",
            "Fisioterapia",
            "Farmácias e Medicamentos",
            "Exames",
            "Vacinas",
            "Cirurgias",
            "Emergências Médicas",
            "Óculos e Lentes",
            "Aparelhos Ortodônticos",
            "Suplementos",
        ]),

        CategorySeedDefinition(
            slug: "investimentos",
            name: "Investimentos",
            kind: .expense,
            subcategories: [
                "Poupança",
                "CDB",
                "Tesouro Direto",
                "LCI/LCA",
                "Fundos de Investimento",
                "Ações Bolsa",
                "FIIs",
                "ETFs",
                "Previdência Privada",
                "Criptomoedas",
            ]
        ),

        CategorySeedDefinition(slug: "impostos", name: "Impostos", kind: .expense, subcategories: [
            "Imposto de Renda",
            "DAS",
            "INSS Autônomo",
            "ISS",
            "ITBI",
            "Taxas Cartoriais",
            "Taxas Bancárias",
            "IOF",
        ]),

        CategorySeedDefinition(slug: "saques", name: "Saques", kind: .expense, subcategories: [
            "Saque em Agência",
            "Taxa de Saque",
        ]),

        CategorySeedDefinition(slug: "nao-classificado", name: "Não Classificado", kind: .expense, subcategories: [
            "Pendente de Revisão",
        ]),

        // MARK: - Transferências

        CategorySeedDefinition(slug: "transferencias", name: "Transferências", kind: .transfer, subcategories: [
            "PIX Enviado",
            "PIX Recebido",
            "TED Enviada",
            "TED Recebida",
            "Transferência entre Contas",
            "Transferência Internacional",
            "Depósito em Conta",
        ]),
    ]
}
