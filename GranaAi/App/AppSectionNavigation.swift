import Foundation

extension Notification.Name {
    static let appSectionNavigationRequested = Notification.Name("GranaAi.appSectionNavigationRequested")
}

enum AppSectionNavigation {
    static func open(_ section: AppSection) {
        NotificationCenter.default.post(
            name: .appSectionNavigationRequested,
            object: section.rawValue
        )
    }
}
