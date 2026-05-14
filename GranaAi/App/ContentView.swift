import SwiftUI

/// Seções principais do app, usadas pelo sidebar (Mac) e pela TabView (iPhone).
enum AppSection: String, Hashable, CaseIterable, Identifiable {
    case dashboard
    case accounts
    case transactions
    case investments
    case `import`
    case chat
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:    "Dashboard"
        case .accounts:     "Contas"
        case .transactions: "Transações"
        case .investments:  "Investimentos"
        case .import:       "Importações"
        case .chat:         "Chat IA"
        case .settings:     "Configurações"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:    "chart.pie.fill"
        case .accounts:     "wallet.pass.fill"
        case .transactions: "list.bullet.rectangle"
        case .investments:  "chart.line.uptrend.xyaxis"
        case .import:       "tray.and.arrow.down"
        case .chat:         "bubble.left.and.bubble.right"
        case .settings:     "gearshape"
        }
    }
}

struct ContentView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Lê o tema escolhido em `SettingsView` (mesma chave, sincronização
    /// automática via `UserDefaults`) pra aplicar no root via
    /// `.preferredColorScheme(_:)`.
    @AppStorage("appColorScheme") private var appColorScheme: AppColorScheme = .system

    // No iPhone usamos `TabView`. Decisão: um app financeiro pessoal alterna
    // muito entre "ver dashboard" e "adicionar gasto"; tabs deixam o tap pra
    // entrar nas Transações sempre a um toque, sem empilhar navegação.
    #if !os(macOS)
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label(AppSection.dashboard.title, systemImage: AppSection.dashboard.systemImage) }

            NavigationStack { TransactionsView() }
                .tabItem { Label(AppSection.transactions.title, systemImage: AppSection.transactions.systemImage) }

            NavigationStack { AccountsView() }
                .tabItem { Label(AppSection.accounts.title, systemImage: AppSection.accounts.systemImage) }

            NavigationStack { SettingsView() }
                .tabItem { Label(AppSection.settings.title, systemImage: AppSection.settings.systemImage) }
        }
        .preferredColorScheme(appColorScheme.colorScheme)
    }
    #else
    @State private var selection: AppSection = .dashboard

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                NavigationLink(value: section) {
                    Label(section.title, systemImage: section.systemImage)
                }
            }
            .navigationTitle("Grana AI")
            .frame(minWidth: 200)
        } detail: {
            // Restaura o dourado dentro do detail — `.tint(.brandPrimary)`
            // está aplicado na raiz do `NavigationSplitView` (abaixo) pra
            // o highlight da linha selecionada na sidebar ficar graphite,
            // mas botões/links do conteúdo seguem com o accent global gold.
            Group {
                switch selection {
                case .dashboard:    DashboardView()
                case .accounts:     AccountsView()
                case .transactions: TransactionsView()
                case .investments:  placeholder(for: .investments)
                case .import:       ImportHistoryView()
                case .chat:         placeholder(for: .chat)
                case .settings:     SettingsView()
                }
            }
            .tint(.brandSecondary)
        }
        // Tint graphite no `NavigationSplitView` raiz cobre o sidebar
        // selection highlight (que ignora `.tint()` aplicado só na `List`
        // no macOS — o sidebar lê o accent do contêiner pai).
        .tint(.brandPrimary)
        .navigationTitle("Grana AI")
        .preferredColorScheme(appColorScheme.colorScheme)
    }

    @ViewBuilder
    private func placeholder(for section: AppSection) -> some View {
        ContentUnavailableView(
            section.title,
            systemImage: section.systemImage,
            description: Text("Entra em uma fase futura do roadmap.")
        )
    }
    #endif
}

#Preview("Mac") {
    ContentView()
        .environment(AppEnvironment())
        .frame(width: 900, height: 600)
}

#Preview("iPhone") {
    ContentView()
        .environment(AppEnvironment())
}
