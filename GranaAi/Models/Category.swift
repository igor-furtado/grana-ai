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
/// **Nomes semânticos por categoria** (não pelo SF Symbol em si): facilita
/// trocar o glyph no futuro sem renomear a case (ex: trocar `dumbbell.fill`
/// por outro símbolo em `.exercise` muda só o `systemImage`, sem propagar
/// pra `CategoryIcon+Slug.swift` nem pro raw value persistido).
///
/// Renderização HIG-padrão é `.symbolRenderingMode(.hierarchical)` com
/// `.foregroundStyle(color.gradient)` — Apple usa esse pattern desde
/// macOS Sequoia em Music, Photos, Reminders, etc.
enum CategoryIcon: String, Codable, CaseIterable {
    case income
    case food
    case housing
    case exercise
    case dance
    case shopping
    case connectivity
    case personalCare
    case taxes
    case investments
    case entertainment
    case party
    case mobility
    case motorcycle
    case unclassified
    case withdrawal
    case health
    case professional
    case streaming
    case work
    case travel
    case transfer
    case education

    /// Nome do SF Symbol correspondente, pra usar em `Image(systemName:)`.
    var systemImage: String {
        switch self {
        case .income: "brazilianrealsign.circle.fill"
        case .food: "fork.knife"
        case .housing: "house.fill"
        case .exercise: "dumbbell.fill"
        case .dance: "figure.socialdance"
        case .shopping: "cart.fill"
        case .connectivity: "network"
        case .personalCare: "scissors"
        case .taxes: "creditcard.fill"
        case .investments: "chart.line.uptrend.xyaxis"
        case .entertainment: "theatermasks.fill"
        case .party: "party.popper.fill"
        case .mobility: "car.fill"
        case .motorcycle: "motorcycle.fill"
        case .unclassified: "questionmark.circle.fill"
        case .withdrawal: "banknote.fill"
        case .health: "heart.fill"
        case .professional: "figure.walk.suitcase.rolling"
        case .streaming: "play.rectangle.fill"
        case .work: "desktopcomputer"
        case .travel: "airplane"
        case .transfer: "repeat.circle.fill"
        case .education: "graduationcap.fill"
        }
    }
}
