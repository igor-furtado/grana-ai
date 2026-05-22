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
    case institutions
    case categorization
    case theme

    var id: String { rawValue }

    /// Itens fixos no topo da sidebar.
    static let topItems: [AppSection] = [.dashboard, .transactions, .investments, .import, .chat]

    /// Itens sob a seção "Configurações" da sidebar.
    static let settingsItems: [AppSection] = [.categories, .accounts, .institutions, .categorization, .theme]

    var title: String {
        switch self {
        case .dashboard:      "Dashboard"
        case .transactions:   "Transações"
        case .investments:    "Investimentos"
        case .import:         "Importações"
        case .chat:           "Chat IA"
        case .categories:     "Categorias"
        case .accounts:       "Contas"
        case .institutions:   "Bancos suportados"
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
        case .institutions:   "building.columns"
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
            sidebar
        } detail: {
            Group {
                switch selection {
                case .dashboard:    DashboardView()
                case .transactions: TransactionsView()
                case .investments:  placeholder(for: .investments)
                case .import:       ImportHistoryView()
                case .chat:         placeholder(for: .chat)
                case .categories:     CategoriesView()
                case .accounts:       AccountsView()
                case .institutions:   SupportedInstitutionsView()
                case .categorization: CategorizationSettingsView()
                case .theme:          ThemeView()
                }
            }
            .tint(.brandSecondary)
        }
        .navigationTitle("Grana AI")
        .preferredColorScheme(appColorScheme.colorScheme)
        // Toasts globais de erro. Plugado aqui (raiz) pra cobrir qualquer
        // tela. Stores e services reportam via `ErrorCenter.shared.report(_:)`.
        .errorToastOverlay()
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
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(AppSection.topItems) { section in
                    sidebarRow(section)
                }

                Text("Configurações")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(.horizontal, 10)
                    .padding(.top, 18)
                    .padding(.bottom, 4)

                ForEach(AppSection.settingsItems) { section in
                    sidebarRow(section)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(Color.brandPrimary)
        .frame(minWidth: 200)
        .focusable()
        .onMoveCommand { direction in
            moveSelection(direction)
        }
    }

    private func sidebarRow(_ section: AppSection) -> some View {
        let isSelected = selection == section
        return Button {
            selection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.body)
                    .frame(width: 18)
                Text(section.title)
                    .font(.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.brandPrimary : Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.white : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Lista flat ordenada: top + settings. Usada só pra resolver "próximo /
    /// anterior" no `onMoveCommand` — a ordem visual já é essa.
    private var orderedSections: [AppSection] {
        AppSection.topItems + AppSection.settingsItems
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let ordered = orderedSections
        guard let idx = ordered.firstIndex(of: selection) else { return }
        switch direction {
        case .up   where idx > 0:                  selection = ordered[idx - 1]
        case .down where idx < ordered.count - 1:  selection = ordered[idx + 1]
        default: break
        }
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
