import Foundation
import SwiftUI

/// Lista de contas + botão "Nova conta". Reativa via `AccountStore.start()`.
struct AccountsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var store: AccountStore?
    @State private var formMode: FormMode?
    @State private var showArchived = false

    enum FormMode: Identifiable {
        case create
        case edit(Account)

        var id: String {
            switch self {
            case .create:           return "create"
            case .edit(let acc):    return "edit-\(acc.id.uuidString)"
            }
        }
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    formMode = .create
                } label: {
                    Label("Nova conta", systemImage: AppIcon.add.systemImage)
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Toggle("Mostrar arquivadas", isOn: $showArchived)
            }
        }
        .sheet(item: $formMode) { mode in
            if let store {
                switch mode {
                case .create:
                    AccountFormView()
                        .environment(store)
                case .edit(let account):
                    AccountFormView(existing: account)
                        .environment(store)
                }
            }
        }
    }

    @ViewBuilder
    private func content(store: AccountStore) -> some View {
        if store.accounts.isEmpty {
            ContentUnavailableView(
                "Nenhuma conta",
                systemImage: AppIcon.walletEmpty.systemImage,
                description: Text("Crie uma conta para começar a registrar transações.")
            )
        } else {
            List {
                ForEach(visible(store: store)) { account in
                    AccountRow(account: account, store: store)
                        .contentShape(Rectangle())
                        .onTapGesture { formMode = .edit(account) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { try? await store.delete(id: account.id) }
                            } label: {
                                Label("Apagar", systemImage: AppIcon.delete.systemImage)
                            }
                            Button {
                                Task { try? await store.setArchived(account, archived: !account.archived) }
                            } label: {
                                Label(account.archived ? "Desarquivar" : "Arquivar",
                                      systemImage: account.archived ? AppIcon.unarchive.systemImage : AppIcon.archive.systemImage)
                            }
                            .tint(.warning)
                        }
                }
            }
        }
    }

    private func visible(store: AccountStore) -> [Account] {
        store.accounts.filter { showArchived ? true : !$0.archived }
    }
}

private struct AccountRow: View {
    let account: Account
    let store: AccountStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: institutionIcon)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(account.archived ? Color.secondary : .primary)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(account.name)
                        .font(.body.weight(.medium))
                    if account.archived {
                        Text("(arquivada)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(account.initialBalance.formatted(.currency(code: account.currency)))
                .font(.callout.monospacedDigit())
                .foregroundStyle(account.archived ? Color.secondary : .primary)
        }
        .padding(.vertical, 4)
        .opacity(account.archived ? 0.55 : 1)
    }

    private var institutionIcon: String {
        if let inst = store.institution(forAccount: account) {
            return inst.kind.systemImage
        }
        // Sem instituição → ícone por tipo de conta (carteira física, etc.).
        switch account.type {
        case .wallet:    return "wallet.pass.fill"
        case .checking:  return "building.columns"
        case .savings:   return "banknote"
        case .brokerage: return "chart.line.uptrend.xyaxis"
        }
    }

    private var subtitle: String {
        var parts: [String] = [account.type.displayName]
        if let inst = store.institution(forAccount: account) {
            parts.append(inst.name)
        }
        if let branch = account.branchId, !branch.isEmpty {
            parts.append("Ag. \(branch)")
        }
        if let number = account.accountNumber, !number.isEmpty {
            parts.append("Conta \(number)")
        }
        return parts.joined(separator: " · ")
    }
}

#Preview("Mac") {
    NavigationStack { AccountsView() }
        .environment(AppEnvironment())
        .frame(width: 700, height: 500)
}
