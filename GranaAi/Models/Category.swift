import Foundation

/// Classificação hierárquica de transação. Categoria raiz tem `parentId == nil`;
/// subcategorias apontam para a raiz via `parentId`.
///
/// **`icon` só na raiz:** decisão de produto — subcategorias herdam o ícone
/// do pai pra reduzir ruído visual. No banco, subcategoria tem `icon = NULL`;
/// a UI consulta o ícone do pai via `TransactionStore.icon(for:)`.
struct Category: Identifiable, Codable, Hashable {
    let id: UUID
    var parentId: UUID?
    var name: String
    var kind: CategoryKind
    var icon: CategoryIcon?
    let createdAt: Date
}

enum CategoryKind: String, Codable, CaseIterable {
    case expense
    case income
    case transfer

    var displayName: String {
        switch self {
        case .expense:  "Despesa"
        case .income:   "Receita"
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

    /// Nome do SF Symbol correspondente, pra usar em `Image(systemName:)`.
    var systemImage: String {
        switch self {
        case .dollarSign:     "dollarsign.circle.fill"
        case .shoppingBag:    "bag.fill"
        case .car:            "car.fill"
        case .monitor:        "tv.fill"
        case .utensils:       "fork.knife"
        case .zap:            "bolt.fill"
        case .creditCard:     "creditcard.fill"
        case .heart:          "heart.fill"
        case .shield:         "shield.fill"
        case .trendingUp:     "chart.line.uptrend.xyaxis"
        case .fileText:       "doc.text.fill"
        case .banknote:       "banknote.fill"
        case .helpCircle:     "questionmark.circle.fill"
        case .dice:           "dice.fill"
        case .arrowRightLeft: "arrow.left.arrow.right"
        }
    }
}
