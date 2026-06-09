import SwiftUI

/// Tela de preview da fatura CSV importada. Diferença principal pro OFX:
/// uma única conta, picker manual (só contas-cartão), e info de quantas
/// linhas com valor negativo foram puladas (pagamentos + estornos).
struct CSVReviewStepView: View {
    @Bindable var store: ImportStore
    let dismiss: DismissAction

    private var resolution: CSVStatementResolution? {
        store.csvResolution
    }

    private var creditCardAccounts: [Account] {
        store.accounts.filter { $0.type == .creditCard && !$0.archived }
    }

    private var totalSelected: Int {
        resolution?.selectedCount ?? 0
    }

    private var canConfirm: Bool {
        guard let resolution else { return false }
        guard totalSelected > 0 else { return false }
        return resolution.accountId != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Card "Conta de destino" + skipped negatives info.
            VStack(alignment: .leading, spacing: 0) {
                CSVAccountInfoCard(
                    store: store,
                    accounts: creditCardAccounts
                )
                if let skipped = resolution?.skippedNegatives, !skipped.isEmpty {
                    skippedBanner(rows: skipped)
                }
            }

            // Bind direto pela projeção do @Bindable. `Binding($optional)`
            // devolve `Binding<T>?` quando o subjacente é não-nil; sem isso
            // o getter capturava o snapshot local do `if let` e mutações em
            // loop liam dados velhos (só a última escrita ficava).
            if let resolutionBinding = Binding($store.csvResolution) {
                CSVTransactionsListCard(
                    resolution: resolutionBinding,
                    institutionKind: bankKind(for: resolutionBinding.wrappedValue.accountId)
                )
            }

            BottomActionBar(caption: selectionCaption) {
                Button("Fechar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Avançar com \(totalSelected) \(totalSelected == 1 ? "transação" : "transações")") {
                    Task { await store.confirmCSVImport() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canConfirm)
            }
        }
        .navigationSubtitle(resolution?.sourceFilename ?? "")
    }

    /// Caption só pra bloqueios — stats vivem no header da lista agora.
    private var selectionCaption: String? {
        guard let resolution else { return nil }
        return resolution.accountId == nil ? "Escolha a conta-cartão de destino" : nil
    }

    private func skippedBanner(rows: [InterCreditCardCSVReader.SkippedRow]) -> some View {
        let count = rows.count
        return Form {
            Section {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(rows) { row in
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.date, format: .dateTime.day().month().year())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .leading)
                                Text(row.description)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                                Text(row.amount, format: .currency(code: "BRL"))
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Label {
                        Text(
                            "\(count) \(count == 1 ? "linha ignorada" : "linhas ignoradas") (valores negativos: pagamentos da fatura anterior + estornos). Pagamentos serão registrados como transferência no extrato bancário."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func bankKind(for accountId: UUID?) -> InstitutionKind? {
        guard let accountId,
              let account = store.accounts.first(where: { $0.id == accountId }),
              let institutionId = account.institutionId,
              let institution = store.institutions.first(where: { $0.id == institutionId })
        else { return nil }
        return institution.kind
    }
}

// MARK: - Account info card

/// Card "Conta de destino" do fluxo CSV. Picker simples — só lista contas
/// do tipo "Cartão de Crédito" existentes. Quando não há nenhuma, o
/// `loadCSV` já bloqueia o import com `ImportError.noCreditCardAccount`.
private struct CSVAccountInfoCard: View {
    @Bindable var store: ImportStore
    let accounts: [Account]

    private var resolution: CSVStatementResolution? {
        store.csvResolution
    }

    var body: some View {
        Form {
            Section {
                Picker("Conta-cartão", selection: Binding(
                    get: { store.csvResolution?.accountId },
                    set: { newValue in
                        Task { await store.setCSVAccount(newValue) }
                    }
                )) {
                    Text("Selecione…").tag(UUID?.none)
                    ForEach(accounts) { account in
                        Text(Account.displayName(
                            for: account,
                            institutions: store.institutions,
                            bankAccounts: store.bankDetails,
                            creditCards: store.creditCards
                        ))
                        .tag(UUID?.some(account.id))
                    }
                }
            } header: {
                HStack {
                    Text("Conta de destino")
                    Spacer()
                    if resolution?.accountId == nil {
                        Text("Escolha")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.warning.opacity(0.18))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                            .textCase(nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Transactions list card

/// Lista de transações do preview CSV — virtualizada via LazyVStack dentro
/// de uma Section. Mesma estrutura usada pelo OFX (`OFXTransactionsListCard`),
/// mas com row própria.
private struct CSVTransactionsListCard: View {
    @Binding var resolution: CSVStatementResolution
    let institutionKind: InstitutionKind?

    private var allSelected: Bool {
        !resolution.rows.isEmpty && resolution.rows.allSatisfy(\.selected)
    }

    var body: some View {
        Form {
            Section {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        TransactionsSelectionRow(
                            summary: selectionSummary,
                            allSelected: allSelected,
                            onToggleAll: { value in
                                for idx in resolution.rows.indices {
                                    resolution.rows[idx].selected = value
                                }
                            }
                        )
                        Divider()
                        ForEach($resolution.rows) { $row in
                            CSVRowView(row: $row, institutionKind: institutionKind)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                            Divider()
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Transações")
            }
        }
        .formStyle(.grouped)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .frame(maxHeight: .infinity)
    }

    private var selectionSummary: String {
        let selected = resolution.selectedCount
        let total = resolution.rows.count
        var parts = ["\(selected) de \(total) selecionadas"]
        if resolution.duplicateCount > 0 {
            parts.append("\(resolution.duplicateCount) \(resolution.duplicateCount == 1 ? "duplicada" : "duplicadas")")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Row

/// Wrapper fino que mapeia `CSVPreviewRow` → `TransactionRow.importPreview`.
/// O `tipo` da fatura ("Parcelamento", "Internacional"...) vai como memo
/// quando difere do default "Compra à vista".
private struct CSVRowView: View {
    @Binding var row: CSVPreviewRow
    let institutionKind: InstitutionKind?

    var body: some View {
        // CSV de fatura: parser já filtra estornos/pagamentos como negativos
        // pra outra esteira (transfer). O que sobra é 100% despesa.
        TransactionRow(
            selection: $row.selected,
            institutionKind: institutionKind,
            description: row.raw.description,
            memo: memo,
            date: row.raw.date,
            amount: row.raw.amount,
            amountKind: .outgoing,
            status: row.isDuplicate ? .duplicate : nil
        )
    }

    private var memo: String? {
        let tipo = row.raw.tipo
        guard !tipo.isEmpty, tipo != "Compra à vista" else { return nil }
        return tipo
    }
}
