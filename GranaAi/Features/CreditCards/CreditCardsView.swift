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
    @State private var showDeleteConfirm = false

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
        .navigationTitle("Cartões de crédito")
        .navigationSubtitle(subtitle)
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
        .confirmationDialog(
            "Apagar cartão?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Apagar", role: .destructive) {
                guard let id = selectedCardId else { return }
                Task { try? await store.delete(id: id) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(
                "Transações vinculadas continuarão no banco mas ficarão órfãs. Considere arquivar em vez de apagar."
            )
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
                selectedId: $selectedCardId
            )
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)

            if let selectedId = selectedCardId,
               let account = cards.first(where: { $0.id == selectedId })
            {
                CreditCardDetailView(account: account, store: store)
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

    @ToolbarContentBuilder
    private func toolbarContent(store: AccountStore) -> some ToolbarContent {
        let cards = visible(store: store)
        let selected = cards.first(where: { $0.id == selectedCardId })

        // `ToolbarSpacer(.fixed, ...)` é o que quebra a pílula única que o
        // SwiftUI faz pra items adjacentes no mesmo placement — sem isso
        // editar/arquivar/apagar + "+" + mais ficam todos colados num
        // único grupo visual. Padrão Liquid Glass do macOS 26+.
        if let selected {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    formMode = .edit(selected)
                } label: {
                    Label("Editar", systemImage: AppIcon.edit.systemImage)
                }
                .help("Editar cartão")

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
                .help(selected.archived ? "Desarquivar cartão" : "Arquivar cartão")

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Apagar", systemImage: AppIcon.delete.systemImage)
                }
                .help("Apagar cartão")
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                formMode = .create
            } label: {
                Label("Novo cartão", systemImage: AppIcon.add.systemImage)
            }
            .help("Novo cartão")
        }

        if hasArchivedCard {
            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle("Mostrar arquivados", isOn: $showArchived)
                } label: {
                    Label("Mais", systemImage: AppIcon.more.systemImage)
                }
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
        EmptyStateView(
            "Sem cartões por aqui",
            icon: .sidebarCreditCards,
            description: "Cadastre os cartões de crédito que você usa pra acompanhar as faturas — dia de fechamento, vencimento e limite (opcional)."
        ) {
            Button {
                formMode = .create
            } label: {
                Label("Cadastrar primeiro cartão", systemImage: AppIcon.add.systemImage)
            }
            .buttonStyle(.borderedProminent)
            .disabled(formMode != nil)
        }
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
