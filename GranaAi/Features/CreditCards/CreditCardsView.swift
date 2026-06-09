import Foundation
import SwiftUI

/// Tela de Cartões de crédito. Layout mestre-detalhe inspirado no Notas do
/// macOS e na visão web do Inter: sidebar à esquerda com a lista de cartões
/// + totais, detalhe à direita com header do cartão, gauge de limite,
/// timeline de faturas, trio de cards de ciclo (anterior / atual / próxima)
/// e lançamentos da fatura selecionada.
///
/// A `CreditCardsView` é só o orquestrador: mantém `selectedCardId` e
/// delega o lado esquerdo pra `CreditCardsSidebar` e o lado direito pra
/// `CreditCardDetailView`. Estado de seleção é local (`@State`) — não se
/// preserva entre lançamentos do app, mas re-seleciona o primeiro cartão
/// não-arquivado automaticamente quando o stream emite.
struct CreditCardsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var store: AccountStore?
    @State private var selectedCardId: UUID?
    @State private var formMode: FormMode?
    @State private var showArchived = false

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
            } else {
                ProgressView()
                    .task { store = AccountStore(container: environment.container) }
            }
        }
        .navigationTitle("Cartões de crédito")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    formMode = .create
                } label: {
                    Label("Novo cartão", systemImage: AppIcon.add.systemImage)
                }
                .disabled(formMode != nil)
                .help("Adicionar novo cartão")
            }
            if hasArchivedCard {
                ToolbarItem(placement: .secondaryAction) {
                    Toggle("Mostrar arquivados", isOn: $showArchived)
                }
            }
        }
    }

    @ViewBuilder
    private func content(store: AccountStore) -> some View {
        let visibleCards = visible(store: store)
        Group {
            if visibleCards.isEmpty {
                emptyState
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                splitContent(store: store, cards: visibleCards)
            }
        }
        .sheet(item: $formMode) { mode in
            AccountFormView(
                existing: editingAccount(from: mode),
                lockedType: .creditCard,
                onCancel: { formMode = nil },
                onSaved: { formMode = nil }
            )
            .environment(store)
        }
        .onChange(of: visibleCards.map(\.id)) { _, ids in
            reconcileSelection(visibleIds: ids)
        }
        .onAppear {
            reconcileSelection(visibleIds: visibleCards.map(\.id))
        }
    }

    private func splitContent(store: AccountStore, cards: [Account]) -> some View {
        // `HSplitView` em vez de aninhar outro `NavigationSplitView`: o
        // pai (`ContentView`) já é split — aninhar deixa o macOS confuso
        // quanto a qual sidebar dobra. `HSplitView` é o controle nativo
        // pra split intra-feature, com divisor arrastável herdado do AppKit.
        HSplitView {
            CreditCardsSidebar(
                store: store,
                cards: cards,
                selectedId: $selectedCardId,
                onCreate: { formMode = .create }
            )
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)

            if let selectedId = selectedCardId,
               let account = cards.first(where: { $0.id == selectedId }) {
                CreditCardDetailView(
                    account: account,
                    store: store,
                    onEdit: { formMode = .edit(account) },
                    onToggleArchive: {
                        Task { try? await store.setArchived(account, archived: !account.archived) }
                    },
                    onDelete: {
                        Task { try? await store.delete(id: account.id) }
                    }
                )
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Fallback enquanto a seleção ainda não foi reconciliada
                // (primeira renderização ou cartão único acabou de ser
                // removido). Mostra placeholder em vez de detalhe quebrado.
                placeholderDetail
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var placeholderDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "creditcard")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Selecione um cartão")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var subtitle: String {
        guard let store else { return "" }
        let count = visible(store: store).count
        if count == 0 { return "Nenhum cartão cadastrado" }
        if count == 1 { return "1 cartão cadastrado" }
        return "\(count) cartões cadastrados"
    }

    private var hasArchivedCard: Bool {
        store?.accounts.contains { $0.type == .creditCard && $0.archived } ?? false
    }

    /// Reconcilia a seleção quando a lista de cartões visíveis muda: se a
    /// seleção atual sumiu (foi arquivada / deletada / o toggle de
    /// arquivados desligou), seleciona o primeiro disponível. Se nada
    /// está selecionado e há cartões, seleciona o primeiro.
    private func reconcileSelection(visibleIds: [UUID]) {
        if let current = selectedCardId, visibleIds.contains(current) { return }
        selectedCardId = visibleIds.first
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Nenhum cartão cadastrado")
                .font(.title3.weight(.semibold))
            Text(
                """
                Cadastre os cartões de crédito que você usa para detalhar \
                as compras de cada fatura (dia de fechamento, dia de \
                vencimento, limite opcional).
                """
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)
            Button {
                formMode = .create
            } label: {
                Label("Cadastrar primeiro cartão", systemImage: AppIcon.add.systemImage)
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
        store.accounts.filter { account in
            guard account.type == .creditCard else { return false }
            return showArchived ? true : !account.archived
        }
    }

    private func editingAccount(from mode: FormMode) -> Account? {
        if case let .edit(account) = mode { return account }
        return nil
    }
}
