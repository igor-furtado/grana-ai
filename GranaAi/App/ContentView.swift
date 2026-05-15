import SwiftUI

/// Seções principais do app, usadas pelo sidebar (Mac) e pela TabView (iPhone).
///
/// **Top vs. configurações:** os cases de `top` ficam soltos no topo da
/// sidebar — uso frequente, viagem direta. Os de `settings` ficam agrupados
/// sob a seção "Configurações" — uso ocasional, raramente trocados. A
/// separação evita um sidebar de 8 itens "achatado" onde Tema e Dashboard
/// têm o mesmo peso visual.
enum AppSection: String, Hashable, CaseIterable, Identifiable {
    case dashboard
    case transactions
    case investments
    case `import`
    case chat
    case categories
    case accounts
    case theme
    /// Tab-only no iPhone: abre a `SettingsView` (hub que lista Categorias,
    /// Contas e Tema). No Mac não tem equivalente — a sidebar usa a
    /// `Section("Configurações")` agrupando direto os 3 itens, sem hub.
    /// Fora dos arrays `topItems`/`settingsItems` de propósito: não vira
    /// linha de sidebar no Mac.
    case settings

    var id: String { rawValue }

    /// Itens fixos no topo da sidebar (e tabs no iPhone).
    static let topItems: [AppSection] = [.dashboard, .transactions, .investments, .import, .chat]

    /// Itens sob a seção "Configurações" da sidebar (no iPhone aparecem
    /// dentro do hub `SettingsView` acessado pelo `case .settings`).
    static let settingsItems: [AppSection] = [.categories, .accounts, .theme]

    var title: String {
        switch self {
        case .dashboard:    "Dashboard"
        case .transactions: "Transações"
        case .investments:  "Investimentos"
        case .import:       "Importações"
        case .chat:         "Chat IA"
        case .categories:   "Categorias"
        case .accounts:     "Contas"
        case .theme:        "Tema"
        case .settings:     "Configurações"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:    "chart.pie.fill"
        case .transactions: "list.bullet.rectangle"
        case .investments:  "chart.line.uptrend.xyaxis"
        case .import:       "tray.and.arrow.down"
        case .chat:         "bubble.left.and.bubble.right"
        case .categories:   "tag.fill"
        case .accounts:     "wallet.pass.fill"
        case .theme:        "paintpalette.fill"
        case .settings:     "gearshape"
        }
    }
}

struct ContentView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Lê o tema escolhido em `ThemeView` (mesma chave, sincronização
    /// automática via `UserDefaults`) pra aplicar no root via
    /// `.preferredColorScheme(_:)`.
    @AppStorage("appColorScheme") private var appColorScheme: AppColorScheme = .system

    // No iPhone usamos `TabView`. Decisão: um app financeiro pessoal alterna
    // muito entre "ver dashboard" e "adicionar gasto"; tabs deixam o tap pra
    // entrar nas Transações sempre a um toque, sem empilhar navegação.
    //
    // O tab "Configurações" abre o `SettingsView` (hub) — Categorias, Contas
    // e Tema vivem lá dentro como `NavigationLink`. Contas saiu do topo (era
    // tab antes) porque é uso menos frequente que Dashboard/Transações.
    #if !os(macOS)
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label(AppSection.dashboard.title, systemImage: AppSection.dashboard.systemImage) }

            NavigationStack { TransactionsView() }
                .tabItem { Label(AppSection.transactions.title, systemImage: AppSection.transactions.systemImage) }

            NavigationStack { SettingsView() }
                .tabItem { Label(AppSection.settings.title, systemImage: AppSection.settings.systemImage) }
        }
        .preferredColorScheme(appColorScheme.colorScheme)
    }
    #else
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
                case .categories:   CategoriesView()
                case .accounts:     AccountsView()
                case .theme:        ThemeView()
                // `.settings` é iPhone-only (não está em `top` nem em
                // `settings`, portanto nunca chega aqui via sidebar). Cobrir
                // o case só pra deixar o switch exhaustive e não usar @unknown.
                case .settings:     EmptyView()
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
