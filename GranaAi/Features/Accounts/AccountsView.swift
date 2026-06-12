import Foundation
import SwiftUI

/// Lista de contas correntes em grid de cards. Reativa via `AccountStore.start()`
/// — saldos, contas e instituições streamam em paralelo e a UI re-renderiza
/// via `@Observable`. Create/edit acontecem em **sheet modal**
/// (`.sheet(item:)`) — padrão idiomático macOS pra esse tipo de fluxo.
///
/// **Filtra cartões fora.** A partir da Fase 4.6, cartões vivem na tela
/// dedicada `CreditCardsView` (entrada própria na sidebar). Esta tela cuida
/// apenas de `type == .checking`. O form é o mesmo `AccountFormView`, invocado
/// com `lockedType: .checking` pra esconder o picker de tipo.
///
/// **Seleção:** clicar num card seleciona ele (stroke de accent). Ações de
/// editar/arquivar/apagar agem no card selecionado e vivem na window toolbar.
/// Context menu (right-click) duplica as ações pra acesso rápido sem precisar
/// selecionar primeiro.
struct AccountsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var store: AccountStore?
    @State private var formMode: FormMode?
    @State private var showArchived = false
    @State private var selectedAccountId: UUID?
    @State private var showDeleteConfirm = false

    /// `Identifiable` pra alimentar o `.sheet(item:)` — o id distingue
    /// "novo" de cada edição específica, garantindo que trocar de "editar
    /// conta A" pra "editar conta B" remonte o form (estado limpo).
    enum FormMode: Identifiable {
        case create
        case edit(Account)

        var id: String {
            switch self {
            case .create: return "create"
            case let .edit(account): return "edit-\(account.id.uuidString)"
            }
        }
    }

    var body: some View {
        Group {
            if let store {
                content(store: store)
                    .task { await store.start() }
                    .toolbar { toolbarContent(store: store) }
            } else {
                ProgressView()
                    .task { store = AccountStore(container: environment.container) }
            }
        }
        .navigationTitle("Contas")
        .navigationSubtitle(subtitle)
    }

    @ViewBuilder
    private func content(store: AccountStore) -> some View {
        let visibleAccounts = visible(store: store)
        Group {
            if visibleAccounts.isEmpty {
                // Fora do `ScrollView` pra que `maxHeight: .infinity` centralize
                // verticalmente no espaço disponível — dentro de um ScrollView
                // a altura é intrínseca e o estado vazio gruda no topo.
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                grid(store: store, accounts: visibleAccounts)
            }
        }
        // Form sheet aparece centralizado e dimming no fundo — padrão macOS
        // pra create/edit. `.sheet(item:)` re-monta o conteúdo a cada novo
        // `formMode` (id muda), garantindo estado limpo entre aberturas.
        .sheet(item: $formMode) { mode in
            AccountFormView(
                existing: editingAccount(from: mode),
                lockedType: .checking,
                onCancel: { formMode = nil },
                onSaved: { formMode = nil }
            )
            .environment(store)
        }
        .confirmationDialog(
            "Apagar conta?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Apagar", role: .destructive) {
                guard let id = selectedAccountId else { return }
                Task { try? await store.delete(id: id) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(
                "Transações vinculadas continuarão no banco mas ficarão órfãs. Considere arquivar em vez de apagar."
            )
        }
        .onChange(of: visibleAccounts.map(\.id)) { _, ids in
            reconcileSelection(visibleIds: ids)
        }
    }

    private func grid(store: AccountStore, accounts: [Account]) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 16)],
                spacing: 16
            ) {
                ForEach(accounts) { account in
                    AccountCard(
                        account: account,
                        displayName: store.displayName(for: account),
                        institution: store.institution(forAccount: account),
                        currentBalance: store.currentBalance(for: account),
                        isSelected: account.id == selectedAccountId,
                        onSelect: { selectedAccountId = account.id },
                        onEdit: {
                            selectedAccountId = account.id
                            formMode = .edit(account)
                        },
                        onToggleArchive: {
                            Task { try? await store.setArchived(account, archived: !account.archived) }
                        },
                        onRequestDelete: {
                            selectedAccountId = account.id
                            showDeleteConfirm = true
                        }
                    )
                }
            }
            .padding(20)
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent(store: AccountStore) -> some ToolbarContent {
        let accounts = visible(store: store)
        let selected = accounts.first(where: { $0.id == selectedAccountId })

        // `ToolbarSpacer(.fixed, ...)` quebra a pílula única que o SwiftUI
        // faz pra items adjacentes no mesmo placement. Resulta em 3 grupos
        // visuais distintos no trailing edge — padrão Liquid Glass do macOS 26+.
        if let selected {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    formMode = .edit(selected)
                } label: {
                    Label("Editar", systemImage: AppIcon.edit.systemImage)
                }
                .help("Editar conta")

                Button {
                    Task {
                        try? await store.setArchived(selected, archived: !selected.archived)
                    }
                } label: {
                    Label(
                        selected.archived ? "Desarquivar" : "Arquivar",
                        systemImage: selected.archived
                            ? AppIcon.unarchive.systemImage
                            : AppIcon.archive.systemImage
                    )
                }
                .help(selected.archived ? "Desarquivar conta" : "Arquivar conta")

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Apagar", systemImage: AppIcon.delete.systemImage)
                }
                .help("Apagar conta")
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                formMode = .create
            } label: {
                Label("Nova conta", systemImage: AppIcon.add.systemImage)
            }
            .help("Nova conta")
        }

        if hasArchivedAccount {
            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle("Mostrar arquivadas", isOn: $showArchived)
                } label: {
                    Label("Mais", systemImage: AppIcon.more.systemImage)
                }
            }
        }
    }

    private var subtitle: String {
        guard let store else { return "" }
        let count = visible(store: store).count
        if count == 0 { return "Nenhuma conta cadastrada" }
        if count == 1 { return "1 conta cadastrada" }
        return "\(count) contas cadastradas"
    }

    /// `true` quando pelo menos uma conta corrente está arquivada. Gateia a
    /// exibição do toggle "Mostrar arquivadas" — esconde quando não há nada
    /// arquivado no escopo desta tela.
    private var hasArchivedAccount: Bool {
        store?.accounts.contains { $0.type == .checking && $0.archived } ?? false
    }

    /// Limpa seleção quando a conta selecionada some da lista visível
    /// (apagada, arquivada com toggle desligado, etc.). Diferente da
    /// `CreditCardsView`, não auto-seleciona o primeiro — em grid, seleção
    /// é sempre opt-in via clique do usuário.
    private func reconcileSelection(visibleIds: [UUID]) {
        guard let current = selectedAccountId, !visibleIds.contains(current) else { return }
        selectedAccountId = nil
    }

    private var emptyState: some View {
        EmptyStateView(
            "Sem contas por aqui",
            icon: .sidebarAccounts,
            description: "Cadastre as contas correntes que você usa (Inter, Nubank, XP, etc.) pra vincular transações e organizar suas movimentações."
        ) {
            Button {
                formMode = .create
            } label: {
                Label("Cadastrar primeira conta", systemImage: AppIcon.add.systemImage)
            }
            .buttonStyle(.borderedProminent)
            .disabled(formMode != nil)
        }
    }

    private func visible(store: AccountStore) -> [Account] {
        store.accounts.filter { account in
            guard account.type == .checking else { return false }
            return showArchived ? true : !account.archived
        }
    }

    private func editingAccount(from mode: FormMode) -> Account? {
        if case let .edit(account) = mode { return account }
        return nil
    }
}

// MARK: - Card

private struct AccountCard: View {
    let account: Account
    let displayName: String
    let institution: Institution?
    let currentBalance: Decimal
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onToggleArchive: () -> Void
    let onRequestDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(accentColor)
                .frame(height: 4)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    accountIcon
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(displayName)
                            .font(.headline)
                        if account.archived {
                            Text("arquivada")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(Color.secondary.opacity(0.15))
                                )
                        }
                    }
                    Text("SALDO ATUAL")
                        .font(.caption2)
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }

                Text(currentBalance.formatted(.currency(code: account.currency)))
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(balanceColor)
            }
            .padding(14)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.15),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .opacity(account.archived ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        // Context menu duplica as ações da toolbar pra acesso rápido por
        // right-click — sem precisar selecionar primeiro. Apagar passa por
        // `onRequestDelete` que seleciona a conta e abre o confirm a nível
        // de tela.
        .contextMenu {
            Button("Editar", action: onEdit)
            Button(account.archived ? "Desarquivar" : "Arquivar", action: onToggleArchive)
            Divider()
            Button("Apagar", role: .destructive, action: onRequestDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var accentColor: Color {
        institution?.kind.brandColor ?? defaultAccent
    }

    private var defaultAccent: Color {
        switch account.type {
        case .creditCard: return .transfer
        default: return .accentColor
        }
    }

    /// Ícone da conta. Quando tem `Institution`, usa o avatar da marca
    /// (`InstitutionIcon`). Sem instituição (caso degenerado pós-Fase 4.5),
    /// cai num SF Symbol por tipo de conta sobre o tint do `accentColor`.
    @ViewBuilder
    private var accountIcon: some View {
        if let institution {
            InstitutionIcon(kind: institution.kind, size: 44)
        } else {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                Image(systemName: fallbackIconName)
                    .font(.title2)
                    .foregroundStyle(accentColor)
            }
            .frame(width: 44, height: 44)
        }
    }

    private var fallbackIconName: String {
        switch account.type {
        case .checking: return "building.columns"
        case .creditCard: return "creditcard.fill"
        }
    }

    private var balanceColor: Color {
        if account.archived { return .secondary }
        if currentBalance < 0 { return .danger }
        return .primary
    }
}
