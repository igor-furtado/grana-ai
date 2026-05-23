import Foundation

/// Mapping `slug → CategoryIcon` das categorias raiz do seed.
///
/// **Fonte única da verdade:** se uma categoria raiz nova entra em
/// `CategorySeedData.categories`, o slug correspondente DEVE existir aqui.
/// O contrário também — slug órfão (sem categoria no seed) é unused code.
///
/// **Por que não derivar do nome:** se um dia o usuário renomear
/// "Compras Pessoais" pra "Roupas e Acessórios", o ícone tem que continuar
/// resolvendo. O slug é o anchor estável; o nome é display.
///
/// **Por que dicionário privado em vez de switch no enum:** evita poluir
/// `CategoryIcon` com 16 strings hard-coded e mantém a responsabilidade
/// "qual slug usa qual ícone?" isolada deste arquivo.
extension CategoryIcon {
    static func forSlug(_ slug: String) -> CategoryIcon? {
        slugToIcon[slug]
    }

    private static let slugToIcon: [String: CategoryIcon] = [
        // Receitas
        "renda-e-pagamentos": .dollarSign,

        // Despesas
        "compras-pessoais": .shoppingBag,
        "transporte": .car,
        "viagem": .airplane,
        "entretenimento-e-lazer": .monitor,
        "alimentacao-e-supermercado": .utensils,
        "contas-e-servicos": .zap,
        "creditos-e-emprestimos": .creditCard,
        "saude-e-medicina": .heart,
        "seguros": .shield,
        "investimentos-e-poupanca": .trendingUp,
        "impostos-e-taxas": .fileText,
        "saques-e-atm": .banknote,
        "nao-classificado": .helpCircle,
        "jogos-e-apostas": .dice,

        // Transferências
        "transferencias": .arrowRightLeft,
    ]
}
