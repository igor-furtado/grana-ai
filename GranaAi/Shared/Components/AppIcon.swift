import SwiftUI

/// Catálogo central de SF Symbols usados como **chrome de UI** (toolbars,
/// empty states, métricas, feedback de status). Ícones de **domínio** vivem
/// nos enums das próprias entidades — `CategoryIcon` (categoria),
/// `InstitutionKind` (instituição), `AppSection` (tab/sidebar).
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

    // MARK: - Métricas / dashboard
    case balance
    case expenseFlow
    case incomeFlow
    case netResult

    // MARK: - Feedback de status
    case success
    case warning
    case error
    case unknown
    case completedSeal
    case invalidDate
    case invalidAmount

    // MARK: - Empty states / conteúdo
    case walletEmpty
    case transactionsList
    case inbox
    case chart
    case categoryRankingEmpty
    case calendar
    case institution

    /// Nome do SF Symbol, pra `Image(systemName:)` ou `Label(_:systemImage:)`.
    var systemImage: String {
        switch self {
        // Ações
        case .add:              "plus"
        case .edit:             "pencil"
        case .delete:           "trash"
        case .undo:             "arrow.uturn.backward"
        case .importFile:       "square.and.arrow.down"
        case .archive:          "archivebox"
        case .unarchive:        "tray.and.arrow.up"
        case .sort:             "chevron.up.chevron.down"

        // Métricas
        case .balance:          "wallet.pass.fill"
        case .expenseFlow:      "arrow.down.right.circle.fill"
        case .incomeFlow:       "arrow.up.right.circle.fill"
        case .netResult:        "chart.line.uptrend.xyaxis"

        // Status
        case .success:          "checkmark.circle.fill"
        case .warning:          "exclamationmark.triangle.fill"
        case .error:            "xmark.circle.fill"
        case .unknown:          "questionmark.circle"
        case .completedSeal:    "checkmark.seal.fill"
        case .invalidDate:      "calendar.badge.exclamationmark"
        case .invalidAmount:    "dollarsign.circle.trianglebadge.exclamationmark"

        // Conteúdo / empty
        case .walletEmpty:          "wallet.pass"
        case .transactionsList:     "list.bullet.rectangle"
        case .inbox:                "tray"
        case .chart:                "chart.bar"
        case .categoryRankingEmpty: "chart.bar.fill"
        case .calendar:             "calendar"
        case .institution:          "building.columns"
        }
    }
}
