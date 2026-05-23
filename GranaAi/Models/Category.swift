import Foundation

/// Classificação hierárquica de transação. Categoria raiz tem `parentId == nil`;
/// subcategorias apontam para a raiz via `parentId`.
///
/// **`slug` só na raiz:** decisão de produto — subcategorias herdam o ícone
/// do pai pra reduzir ruído visual. No banco, subcategoria tem `slug = NULL`;
/// a UI consulta o ícone do pai via `TransactionStore.icon(for:)`.
///
/// **Por que slug em vez de coluna `icon`:** categorias são seed estático
/// (usuário não cria nem edita por enquanto), então gravar o `CategoryIcon`
/// em cada linha é desperdício — o ícone é função pura do slug. O mapping
/// `slug → CategoryIcon` vive em `CategoryIcon+Slug.swift`, fonte única
/// da verdade. Slug também serve como id estável pra IA na Fase 4 (few-shot
/// prompting) — sem isso precisaríamos de UUIDs hard-coded.
struct Category: Identifiable, Codable, Hashable {
    let id: UUID
    var parentId: UUID?
    var name: String
    var kind: CategoryKind
    var slug: String?
    let createdAt: Date

    /// Ícone derivado do slug. Subcategorias sempre retornam `nil` aqui —
    /// quem precisa do ícone "efetivo" da subcategoria usa
    /// `TransactionStore.icon(for:)`, que cai no pai.
    var icon: CategoryIcon? {
        slug.flatMap(CategoryIcon.forSlug)
    }
}

enum CategoryKind: String, Codable, CaseIterable {
    case expense
    case income
    case transfer

    var displayName: String {
        switch self {
        case .expense: "Despesa"
        case .income: "Receita"
        case .transfer: "Transferência"
        }
    }
}

/// Ícone visual da categoria raiz.
///
/// **Raw values em camelCase** espelham os nomes do `CategoryIcon` do projeto
/// Flutter (Lucide icons) — facilita migração futura de dados entre os dois.
/// Mapeamento pra SF Symbols (nativo Apple) fica em `systemImage`.
///
/// **Por que enum tipado em vez de String solta:**
/// - Compilador valida que só nomes conhecidos são usados.
/// - O mapeamento Lucide→SF Symbol fica em UM lugar (aqui).
/// - Trocar a biblioteca de ícones no futuro = mudar só o switch.
enum CategoryIcon: String, Codable, CaseIterable {
    case dollarSign
    case shoppingBag
    case car
    case monitor
    case utensils
    case zap
    case creditCard
    case heart
    case shield
    case trendingUp
    case fileText
    case banknote
    case helpCircle
    case dice
    case arrowRightLeft
    case airplane

    /// Nome do SF Symbol correspondente, pra usar em `Image(systemName:)`.
    var systemImage: String {
        switch self {
        case .dollarSign: "dollarsign.circle.fill"
        case .shoppingBag: "bag.fill"
        case .car: "car.fill"
        case .monitor: "tv.fill"
        case .utensils: "fork.knife"
        case .zap: "bolt.fill"
        case .creditCard: "creditcard.fill"
        case .heart: "heart.fill"
        case .shield: "shield.fill"
        case .trendingUp: "chart.line.uptrend.xyaxis"
        case .fileText: "doc.text.fill"
        case .banknote: "banknote.fill"
        case .helpCircle: "questionmark.circle.fill"
        case .dice: "dice.fill"
        case .arrowRightLeft: "arrow.left.arrow.right"
        case .airplane: "airplane"
        }
    }
}
