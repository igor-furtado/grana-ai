import SwiftUI

/// Catálogo central de SF Symbols usados como **chrome de UI** (sidebar nav,
/// toolbars, empty states, métricas, feedback de status). Ícones de **domínio**
/// vivem nos enums das próprias entidades — `CategoryIcon` (categoria),
/// `InstitutionKind` (instituição).
///
/// **Por que centralizar:** strings cruas de SF Symbol espalhadas pelas Views
/// criam três problemas — typo silencioso (só descobre em runtime, ícone some),
/// duplicação semântica (5 lugares usam "exclamationmark.triangle.fill" pra
/// significar "warning"), e troca de símbolo vira find-and-replace frágil.
/// O enum corrige tudo: compilador valida, intenção fica nomeada, troca = uma
/// linha no switch.
///
/// **Nomeação por intenção, não pelo símbolo.** Caso é `success`, não
/// `checkmarkCircle` — se amanhã trocarmos pro `checkmark.seal.fill`, o nome
/// do caso continua certo. Mesmo princípio do `CategoryIcon`.
enum AppIcon {
    // MARK: - Ações

    case add
    case edit
    case delete
    case undo
    case importFile
    case archive
    case unarchive
    case sort
    case inspectorToggle
    case more

    // MARK: - Métricas / dashboard

    case balance
    case expenseFlow
    case incomeFlow
    case netResult

    // MARK: - Empty states de charts do dashboard
    //
    // Um ícone por chart, escolhido pelo eixo semântico do gráfico — assim
    // três cards de chart vazios lado a lado mantêm pistas visuais distintas
    // do que cada um exibiria com dados.

    case chartCategoryRanking
    case chartIncomeExpense
    case chartWeekday

    // MARK: - Feedback de status

    case success
    case warning
    case error
    case info
    case unknown
    case completedSeal
    case invalidDate
    case invalidAmount

    // MARK: - Sidebar / Seções

    case sidebarDashboard
    case sidebarSummary
    case sidebarTransactions
    case sidebarCreditCards
    case sidebarAccounts
    case sidebarPlanning
    case sidebarSavings
    case sidebarInvestments
    case sidebarImport
    case sidebarCategorization
    case sidebarCategories
    case sidebarInstitutions
    case sidebarAdvanced

    // MARK: - Tema

    case themeLight
    case themeDark

    /// Nome do SF Symbol, pra `Image(systemName:)` ou `Label(_:systemImage:)`.
    var systemImage: String {
        switch self {
        // Ações
        case .add: "plus"
        case .edit: "pencil"
        case .delete: "trash"
        case .undo: "arrow.uturn.backward"
        case .importFile: "square.and.arrow.down"
        case .archive: "archivebox"
        case .unarchive: "tray.and.arrow.up"
        case .sort: "chevron.up.chevron.down"
        case .inspectorToggle: "sidebar.right"
        case .more: "ellipsis"
        // Métricas
        case .balance: "wallet.pass.fill"
        case .expenseFlow: "arrow.down.right.circle.fill"
        case .incomeFlow: "arrow.up.right.circle.fill"
        case .netResult: "chart.line.uptrend.xyaxis"
        // Charts do dashboard
        case .chartCategoryRanking: "chart.bar.xaxis"
        case .chartIncomeExpense: "arrow.up.arrow.down"
        case .chartWeekday: "calendar"
        // Status
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.circle.fill"
        case .info: "info.circle.fill"
        case .unknown: "questionmark.circle"
        case .completedSeal: "checkmark.seal.fill"
        case .invalidDate: "calendar.badge.exclamationmark"
        case .invalidAmount: "dollarsign.circle.trianglebadge.exclamationmark"
        // Sidebar
        case .sidebarDashboard: "chart.pie"
        case .sidebarSummary: "doc.text"
        case .sidebarTransactions: "list.bullet"
        case .sidebarCreditCards: "creditcard"
        case .sidebarAccounts: "building.columns"
        case .sidebarPlanning: "trophy"
        case .sidebarSavings: "mountain.2"
        case .sidebarInvestments: "chart.line.uptrend.xyaxis"
        case .sidebarImport: "tray.and.arrow.down"
        case .sidebarCategorization: "sparkles"
        case .sidebarCategories: "tag"
        case .sidebarInstitutions: "building.columns"
        case .sidebarAdvanced: "wrench.and.screwdriver"
        // Tema
        case .themeLight: "sun.max"
        case .themeDark: "moon"
        }
    }
}
