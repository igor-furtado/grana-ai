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

    var id: String {
        rawValue
    }

    static let groups: [SidebarGroup] = [
        SidebarGroup(title: nil, items: [.dashboard, .summary, .transactions, .creditCards, .accounts]),
        SidebarGroup(title: "Economias", items: [.planning, .savings, .investments]),
        SidebarGroup(title: "Facilidades", items: [.import, .categorization]),
        SidebarGroup(title: "Ajustes", items: [.categories, .institutions]),
    ]

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .summary: "Resumo"
        case .transactions: "Extrato"
        case .creditCards: "Cartões de crédito"
        case .accounts: "Contas"
        case .planning: "Planejamento"
        case .savings: "Cofrinho"
        case .investments: "Investimentos"
        case .import: "Importar dados"
        case .categorization: "Categorização"
        case .categories: "Categorias"
        case .institutions: "Instituições"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "chart.pie"
        case .summary: "doc.text"
        case .transactions: "list.bullet.rectangle"
        case .creditCards: "creditcard"
        case .accounts: "wallet.pass"
        case .planning: "target"
        case .savings: "banknote"
        case .investments: "chart.line.uptrend.xyaxis"
        case .import: "tray.and.arrow.down"
        case .categorization: "sparkles"
        case .categories: "tag"
        case .institutions: "building.columns"
        }
    }
}

/// Grupo de itens da sidebar. `title` nulo significa "sem header" — usado
/// no primeiro bloco (Dashboard, Resumo, Extrato, etc.) que fica solto no
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
    /// abertura do app começa em `nil` (segue o sistema); o botão do topo
    /// da sidebar flipa pra `.light`/`.dark` e o estado se perde ao fechar.
    @State private var themeOverride: ColorScheme?

    /// Lido pra decidir a direção do toggle quando ainda não há override.
    /// Reflete o tema efetivo da janela — sistema quando `themeOverride`
    /// é `nil`, ou o próprio override depois do primeiro clique. Lido aqui
    /// no nível do `ContentView` (e não dentro do `sidebar`) porque a
    /// sidebar força `.environment(\.colorScheme, .dark)` no próprio escopo.
    @Environment(\.colorScheme) private var currentScheme

    @State private var selection: AppSection = .dashboard

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            Group {
                switch selection {
                case .dashboard: DashboardView()
                case .summary: placeholder(for: .summary)
                case .transactions: TransactionsView()
                case .creditCards: placeholder(for: .creditCards)
                case .accounts: AccountsView()
                case .planning: placeholder(for: .planning)
                case .savings: placeholder(for: .savings)
                case .investments: placeholder(for: .investments)
                case .import: ImportHistoryView()
                case .categorization: CategorizationSettingsView()
                case .categories: CategoriesView()
                case .institutions: SupportedInstitutionsView()
                }
            }
            .tint(.brandSecondary)
        }
        .navigationTitle("Grana AI")
        .preferredColorScheme(themeOverride)
        // Toasts globais de erro. Plugado aqui (raiz) pra cobrir qualquer
        // tela. Stores e services reportam via `ErrorCenter.shared.report(_:)`.
        .errorToastOverlay()
    }

    private func toggleTheme() {
        themeOverride = (currentScheme == .dark) ? .light : .dark
    }

    /// Sidebar custom — Buttons em vez de `List(selection:)`. Motivo: na
    /// `NavigationSplitView` do macOS, a cor do highlight da linha
    /// selecionada vem do asset `AccentColor` (e `.tint(...)` é ignorado
    /// nesse ponto). Como aqui queremos a seleção branca **sem** mudar o
    /// AccentColor global (que afetaria foco de TextField, default buttons,
    /// etc.), abandonamos o sistema de seleção do List e renderizamos o
    /// destaque na unha via `background` condicionado a `selection`.
    ///
    /// **Trade-off aceito:** a navegação por seta cima/baixo do `List` nativo
    /// é substituída pelo handler `onMoveCommand` abaixo, focusável no
    /// container. VoiceOver enxerga cada item como Button com `accessibilityLabel`
    /// — perde o "row N of M" do List, mas anuncia título + estado de seleção.
    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(AppSection.groups) { group in
                        if let header = group.title {
                            Text(header)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.45))
                                .padding(.horizontal, 10)
                                .padding(.top, 18)
                                .padding(.bottom, 4)
                        }

                        ForEach(group.items) { section in
                            SidebarRow(section: section, isSelected: selection == section) {
                                selection = section
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)

            sidebarBottomBar
        }
        // `sidebarBackground` é um asset SEM variante dark — fica grafite
        // sempre. `brandPrimary` flipa pra creme no tema dark (intencional pro
        // resto do app, mas a sidebar precisa permanecer escura).
        .background(Color.sidebarBackground)
        .frame(minWidth: 200)
        // Força colorScheme dark aqui pra que o toggle nativo de sidebar (e
        // qualquer outro control herdado do sistema) renderize com ícones
        // claros, visíveis contra o fundo escuro fixo.
        .environment(\.colorScheme, .dark)
        .focusable()
        // Sem o `.focusEffectDisabled`, o focus ring nativo (cor = AccentColor,
        // gold) desenha um retângulo dourado ao redor da sidebar inteira sempre
        // que ela recebe foco. `.focusable` continua ativo pra capturar
        // `onMoveCommand` (setas), só removemos o highlight visual.
        .focusEffectDisabled()
        .onMoveCommand { direction in
            moveSelection(direction)
        }
    }

    /// Faixa fixa no rodapé da sidebar pra ícones de ação rápida. Hoje só
    /// hospeda o toggle de tema; o `HStack` com `Spacer` no final deixa o
    /// crescimento futuro acontecer sem rearranjo (basta adicionar botões
    /// antes do `Spacer`).
    private var sidebarBottomBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.white.opacity(0.08))

            HStack(spacing: 4) {
                Spacer(minLength: 0)

                SidebarIconButton(
                    icon: currentScheme == .dark ? .themeLight : .themeDark,
                    help: currentScheme == .dark ? "Mudar para tema claro" : "Mudar para tema escuro",
                    accessibilityLabel: "Alternar tema",
                    action: toggleTheme
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    /// Lista flat ordenada na sequência visual da sidebar. Usada só pra
    /// resolver "próximo / anterior" no `onMoveCommand`.
    private var orderedSections: [AppSection] {
        AppSection.groups.flatMap(\.items)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let ordered = orderedSections
        guard let idx = ordered.firstIndex(of: selection) else { return }
        switch direction {
        case .up where idx > 0: selection = ordered[idx - 1]
        case .down where idx < ordered.count - 1: selection = ordered[idx + 1]
        default: break
        }
    }

    private func placeholder(for section: AppSection) -> some View {
        ContentUnavailableView(
            section.title,
            systemImage: section.systemImage,
            description: Text("Entra em uma fase futura do roadmap.")
        )
    }
}

/// Linha da sidebar como `View` própria (em vez de função em `ContentView`)
/// pra cada instância carregar seu próprio `@State` de hover — sem isso,
/// um único flag controlaria todas as linhas ao mesmo tempo.
private struct SidebarRow: View {
    let section: AppSection
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.body)
                    .frame(width: 18)
                Text(section.title)
                    .font(.body)
                Spacer(minLength: 0)
            }
            // `sidebarBackground` (grafite fixo) é o oposto do fundo branco do
            // item selecionado — `brandPrimary` flipa pra creme no env dark e
            // sumiria contra o highlight.
            .foregroundStyle(isSelected ? Color.sidebarBackground : Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowBackground)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var rowBackground: Color {
        if isSelected { return .white }
        if isHovering { return Color.white.opacity(0.1) }
        return .clear
    }
}

/// Botão de ícone da faixa inferior da sidebar. Mesmo motivo da
/// `SidebarRow` pra ser uma `View` própria: cada botão precisa do seu
/// `@State` de hover.
private struct SidebarIconButton: View {
    let icon: AppIcon
    let help: String
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon.systemImage)
                .font(.body)
                .foregroundStyle(Color.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering ? Color.white.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    ContentView()
        .environment(AppEnvironment())
        .frame(width: 900, height: 600)
}
