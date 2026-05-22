import Foundation
import SwiftUI

/// Lista de contas em grid de cards, com form inline. Reativa via
/// `AccountStore.start()` — saldos, contas e instituições streamam em
/// paralelo e a UI re-renderiza via `@Observable`.
///
/// Diferença pro Finest: aqui distinguimos **Conta** (livre, criada pelo
/// usuário) de **Banco** (catálogo fixo via `InstitutionKind`). O card de
/// uma conta puxa logo + cor da Institution associada — a identidade
/// visual não é editável por conta.
struct AccountsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var store: AccountStore?
    @State private var formMode: FormMode?
    @State private var showArchived = false

    enum FormMode {
        case create
        case edit(Account)
    }

    var body: some View {
        Group {
            if let store {
                content(store: store)
                    .task { await store.start() }
            } else {
                ProgressView()
                    .task { store = AccountStore(container: environment.container) }
            }
        }
        .navigationTitle("Contas")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    formMode = .create
                } label: {
                    Label("Nova conta", systemImage: AppIcon.add.systemImage)
                }
                .disabled(formMode != nil)
            }
            ToolbarItem(placement: .secondaryAction) {
                Toggle("Mostrar arquivadas", isOn: $showArchived)
            }
        }
    }

    @ViewBuilder
    private func content(store: AccountStore) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let formMode {
                    AccountFormView(
                        existing: editingAccount(from: formMode),
                        onCancel: { self.formMode = nil },
                        onSaved: { self.formMode = nil }
                    )
                    // `.id(...)` força remontagem (estado limpo + `onAppear`
                    // re-disparado) quando o usuário troca de "novo" pra
                    // "editar conta X", ou entre duas edições. Sem isso, a
                    // mesma instância do form se mantém com `@State` velho.
                    .id(formIdentity(for: formMode))
                    .environment(store)
                }
                listOrEmpty(store: store)
            }
            .padding(20)
        }
    }

    private var subtitle: String {
        guard let store else { return "" }
        let count = visible(store: store).count
        if count == 0 { return "Nenhuma conta cadastrada" }
        if count == 1 { return "1 conta cadastrada" }
        return "\(count) contas cadastradas"
    }

    @ViewBuilder
    private func listOrEmpty(store: AccountStore) -> some View {
        let visibleAccounts = visible(store: store)
        if visibleAccounts.isEmpty {
            emptyState
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 16)],
                spacing: 16
            ) {
                ForEach(visibleAccounts) { account in
                    AccountCard(
                        account: account,
                        institution: store.institution(forAccount: account),
                        currentBalance: store.currentBalance(for: account),
                        onEdit: { formMode = .edit(account) },
                        onDelete: { Task { try? await store.delete(id: account.id) } },
                        onToggleArchive: {
                            Task { try? await store.setArchived(account, archived: !account.archived) }
                        }
                    )
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: AppIcon.institution.systemImage)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Nenhuma conta cadastrada")
                .font(.title3.weight(.semibold))
            Text("Cadastre as contas que você usa (Inter, Nubank, carteira, etc.) para vincular transações e organizar suas movimentações.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button {
                formMode = .create
            } label: {
                Label("Cadastrar primeira conta", systemImage: AppIcon.add.systemImage)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.brandSecondary)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(formMode != nil)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                )
        )
    }

    private func visible(store: AccountStore) -> [Account] {
        store.accounts.filter { showArchived ? true : !$0.archived }
    }

    private func editingAccount(from mode: FormMode) -> Account? {
        if case .edit(let account) = mode { return account }
        return nil
    }

    private func formIdentity(for mode: FormMode) -> String {
        switch mode {
        case .create:           return "create"
        case .edit(let account): return "edit-\(account.id.uuidString)"
        }
    }
}

// MARK: - Card

private struct AccountCard: View {
    let account: Account
    let institution: Institution?
    let currentBalance: Decimal
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleArchive: () -> Void

    @State private var isHovered = false
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(accentColor)
                .frame(height: 4)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.15))
                        accountIcon
                    }
                    .frame(width: 44, height: 44)

                    Spacer()

                    if isHovered {
                        HStack(spacing: 6) {
                            iconButton(systemImage: AppIcon.edit.systemImage, help: "Editar", action: onEdit)
                            iconButton(systemImage: account.archived ? AppIcon.unarchive.systemImage : AppIcon.archive.systemImage,
                                       help: account.archived ? "Desarquivar" : "Arquivar",
                                       action: onToggleArchive)
                            iconButton(systemImage: AppIcon.delete.systemImage, help: "Apagar") {
                                showDeleteConfirm = true
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(account.name)
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
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .opacity(account.archived ? 0.6 : 1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        // Espelho das ações hover-only via context menu. Garante acesso por
        // teclado (Control+click) e right-click pra quem não dispara hover.
        .contextMenu {
            Button("Editar", action: onEdit)
            Button(account.archived ? "Desarquivar" : "Arquivar", action: onToggleArchive)
            Divider()
            Button("Apagar", role: .destructive) { showDeleteConfirm = true }
        }
        .confirmationDialog(
            "Apagar conta “\(account.name)”?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Apagar", role: .destructive, action: onDelete)
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Transações vinculadas continuarão no banco mas ficarão órfãs. Considere arquivar em vez de apagar.")
        }
    }

    private var accentColor: Color {
        institution?.kind.brandColor ?? defaultAccent
    }

    private var defaultAccent: Color {
        switch account.type {
        case .wallet:     return .income
        case .creditCard: return .transfer
        default:          return .brandSecondary
        }
    }

    /// Ícone da conta. Quando tem `Institution`, usa o logo da marca (asset
    /// real se cadastrado, ou SF Symbol tintado pela cor da marca como
    /// fallback). Sem instituição, cai num SF Symbol por tipo de conta.
    @ViewBuilder
    private var accountIcon: some View {
        if account.type != .wallet, let institution {
            InstitutionLogoImage(kind: institution.kind)
                .padding(8)
        } else {
            Image(systemName: fallbackIconName)
                .font(.title2)
                .foregroundStyle(accentColor)
        }
    }

    private var fallbackIconName: String {
        switch account.type {
        case .checking:   return "building.columns"
        case .savings:    return "banknote"
        case .brokerage:  return "chart.line.uptrend.xyaxis"
        case .creditCard: return "creditcard.fill"
        case .wallet:     return "wallet.pass.fill"
        }
    }

    private var balanceColor: Color {
        if account.archived { return .secondary }
        if currentBalance < 0 { return .danger }
        return .primary
    }

    private func iconButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(Color.secondary.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

#Preview("Mac") {
    NavigationStack { AccountsView() }
        .environment(AppEnvironment())
        .frame(width: 900, height: 600)
}
