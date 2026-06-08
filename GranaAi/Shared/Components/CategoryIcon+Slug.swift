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
extension CategoryIcon {
    static func forSlug(_ slug: String) -> CategoryIcon? {
        slugToIcon[slug]
    }

    private static let slugToIcon: [String: CategoryIcon] = [
        // Receitas
        "renda-e-pagamentos": .income,

        // Despesas
        "alimentacao": .food,
        "moradia": .housing,
        "exercicios": .exercise,
        "danca": .dance,
        "compras": .shopping,
        "conectividade": .connectivity,
        "cuidados-pessoais": .personalCare,
        "educacao": .education,
        "entretenimento": .entertainment,
        "festas": .party,
        "impostos": .taxes,
        "investimentos": .investments,
        "mobilidade": .mobility,
        "moto": .motorcycle,
        "nao-classificado": .unclassified,
        "saques": .withdrawal,
        "saude": .health,
        "servicos-profissionais": .professional,
        "streaming-e-apps": .streaming,
        "trabalho": .work,
        "viagem": .travel,

        // Transferências
        "transferencias": .transfer,
    ]
}
