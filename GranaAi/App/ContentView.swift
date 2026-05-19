import SwiftUI

/// Seções principais do app, exibidas na sidebar do `NavigationSplitView`.
///
/// **Top vs. configurações:** os cases de `topItems` ficam soltos no topo
/// da sidebar — uso frequente, viagem direta. Os de `settingsItems` ficam
/// agrupados sob a seção "Configurações" — uso ocasional, raramente
/// trocados. A separação evita um sidebar de 8 itens "achatado" onde
/// Tema e Dashboard têm o mesmo peso visual.
enum AppSection: String, Hashable, CaseIterable, Identifiable {
    case dashboard
    case transactions
    case investments
    case `import`
    case chat
    case categories
    case accounts
    case categorization
    case theme

    var id: String { rawValue }

    /// Itens fixos no topo da sidebar.
    static let topItems: [AppSection] = [.dashboard, .transactions, .investments, .import, .chat]

    /// Itens sob a seção "Configurações" da sidebar.
    static let settingsItems: [AppSection] = [.categories, .accounts, .categorization, .theme]

    var title: String {
        switch self {
        case .dashboard:      "Dashboard"
        case .transactions:   "Transações"
        case .investments:    "Investimentos"
        case .import:         "Importações"
        case .chat:           "Chat IA"
        case .categories:     "Categorias"
        case .accounts:       "Contas"
        case .categorization: "Categorização"
        case .theme:          "Tema"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:      "chart.pie.fill"
        case .transactions:   "list.bullet.rectangle"
        case .investments:    "chart.line.uptrend.xyaxis"
        case .import:         "tray.and.arrow.down"
        case .chat:           "bubble.left.and.bubble.right"
        case .categories:     "tag.fill"
        case .accounts:       "wallet.pass.fill"
        case .categorization: "sparkles"
        case .theme:          "paintpalette.fill"
        }
    }
}

struct ContentView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Lê o tema escolhido em `ThemeView` (mesma chave, sincronização
    /// automática via `UserDefaults`) pra aplicar no root via
    /// `.preferredColorScheme(_:)`.
    @AppStorage("appColorScheme") private var appColorScheme: AppColorScheme = .system

    @State private var selection: AppSection = .dashboard

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(AppSection.topItems) { section in
                    NavigationLink(value: section) {
                        Label(section.title, systemImage: section.systemImage)
                    }
                }

                Section("Configurações") {
                    ForEach(AppSection.settingsItems) { section in
                        NavigationLink(value: section) {
                            Label(section.title, systemImage: section.systemImage)
                        }
                    }
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
                case .transactions: TransactionsView()
                case .investments:  placeholder(for: .investments)
                case .import:       ImportHistoryView()
                case .chat:         placeholder(for: .chat)
                case .categories:     CategoriesView()
                case .accounts:       AccountsView()
                case .categorization: CategorizationSettingsView()
                case .theme:          ThemeView()
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
        // Toasts globais de erro. Plugado aqui (raiz) pra cobrir qualquer
        // tela. Stores e services reportam via `ErrorCenter.shared.report(_:)`.
        .errorToastOverlay()
    }

    @ViewBuilder
    private func placeholder(for section: AppSection) -> some View {
        ContentUnavailableView(
            section.title,
            systemImage: section.systemImage,
            description: Text("Entra em uma fase futura do roadmap.")
        )
    }
}

#Preview {
    ContentView()
        .environment(AppEnvironment())
        .frame(width: 900, height: 600)
}
