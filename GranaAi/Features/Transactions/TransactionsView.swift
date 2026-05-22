import SwiftUI

/// Lista reativa de transações.
struct TransactionsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var store: TransactionStore?
    @State private var showingForm = false
    @State private var showingImport = false
    @State private var editing: Transaction?
    @State private var pendingDelete: Transaction?
    @State private var searchText = ""

    /// Default = data decrescente (mais recente primeiro), o comportamento
    /// padrão do `getAll()` no repo. Usuário pode clicar no header da coluna
    /// pra alternar entre asc/desc ou trocar de coluna.
    @State private var sortOrder: [KeyPathComparator<Transaction>] = [
        KeyPathComparator(\Transaction.occurredAt, order: .reverse)
    ]

    var body: some View {
        Group {
            if let store {
                content(store: store)
                    .environment(store)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if store == nil {
                store = TransactionStore(container: environment.container)
            }
        }
    }

    @ViewBuilder
    private func content(store: TransactionStore) -> some View {
        list(store: store)
            .overlay {
                if store.transactions.isEmpty && !store.isLoading {
                    ContentUnavailableView(
                        "Sem transações",
                        systemImage: AppIcon.transactionsList.systemImage,
                        description: Text("Toque em + pra adicionar a primeira.")
                    )
                }
            }
            .searchable(text: $searchText, prompt: "Buscar")
            .navigationTitle("Transações")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingImport = true
                    } label: {
                        Label("Importar OFX", systemImage: AppIcon.importFile.systemImage)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingForm = true
                    } label: {
                        Label("Adicionar", systemImage: AppIcon.add.systemImage)
                    }
                }
            }
            .sheet(isPresented: $showingForm) {
                TransactionFormView()
                    .environment(store)
            }
            .sheet(item: $editing) { transaction in
                TransactionFormView(existing: transaction)
                    .environment(store)
            }
            .sheet(isPresented: $showingImport) {
                ImportView()
                    .environment(environment)
            }
            .confirmationDialog(
                "Apagar transação?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                presenting: pendingDelete
            ) { transaction in
                Button("Apagar", role: .destructive) {
                    Task {
                        try? await store.delete(id: transaction.id)
                        pendingDelete = nil
                    }
                }
                Button("Cancelar", role: .cancel) { pendingDelete = nil }
            } message: { transaction in
                Text("\(transaction.description) — \(transaction.amount.formatted(.currency(code: "BRL")))")
            }
            .task {
                await store.start()
            }
    }

    @ViewBuilder
    private func list(store: TransactionStore) -> some View {
        // Table nativa do macOS: virtualizada (escala bem com milhares de
        // linhas), colunas redimensionáveis pelo usuário, e segue o padrão
        // visual do `ImportHistoryView`.
        //
        // **Ordenação:** colunas com `value:` ficam clicáveis (chevron sobe/desce
        // aparece no header). SwiftUI atualiza o `sortOrder` binding mas não
        // sorta os dados sozinho — fazemos `.sorted(using:)` na chamada.
        // Categoria/Conta não ganham `value:` porque o que queremos ordenar
        // ali é o *nome* (`store.category(for:)?.name`), que não é uma
        // propriedade direta de `Transaction` — adicionar exige um
        // comparator custom. Fica fora do MVP.
        Table(filtered(store: store).sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Data", value: \.occurredAt) { transaction in
                Text(transaction.occurredAt.formatted(date: .numeric, time: .omitted))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 100, max: 110)

            TableColumn("Descrição", value: \.description) { transaction in
                Text(transaction.description)
                    .lineLimit(1)
            }

            TableColumn("Categoria") { transaction in
                CategoryBadge(
                    category: store.category(for: transaction.categoryId),
                    icon: store.icon(for: transaction.categoryId)
                )
            }
            .width(min: 160, ideal: 200)

            TableColumn("Conta") { transaction in
                Text(store.account(for: transaction.accountId)?.name ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150)

            TableColumn("Valor", value: \.amount) { transaction in
                Text(transaction.amount.formatted(.currency(code: "BRL")))
                    .monospacedDigit()
                    .foregroundStyle(amountColor(for: transaction, store: store))
            }
            .width(min: 110, ideal: 130, max: 160)

            TableColumn("") { transaction in
                HStack(spacing: 8) {
                    Button {
                        editing = transaction
                    } label: {
                        Image(systemName: AppIcon.edit.systemImage)
                    }
                    .buttonStyle(.borderless)
                    .help("Editar")

                    Button(role: .destructive) {
                        pendingDelete = transaction
                    } label: {
                        Image(systemName: AppIcon.delete.systemImage)
                    }
                    .buttonStyle(.borderless)
                    .help("Apagar")
                }
            }
            .width(60)
        }
    }

    private func amountColor(for transaction: Transaction, store: TransactionStore) -> Color {
        switch store.category(for: transaction.categoryId)?.kind {
        case .income:   return .income
        case .transfer: return .transfer
        case .expense:  return transaction.amount < 0 ? .expense : .primary
        case .none:     return .primary
        }
    }

    private func filtered(store: TransactionStore) -> [Transaction] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.transactions }
        let needle = trimmed.lowercased()
        return store.transactions.filter { t in
            // Busca client-side em descrição + nome da categoria. Otimizar
            // pra full-text search quando passar dos ~5k registros locais.
            if t.description.lowercased().contains(needle) { return true }
            if let cat = store.category(for: t.categoryId),
               cat.name.lowercased().contains(needle) { return true }
            return false
        }
    }
}

#Preview {
    NavigationStack {
        TransactionsView()
            .environment(AppEnvironment())
    }
}
