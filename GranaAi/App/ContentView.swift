import SwiftUI

/// Seções principais do app, exibidas na sidebar do `NavigationSplitView`.
///
/// A sidebar é dividida em grupos via `SidebarGroup` (topo sem header,
/// depois "Economias", "Facilidades", "Ajustes"). A ordem visual é
/// determinada por `AppSection.groups`, não pela ordem do `enum`.
enum AppSection: String, Hashable, CaseIterable, Identifiable {
    case dashboard
    case summary
    case transactions
    case creditCards
    case accounts
    case planning
    case savings
    case investments
    case `import`
    case categorization
    case categories
    case institutions
    case advanced

    var id: String {
        rawValue
    }

    /// Ordem é **parte do contrato de UI**: os 9 primeiros itens nesta
    /// ordem ganham atalho `⌘1..⌘9` (ver `ContentView.shortcutOrder`).
    /// Reordenar aqui muda os atalhos do usuário silenciosamente.
    static let groups: [SidebarGroup] = [
        SidebarGroup(title: nil, items: [.dashboard, .summary, .transactions, .creditCards, .accounts]),
        SidebarGroup(title: "Economias", items: [.planning, .savings, .investments]),
        SidebarGroup(title: "Facilidades", items: [.import, .categorization]),
        SidebarGroup(title: "Ajustes", items: [.categories, .institutions, .advanced]),
    ]

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .summary: "Resumo"
        case .transactions: "Transações"
        case .creditCards: "Cartões de crédito"
        case .accounts: "Contas"
        case .planning: "Planejamento"
        case .savings: "Cofrinho"
        case .investments: "Investimentos"
        case .import: "Importar dados"
        case .categorization: "Categorização"
        case .categories: "Categorias"
        case .institutions: "Instituições"
        case .advanced: "Avançado"
        }
    }

    /// Ícone da seção. Delega pro `AppIcon` (catálogo central de chrome de UI)
    /// pra manter strings de SF Symbol num único lugar e evitar typos.
    var icon: AppIcon {
        switch self {
        case .dashboard: .sidebarDashboard
        case .summary: .sidebarSummary
        case .transactions: .sidebarTransactions
        case .creditCards: .sidebarCreditCards
        case .accounts: .sidebarAccounts
        case .planning: .sidebarPlanning
        case .savings: .sidebarSavings
        case .investments: .sidebarInvestments
        case .import: .sidebarImport
        case .categorization: .sidebarCategorization
        case .categories: .sidebarCategories
        case .institutions: .sidebarInstitutions
        case .advanced: .sidebarAdvanced
        }
    }
}

/// Grupo de itens da sidebar. `title` nulo significa "sem header" — usado
/// no primeiro bloco (Dashboard, Resumo, Transações, etc.) que fica solto no
/// topo sem rótulo.
struct SidebarGroup: Identifiable {
    let title: String?
    let items: [AppSection]
    var id: String {
        title ?? "_top"
    }
}

struct ContentView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Override de tema válido só pra sessão atual (não persistido). Toda
    /// abertura do app começa em `nil` (segue o sistema); o botão de tema
    /// na toolbar da sidebar flipa pra `.light`/`.dark` e o estado se perde
    /// ao fechar.
    @State private var themeOverride: ColorScheme?

    /// Lido pra decidir a direção do toggle quando ainda não há override.
    /// Reflete o tema efetivo da janela — sistema quando `themeOverride`
    /// é `nil`, ou o próprio override depois do primeiro clique.
    @Environment(\.colorScheme) private var currentScheme

    /// Restaurado entre sessões via `@SceneStorage` — abrir o app cai na
    /// última seção visitada (UX padrão macOS). `rawValue: String` é o que o
    /// SceneStorage persiste; reconstruímos o `AppSection` no getter abaixo.
    /// Default `.dashboard` cobre o primeiro lançamento + casos de raw value
    /// inválido (ex: enum mudou entre versões).
    @SceneStorage("ContentView.selection") private var selectionRaw: String = AppSection.dashboard.rawValue

    private var selection: AppSection {
        AppSection(rawValue: selectionRaw) ?? .dashboard
    }

    /// Binding pro `List(selection:)`. Optional porque o List aceita "nada
    /// selecionado" — tratamos `nil` como no-op pra preservar a última
    /// seleção válida (evita janela em branco se o sistema desselecionar).
    private var selectionBinding: Binding<AppSection?> {
        Binding(
            get: { AppSection(rawValue: selectionRaw) },
            set: { newValue in
                if let newValue { selectionRaw = newValue.rawValue }
            }
        )
    }

    /// Atalhos ⌘1..⌘9 — primeiras 9 seções na ordem visual da sidebar.
    /// Segue convenção do macOS (Safari, Mail, Notes usam ⌘1..⌘N pra
    /// alternar entre seções/abas/contas). As seções restantes ficam sem
    /// atalho — são acessadas via clique, e ⌘0 colide com "tamanho real"
    /// em vários contextos macOS.
    private static let shortcutOrder: [AppSection] =
        Array(AppSection.groups.flatMap(\.items).prefix(9))
    private static let shortcutKeys: [KeyEquivalent] =
        ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            Group {
                switch selection {
                case .dashboard: DashboardView()
                case .summary: placeholder(for: .summary)
                case .transactions: TransactionsView()
                case .creditCards: CreditCardsView()
                case .accounts: AccountsView()
                case .planning: placeholder(for: .planning)
                case .savings: placeholder(for: .savings)
                case .investments: placeholder(for: .investments)
                case .import: ImportHistoryView()
                case .categorization: CategorizationSettingsView()
                case .categories: CategoriesView()
                case .institutions: SupportedInstitutionsView()
                case .advanced: AdvancedSettingsView()
                }
            }
        }
        .navigationTitle("Grana AI")
        .preferredColorScheme(themeOverride)
        // Mínimo global da janela. A tela mais "gulosa" hoje é Cartões
        // (sidebar interna 240 + detalhe 520 = 760), somado à sidebar do
        // app (200), exige ~960. Arredondado pra 1000 dá folga; 640 de
        // altura mostra ~12 linhas de transação confortavelmente.
        .frame(minWidth: 1000, minHeight: 640)
        // Toasts globais de erro. Plugado aqui (raiz) pra cobrir qualquer
        // tela. Stores e services reportam via `NoticeCenter.shared.report(_:)`.
        .noticeOverlay()
    }

    private func toggleTheme() {
        themeOverride = (currentScheme == .dark) ? .light : .dark
    }

    /// Sidebar padrão do macOS: `List(selection:)` com `Label` nativo.
    /// Seleção, hover, navegação por teclado (setas ↑↓), background
    /// translúcido, suporte a Increase Contrast — tudo grátis do sistema.
    /// Highlight de seleção usa `AccentColor`.
    private var sidebar: some View {
        List(selection: selectionBinding) {
            ForEach(AppSection.groups) { group in
                Section {
                    ForEach(group.items) { section in
                        Label(section.title, systemImage: section.icon.systemImage)
                            .tag(section)
                    }
                } header: {
                    if let title = group.title {
                        Text(title)
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        .background {
            // Atalhos ⌘1..⌘9 — Buttons invisíveis que capturam os shortcuts
            // e setam a seleção. `Label` dentro do `List(selection:)` não
            // aceita `.keyboardShortcut` direto, daí o workaround.
            Group {
                ForEach(Array(zip(Self.shortcutOrder, Self.shortcutKeys)), id: \.0) { section, key in
                    Button(section.title) {
                        selectionRaw = section.rawValue
                    }
                    .keyboardShortcut(key, modifiers: .command)
                }
            }
            .hidden()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: toggleTheme) {
                    Label(
                        currentScheme == .dark ? "Tema claro" : "Tema escuro",
                        systemImage: currentScheme == .dark
                            ? AppIcon.themeLight.systemImage
                            : AppIcon.themeDark.systemImage
                    )
                }
                .help(currentScheme == .dark ? "Mudar para tema claro" : "Mudar para tema escuro")
            }
        }
    }

    private func placeholder(for section: AppSection) -> some View {
        EmptyStateView(
            "Em breve",
            icon: section.icon,
            description: "Esta seção entra numa próxima atualização."
        )
    }
}
