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
        ]),

        // MARK: - Despesas
        CategorySeedDefinition(slug: "compras-pessoais", name: "Compras Pessoais", kind: .expense, subcategories: [
            "Roupas e Calçados",
            "Acessórios e Joias",
            "Eletrônicos",
            "Smartphones e Gadgets",
            "Cosméticos e Perfumes",
            "Produtos de Higiene",
            "Móveis",
            "Decoração",
            "Utensílios Domésticos",
            "Ferramentas",
            "Livros",
            "Material Escolar",
            "Presentes",
            "Artigos Esportivos",
            "Hobbies e Coleções",
        ]),

        CategorySeedDefinition(slug: "transporte-e-viagem", name: "Transporte e Viagem", kind: .expense, subcategories: [
            "Uber e 99",
            "Táxi",
            "Combustível",
            "Passagens Aéreas",
            "Passagens de Ônibus",
            "Passagens de Trem",
            "Hospedagem",
            "Hotéis",
            "Pousadas",
            "Transporte Público",
            "Metrô e Trem",
            "Manutenção Veículos",
            "Seguro Veicular",
            "IPVA",
            "Estacionamento",
            "Pedágio",
            "Aluguel de Carros",
        ]),

        CategorySeedDefinition(slug: "entretenimento-e-lazer", name: "Entretenimento e Lazer", kind: .expense, subcategories: [
            "Netflix",
            "Amazon Prime",
            "Disney Plus",
            "Spotify",
            "Apple Music",
            "YouTube Premium",
            "Academia",
            "Personal Trainer",
            "Jogos e Aplicativos",
            "Cinema",
            "Teatro",
            "Shows e Eventos",
            "Parques e Diversões",
            "Cursos Online",
            "Software e Licenças",
        ]),

        CategorySeedDefinition(slug: "alimentacao-e-supermercado", name: "Alimentação e Supermercado", kind: .expense, subcategories: [
            "Supermercados",
            "Hipermercados",
            "Mercearias",
            "Açougues",
            "Padarias",
            "Confeitarias",
            "Restaurantes",
            "Lanchonetes",
            "iFood",
            "Uber Eats",
            "Rappi",
            "Fast Food",
            "Cafeterias",
            "Bares",
            "Bebidas Alcoólicas",
            "Hortifrúti",
        ]),

        CategorySeedDefinition(slug: "contas-e-servicos", name: "Contas e Serviços", kind: .expense, subcategories: [
            "Energia Elétrica",
            "Água e Esgoto",
            "Internet Banda Larga",
            "Telefone Fixo",
            "Celular",
            "Gás Encanado",
            "Gás de Cozinha",
            "TV por Assinatura",
            "Condomínio",
            "Administração Predial",
            "Limpeza Doméstica",
            "Jardinagem",
            "Segurança Residencial",
            "Correios",
        ]),

        CategorySeedDefinition(slug: "creditos-e-emprestimos", name: "Créditos e Empréstimos", kind: .expense, subcategories: [
            "Cartão de Crédito",
            "Empréstimos Pessoais",
            "Crediário",
            "Financiamento Imobiliário",
            "Financiamento Veicular",
            "Consórcio Imóvel",
            "Consórcio Veículo",
            "Antecipação Saque Aniversário",
            "Empréstimo Consignado",
            "Cheque Especial",
            "Juros e Multas",
        ]),

        CategorySeedDefinition(slug: "saude-e-medicina", name: "Saúde e Medicina", kind: .expense, subcategories: [
            "Plano de Saúde",
            "Consultas Médicas",
            "Consultas Dentárias",
            "Psicoterapia",
            "Fisioterapia",
            "Medicamentos",
            "Farmácias",
            "Exames Laboratoriais",
            "Exames de Imagem",
            "Cirurgias",
            "Emergências Médicas",
            "Óculos e Lentes",
            "Aparelhos Ortodônticos",
            "Suplementos",
        ]),

        CategorySeedDefinition(slug: "seguros", name: "Seguros", kind: .expense, subcategories: [
            "Seguro de Vida",
            "Seguro de Automóvel",
            "Seguro Residencial",
            "Seguro Saúde",
            "Seguro Viagem",
            "Seguro Celular",
            "Seguro Prestamista",
            "Seguro Acidentes Pessoais",
        ]),

        CategorySeedDefinition(slug: "investimentos-e-poupanca", name: "Investimentos e Poupança", kind: .expense, subcategories: [
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
            "Corretoras",
            "Bancos de Investimento",
        ]),

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
            "Certidões",
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
            "Transação Desconhecida",
            "Requer Análise Manual",
            "Transação Suspeita",
            "Categoria Indefinida",
        ]),

        CategorySeedDefinition(slug: "jogos-e-apostas", name: "Jogos e Apostas", kind: .expense, subcategories: [
            "Steam",
            "Epic Games",
            "Battle.net",
            "Jogos Online",
            "Mega Sena",
            "Lotofácil",
        ]),

        // MARK: - Transferências
        CategorySeedDefinition(slug: "transferencias", name: "Transferências", kind: .transfer, subcategories: [
            "PIX Enviado",
            "PIX Recebido",
            "TED Enviada",
            "TED Recebida",
            "DOC Enviado",
            "DOC Recebido",
            "Transferência entre Contas",
            "Transferência Internacional",
            "Remessa Familiar",
            "Depósito em Conta",
        ]),
    ]
}
