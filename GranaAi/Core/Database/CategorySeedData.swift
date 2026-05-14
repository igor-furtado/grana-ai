import Foundation

/// Taxonomia padrão de categorias (espelha `CategoriesSeedData.dart` do
/// projeto anterior do mesmo usuário). Cada categoria raiz tem N subcategorias.
///
/// Subcategoria sempre herda o `CategoryKind` da raiz — não há mistura de
/// kinds dentro de uma mesma árvore.
///
/// **TODO (Fase 4):** quando a IA entrar pra categorizar transações, vamos
/// precisar de IDs estáveis pra few-shot prompting. Ou: adicionar coluna
/// `slug text` no schema (pra usar como external_id estável), ou: persistir
/// um mapeamento `name → UUID` em outro lugar. Decidir na Fase 4.
struct CategorySeedDefinition {
    let name: String
    let kind: CategoryKind
    let icon: CategoryIcon
    let subcategories: [String]
}

// `nonisolated`: acessado de dentro do closure `@Sendable` do `writeTransaction`
// no Seed — não pode ser MainActor.
nonisolated enum CategorySeedData {
    static let categories: [CategorySeedDefinition] = [
        // MARK: - Receitas
        CategorySeedDefinition(name: "Renda e Pagamentos", kind: .income, icon: .dollarSign, subcategories: [
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
        CategorySeedDefinition(name: "Compras Pessoais", kind: .expense, icon: .shoppingBag, subcategories: [
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

        CategorySeedDefinition(name: "Transporte e Viagem", kind: .expense, icon: .car, subcategories: [
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

        CategorySeedDefinition(name: "Entretenimento e Lazer", kind: .expense, icon: .monitor, subcategories: [
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

        CategorySeedDefinition(name: "Alimentação e Supermercado", kind: .expense, icon: .utensils, subcategories: [
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

        CategorySeedDefinition(name: "Contas e Serviços", kind: .expense, icon: .zap, subcategories: [
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

        CategorySeedDefinition(name: "Créditos e Empréstimos", kind: .expense, icon: .creditCard, subcategories: [
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

        CategorySeedDefinition(name: "Saúde e Medicina", kind: .expense, icon: .heart, subcategories: [
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

        CategorySeedDefinition(name: "Seguros", kind: .expense, icon: .shield, subcategories: [
            "Seguro de Vida",
            "Seguro de Automóvel",
            "Seguro Residencial",
            "Seguro Saúde",
            "Seguro Viagem",
            "Seguro Celular",
            "Seguro Prestamista",
            "Seguro Acidentes Pessoais",
        ]),

        CategorySeedDefinition(name: "Investimentos e Poupança", kind: .expense, icon: .trendingUp, subcategories: [
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

        CategorySeedDefinition(name: "Impostos e Taxas", kind: .expense, icon: .fileText, subcategories: [
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

        CategorySeedDefinition(name: "Saques e ATM", kind: .expense, icon: .banknote, subcategories: [
            "Saque ATM Próprio",
            "Saque ATM Terceiros",
            "Saque em Agência",
            "Saque Internacional",
            "Taxa de Saque",
            "Saque Cartão Crédito",
        ]),

        CategorySeedDefinition(name: "Não Classificado", kind: .expense, icon: .helpCircle, subcategories: [
            "Transação Desconhecida",
            "Requer Análise Manual",
            "Transação Suspeita",
            "Categoria Indefinida",
        ]),

        CategorySeedDefinition(name: "Jogos e Apostas", kind: .expense, icon: .dice, subcategories: [
            "Steam",
            "Epic Games",
            "Battle.net",
            "Jogos Online",
            "Mega Sena",
            "Lotofácil",
        ]),

        // MARK: - Transferências
        CategorySeedDefinition(name: "Transferências", kind: .transfer, icon: .arrowRightLeft, subcategories: [
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
