import SwiftUI

struct TransactionsView: View {
    private static let ptBR = Locale(identifier: "pt_BR")

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
        KeyPathComparator(\Transaction.occurredAt, order: .reverse),
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

    private func content(store: TransactionStore) -> some View {
        list(store: store)
            .overlay {
                if store.transactions.isEmpty && !store.isLoading {
                    EmptyStateView(
                        "Sem transações ainda",
                        icon: .sidebarTransactions,
                        description: "Adicione uma manualmente ou importe um extrato."
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
                    .help("Importar extrato OFX")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingForm = true
                    } label: {
                        Label("Adicionar", systemImage: AppIcon.add.systemImage)
                    }
                    .help("Nova transação")
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

    private func list(store: TransactionStore) -> some View {
        // Table nativa do macOS: virtualizada (escala bem com milhares de
        // linhas), colunas redimensionáveis pelo usuário, e segue o padrão
        // visual do `ImportHistoryView`.
        //
        // **Ordenação:** colunas com `value:` ficam clicáveis (chevron sobe/desce
        // aparece no header). SwiftUI atualiza o `sortOrder` binding mas não
        // sorta os dados sozinho — fazemos `.sorted(using:)` na chamada.
        // Categoria/Subcategoria não ganham `value:` porque o que queremos
        // ordenar ali é o *nome* (`store.category(for:)?.name`), que não é
        // uma propriedade direta de `Transaction` — adicionar exige um
        // comparator custom. Fica fora do MVP.
        Table(filtered(store: store).sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Banco") { transaction in
                let accountName =
                    store.account(for: transaction.accountId)
                        .map { store.displayName(for: $0) } ?? ""
                // HStack + Spacer + contentShape expandem a área de hover pra
                // célula inteira. Sem isso, `.help(...)` no ícone 24pt só
                // aparece se o cursor pousar exatamente no quadrado pequeno.
                HStack(spacing: 0) {
                    InstitutionIcon(kind: institutionKind(for: transaction, store: store), size: 24)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .help(accountName)
            }
            .width(60)

            TableColumn("Descrição", value: \.description) { transaction in
                Text(transaction.description)
                    .lineLimit(1)
            }
            .width(min: 220, ideal: 320)

            TableColumn("Categoria") { transaction in
                let categoryName = store.category(for: transaction.categoryId)?.name ?? ""
                let subName = subcategoryName(for: transaction, store: store)
                // Tooltip mostra "Categoria · Subcategoria" quando há ambas,
                // só categoria quando não há sub. Sem subcategoria a célula
                // fica só com o ícone — o nome da categoria mora no tooltip.
                let tooltip = subName.map { "\(categoryName) · \($0)" } ?? categoryName
                HStack(spacing: 8) {
                    CategoryBadge(
                        category: store.category(for: transaction.categoryId),
                        icon: store.icon(for: transaction.categoryId),
                        iconOnly: true
                    )
                    if let subName {
                        Text(subName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .help(tooltip)
            }
            .width(min: 130, ideal: 160)

            TableColumn("Data", value: \.occurredAt) { transaction in
                Text(transaction.occurredAt.formatted(date: .numeric, time: .omitted))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(100)

            TableColumn("Valor", value: \.amount) { transaction in
                accountingAmount(transaction.amount)
                    .foregroundStyle(amountColor(for: transaction, store: store))
            }
            .width(min: 110, ideal: 130, max: 160)

            // Placeholder pra campo futuro de status (ex: pendente / efetivada
            // / conciliada). Ainda não existe no modelo — coluna fica vazia
            // até o status entrar no schema.
            TableColumn("Status") { _ in
                Text("")
            }
            .width(70)

            TableColumn("") { transaction in
                // `.foregroundStyle(.secondary)` pra acompanhar o tom dos ícones da
                // toolbar (Importar/Adicionar). Sem isso, `Button` plain renderiza
                // o ícone na cor primária e fica destoante.
                HStack(spacing: 12) {
                    Button {
                        editing = transaction
                    } label: {
                        Image(systemName: AppIcon.edit.systemImage)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Editar")

                    Button(role: .destructive) {
                        pendingDelete = transaction
                    } label: {
                        Image(systemName: AppIcon.delete.systemImage)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Apagar")
                }
            }
            .width(70)
        }
    }

    private func institutionKind(for transaction: Transaction, store: TransactionStore)
        -> InstitutionKind
    {
        guard let account = store.account(for: transaction.accountId),
              let institutionId = account.institutionId,
              let institution = store.institution(for: institutionId)
        else {
            return .other
        }
        return institution.kind
    }

    private func subcategoryName(for transaction: Transaction, store: TransactionStore) -> String? {
        guard let subcategoryId = transaction.subcategoryId else { return nil }
        return store.category(for: subcategoryId)?.name
    }

    /// Renderiza o valor no estilo "contábil": símbolo da moeda colado à
    /// esquerda da célula, número colado à direita, espaço flexível no meio.
    /// É o layout que o Excel chama de "Accounting" — facilita escanear
    /// colunas verticais de valores.
    private func accountingAmount(_ amount: Decimal) -> some View {
        let number = amount.formatted(
            .number
                .precision(.fractionLength(2))
                .locale(Self.ptBR)
        )
        return HStack(spacing: 4) {
            // Símbolo da moeda fica em `.secondary` (mesmo tom da data) pra
            // não competir com o número, que recebe a cor do `CategoryKind`
            // via `.foregroundStyle(amountColor(...))` aplicado por fora.
            Text("R$")
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(number)
        }
        .monospacedDigit()
    }

    private func amountColor(for transaction: Transaction, store: TransactionStore) -> Color {
        switch store.category(for: transaction.categoryId)?.kind {
        case .income: return .income
        case .transfer: return .transfer
        case .expense: return transaction.amount < 0 ? .expense : .primary
        case .none: return .primary
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
               cat.name.lowercased().contains(needle)
            {
                return true
            }
            return false
        }
    }
}
