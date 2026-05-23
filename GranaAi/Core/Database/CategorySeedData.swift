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
            "Aposentadoria",
            "Auxílio e Benefícios",
            "Pensão",
            "13º Salário",
            "Férias",
            "PLR",
            "Comissões",
            "Juros de Investimentos",
            "Dividendos",
            "Aluguel Recebido",
            "Vendas",
            "Restituição de IR",
            "Cashback",
            "Reembolso",
        ]),

        // MARK: - Despesas

        CategorySeedDefinition(slug: "compras-pessoais", name: "Compras Pessoais", kind: .expense, subcategories: [
            "Roupas e Calçados",
            "Acessórios e Joias",
            "Eletrônicos",
            "Cosméticos e Higiene",
            "Móveis",
            "Decoração",
            "Utensílios Domésticos",
            "Ferramentas",
            "Livros",
            "Presentes",
            "Artigos Esportivos",
            "Hobbies e Coleções",
        ]),

        CategorySeedDefinition(slug: "transporte", name: "Transporte", kind: .expense, subcategories: [
            "Uber e 99",
            "Táxi",
            "Combustível",
            "Transporte Público",
            "Manutenção Veículos",
            "Estacionamento",
            "Pedágio",
        ]),

        CategorySeedDefinition(slug: "viagem", name: "Viagem", kind: .expense, subcategories: [
            "Passagens Aéreas",
            "Passagens de Ônibus",
            "Hospedagem",
            "Aluguel de Carros",
            "Pacotes de Viagem",
            "Bagagem",
        ]),

        CategorySeedDefinition(
            slug: "entretenimento-e-lazer",
            name: "Entretenimento e Lazer",
            kind: .expense,
            subcategories: [
                "Streaming de Vídeo",
                "Streaming de Música",
                "Academia",
                "Personal Trainer",
                "Jogos e Aplicativos",
                "Cinema",
                "Teatro",
                "Shows e Eventos",
                "Parques e Diversões",
                "Cursos Online",
                "Software e Licenças",
            ]
        ),

        CategorySeedDefinition(
            slug: "alimentacao-e-supermercado",
            name: "Alimentação e Supermercado",
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
                "Bares",
                "Hortifrúti",
            ]
        ),

        CategorySeedDefinition(slug: "contas-e-servicos", name: "Contas e Serviços", kind: .expense, subcategories: [
            "Energia Elétrica",
            "Água e Esgoto",
            "Internet Banda Larga",
            "Celular",
            "Gás Encanado",
            "Gás de Cozinha",
            "TV por Assinatura",
            "Condomínio",
            "Limpeza Doméstica",
            "Jardinagem",
            "Segurança Residencial",
            "Correios",
        ]),

        CategorySeedDefinition(
            slug: "creditos-e-emprestimos",
            name: "Créditos e Empréstimos",
            kind: .expense,
            subcategories: [
                "Cartão de Crédito",
                "Empréstimos Pessoais",
                "Crediário",
                "Financiamento Imobiliário",
                "Financiamento Veicular",
                "Consórcio Imóvel",
                "Consórcio Veículo",
                "Empréstimo Consignado",
                "Cheque Especial",
                "Juros e Multas",
            ]
        ),

        CategorySeedDefinition(slug: "saude-e-medicina", name: "Saúde e Medicina", kind: .expense, subcategories: [
            "Plano de Saúde",
            "Consultas Médicas",
            "Consultas Dentárias",
            "Psicoterapia",
            "Fisioterapia",
            "Farmácias e Medicamentos",
            "Exames",
            "Cirurgias",
            "Emergências Médicas",
            "Óculos e Lentes",
            "Aparelhos Ortodônticos",
            "Suplementos",
        ]),

        CategorySeedDefinition(slug: "seguros", name: "Seguros", kind: .expense, subcategories: [
            "Seguro de Vida",
            "Seguro Veicular",
            "Seguro Residencial",
            "Seguro Viagem",
            "Seguro Celular",
            "Outros Seguros",
        ]),

        CategorySeedDefinition(
            slug: "investimentos-e-poupanca",
            name: "Investimentos e Poupança",
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

        CategorySeedDefinition(slug: "impostos-e-taxas", name: "Impostos e Taxas", kind: .expense, subcategories: [
            "Imposto de Renda",
            "IPVA",
            "IPTU",
            "ITBI",
            "Licenciamento Veicular",
            "Multas de Trânsito",
            "Taxas Cartoriais",
            "Taxas Bancárias",
            "IOF",
            "INSS Autônomo",
            "ISS",
        ]),

        CategorySeedDefinition(slug: "saques-e-atm", name: "Saques e ATM", kind: .expense, subcategories: [
            "Saque ATM Próprio",
            "Saque ATM Terceiros",
            "Saque em Agência",
            "Saque Internacional",
            "Taxa de Saque",
            "Saque Cartão Crédito",
        ]),

        CategorySeedDefinition(slug: "nao-classificado", name: "Não Classificado", kind: .expense, subcategories: [
            "Pendente de Revisão",
        ]),

        CategorySeedDefinition(slug: "jogos-e-apostas", name: "Jogos e Apostas", kind: .expense, subcategories: [
            "Lojas de Jogos",
            "Loterias",
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
