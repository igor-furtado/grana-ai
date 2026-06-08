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
        "compras": .shoppingBag,
        "mobilidade": .car,
        "moto": .motorcycle,
        "viagem": .airplane,
        "lazer": .users,
        "atividades-e-aulas": .dumbbell,
        "cuidados-pessoais": .scissors,
        "alimentacao": .utensils,
        "apartamento": .home,
        "streaming-e-apps": .playCircle,
        "comunicacao": .antenna,
        "servicos-profissionais": .briefcase,
        "trabalho": .laptop,
        "educacao": .graduationCap,
        "saude": .heart,
        "investimentos": .trendingUp,
        "impostos": .fileText,
        "saques": .banknote,
        "nao-classificado": .helpCircle,

        // Transferências
        "transferencias": .arrowRightLeft,
    ]
}
