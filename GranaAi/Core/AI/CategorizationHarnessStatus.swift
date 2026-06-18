import Foundation
import Observation

@MainActor
@Observable
final class CategorizationHarnessStatusCenter {
    struct Issue: Equatable {
        let title: String
        let message: String
    }

    static let shared = CategorizationHarnessStatusCenter()

    private(set) var issue: Issue?

    private init() {}

    func markUnavailable(message: String) {
        issue = Issue(
            title: "Categorização online indisponível",
            message: message
        )
    }

    func clear() {
        issue = nil
    }
}

enum CategorizationHarnessSupport {
    static let recoveryMessage =
        "A categorização assistida vai cair em Não Classificado até o serviço online voltar a responder."

    static func isHarnessIssue(_ error: Error) -> Bool {
        guard let aiError = error as? AIError else { return false }
        switch aiError {
        case .invalidConfiguration, .requestFailed, .invalidResponse, .httpStatus,
             .responseParse, .decoding:
            return true
        case .unknownCategorySlug, .cancelled:
            return false
        }
    }

    @MainActor
    static func recoveryAction() -> NoticeCenter.Action {
        NoticeCenter.Action(title: "Abrir Categorização") {
            AppSectionNavigation.open(.categorization)
        }
    }
}
