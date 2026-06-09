import Foundation
import SwiftUI

/// Formulário de criação/edição de transação.
///
/// **Modo "novo" vs "edição":** o init aceita `Transaction?` — `nil` significa
/// novo registro. O título do sheet e o botão "Salvar" adaptam o
/// comportamento sem precisar de duas Views diferentes.
///
/// **Pagamento de fatura (Fase 4.7):** quando a categoria é transferência e
/// o destino é uma conta-cartão, aparece uma section com picker de Fatura
/// (sugere a Fatura cujo saldo restante mais se aproxima do valor da
/// transferência). DisclosureGroup "Aplicar em mais de uma fatura" expõe o
/// modo split, distribuindo o valor entre N Faturas.
struct TransactionFormView: View {
    @Environment(TransactionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let existing: Transaction?

    @State private var description: String = ""
    /// Estilo "calculadora": guardamos o valor em **centavos** (Int) e
    /// formatamos pra BRL na exibição. Isso garante que o usuário digite só
    /// números e o "R$ X,YY" apareça automaticamente, sem precisar pensar em
    /// vírgula ou separador de milhar.
    @State private var amountCents: Int = 0
    @State private var occurredAt: Date = .init()
    @State private var accountId: UUID?
    @State private var categoryId: UUID?
    @State private var subcategoryId: UUID?
    /// Fase 4.5: contraparte quando a categoria selecionada é `transfer`.
    /// Aparece como picker logo abaixo do "Conta" — só renderizado quando
    /// `selectedCategoryKind == .transfer`. Ao trocar a categoria pra qualquer
    /// outro kind, o valor é limpo (`onChange` em `categoryId`).
    @State private var destinationAccountId: UUID?
    @State private var notes: String = ""
    @State private var saveError: String?

    // MARK: - Statement payment (Fase 4.7)

    /// Fatura selecionada no modo simples (1 transferência → 1 Fatura).
    /// `nil` quando não há cartão de destino ou usuário ainda não escolheu.
    @State private var selectedStatementId: UUID?
    /// Toggle do DisclosureGroup. Quando true, `splitAmountsCents` vira a
    /// fonte da verdade; `selectedStatementId` é ignorado.
    @State private var splitMode: Bool = false
    /// Valores aplicados por Statement no modo split (em centavos).
    /// Statements ausentes do dict = 0 aplicado. Entries com valor 0 são
    /// filtradas no save.
    @State private var splitAmountsCents: [UUID: Int] = [:]

    init(existing: Transaction? = nil) {
        self.existing = existing
    }

    var body: some View {
        NavigationStack {
            Form {
                // `prompt:` é o placeholder DENTRO do campo. O primeiro
                // argumento ("Descrição") é o LABEL que aparece à esquerda
                // do campo no Form do macOS.
                TextField(
                    "Descrição",
                    text: $description,
                    prompt: Text("Ex: Almoço no restaurante")
                )

                LabeledContent("Valor") {
                    CurrencyField(cents: $amountCents)
                }
                .onChange(of: amountCents) { _, _ in
                    autoSelectClosestStatementIfNeeded()
                }

                // Sem opção "Selecione" — o usuário escolhe da lista direto.
                // `accountId` é defaultado pra primeira conta em `loadExisting`.
                Picker("Conta", selection: $accountId) {
                    ForEach(store.accounts) { account in
                        Text(store.displayName(for: account)).tag(UUID?.some(account.id))
                    }
                }
                .onChange(of: accountId) { _, newValue in
                    // Origem mudou pra mesma conta que o destino → zera o
                    // destino. Sem isso o save passaria com origem == destino
                    // (transferência pra si mesma, neutra no saldo mas suja
                    // na lista).
                    if destinationAccountId == newValue {
                        destinationAccountId = nil
                    }
                }

                Picker("Categoria", selection: $categoryId) {
                    ForEach(store.rootCategories) { category in
                        Text(category.name).tag(UUID?.some(category.id))
                    }
                }
                .onChange(of: categoryId) { oldValue, _ in
                    // Só zerar quando o usuário troca a categoria de fato.
                    // Em `loadExisting` (modo edição), `oldValue` é nil porque
                    // categoryId começa nulo — se zerássemos aqui também,
                    // sobrescreveríamos a subcategoria que está sendo carregada.
                    if oldValue != nil {
                        subcategoryId = nil
                        // Sair de uma categoria "transfer" → joga fora o destino
                        // (só faz sentido pra transferências). `loadExisting`
                        // preserva o destino porque `oldValue == nil` nesse caso.
                        if selectedCategoryKind != .transfer {
                            destinationAccountId = nil
                            resetStatementPayment()
                        }
                    }
                }

                if let categoryId,
                   !store.subcategories(of: categoryId).isEmpty
                {
                    Picker("Subcategoria", selection: $subcategoryId) {
                        Text("(nenhuma)").tag(UUID?.none)
                        ForEach(store.subcategories(of: categoryId)) { sub in
                            Text(sub.name).tag(UUID?.some(sub.id))
                        }
                    }
                }

                // Fase 4.5: contraparte da transferência. Só aparece se a
                // categoria selecionada for `transfer` — pra qualquer outra,
                // destination_account_id fica NULL e o saldo se comporta como
                // sempre (sinal vem do kind income/expense).
                if selectedCategoryKind == .transfer {
                    Picker("Conta de destino", selection: $destinationAccountId) {
                        Text("(nenhuma)").tag(UUID?.none)
                        ForEach(destinationAccountOptions) { account in
                            Text(store.displayName(for: account)).tag(UUID?.some(account.id))
                        }
                    }
                    .onChange(of: destinationAccountId) { _, _ in
                        resetStatementPayment()
                        autoSelectClosestStatementIfNeeded()
                    }
                }

                if shouldShowStatementPicker {
                    statementPaymentSection
                }

                // Dois DatePickers separados pro mesmo Date — cada um só edita
                // seus componentes (data não mexe na hora e vice-versa). No
                // macOS o estilo default é `.stepperField`: segmentos numéricos
                // com setas, exatamente o "preenche com números" que queremos.
                DatePicker("Data", selection: $occurredAt, displayedComponents: [.date])
                DatePicker("Hora", selection: $occurredAt, displayedComponents: [.hourAndMinute])

                // `TextEditor` em vez de `TextField` porque precisa aceitar
                // Enter como quebra de linha real. `TextField(axis: .vertical)`
                // existe, mas no macOS o Enter ainda é interpretado como
                // submit em alguns contextos. `TextEditor` é o controle nativo
                // pra texto livre multilinha. Placeholder via overlay porque
                // `TextEditor` não tem prompt nativo.
                LabeledContent("Notas") {
                    ZStack(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("Opcional")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $notes)
                            .frame(minHeight: 80, maxHeight: 160)
                            .scrollContentBackground(.hidden)
                    }
                }

                if let saveError {
                    Text(saveError)
                        .foregroundStyle(.danger)
                        .font(.callout)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existing == nil ? "Nova transação" : "Editar transação")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadExisting)
            // `loadExisting` define os defaults no `onAppear`, mas
            // `store.accounts`/`store.categories` são populados por streams
            // (`TransactionStore.start()`) que podem ainda não ter emitido
            // quando o sheet aparece — em "novo" o `canSave` ficaria preso
            // em `false` mesmo com descrição e valor preenchidos. Os onChange
            // abaixo aplicam o default assim que os dados chegam.
            .onChange(of: store.accounts) { _, newAccounts in
                if existing == nil, accountId == nil, let first = newAccounts.first {
                    accountId = first.id
                }
            }
            .onChange(of: store.categories) { _, _ in
                if existing == nil, categoryId == nil, let first = store.rootCategories.first {
                    categoryId = first.id
                }
            }
        }
    }

    // MARK: - Statement payment UI (Fase 4.7)

    private var shouldShowStatementPicker: Bool {
        isPayingCreditCard && !openStatementsForDestination.isEmpty
    }

    private var statementPaymentSection: some View {
        Section {
            if !splitMode {
                Picker("Aplicar à fatura", selection: $selectedStatementId) {
                    Text("(nenhuma)").tag(UUID?.none)
                    ForEach(openStatementsForDestination) { statement in
                        Text(statementPickerLabel(statement))
                            .tag(UUID?.some(statement.id))
                    }
                }
            }

            DisclosureGroup(isExpanded: $splitMode) {
                ForEach(openStatementsForDestination) { statement in
                    LabeledContent(statementPickerLabel(statement)) {
                        CurrencyField(cents: Binding(
                            get: { splitAmountsCents[statement.id] ?? 0 },
                            set: { splitAmountsCents[statement.id] = $0 }
                        ))
                    }
                }
                splitSummary
            } label: {
                Text("Aplicar em mais de uma fatura")
                    .font(.callout)
            }
            .onChange(of: splitMode) { _, expanded in
                // Ao abrir o split, popula com a seleção atual no valor
                // cheio — usuário começa de algum lugar coerente em vez de
                // todos zerados.
                if expanded, splitAmountsCents.isEmpty,
                   let id = selectedStatementId
                {
                    splitAmountsCents[id] = amountCents
                }
                // Ao fechar, descarta os valores de split (volta pro modo
                // simples com `selectedStatementId` que estava).
                if !expanded {
                    splitAmountsCents = [:]
                }
            }
        } header: {
            Text("Pagamento da fatura")
        } footer: {
            footerText
        }
    }

    private var splitSummary: some View {
        let totalCents = splitAmountsCents.values.reduce(0, +)
        let transferCents = amountCents
        let totalDecimal = Decimal(totalCents) / 100
        let transferDecimal = Decimal(transferCents) / 100
        let isExact = totalCents == transferCents
        let isOver = totalCents > transferCents
        return HStack {
            Text("Total aplicado")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(
                "\(totalDecimal.formatted(.currency(code: "BRL"))) de \(transferDecimal.formatted(.currency(code: "BRL")))"
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(isOver ? .danger : (isExact ? .success : .secondary))
        }
    }

    /// "Fatura 05/2026 · Faltam R$ X,XX de R$ Y,YY". Mostra `closing_date`
    /// formatado (mês/ano da fatura) + saldo restante pra o usuário escolher
    /// a Fatura certa de bate-pronto.
    private func statementPickerLabel(_ statement: Statement) -> String {
        let monthYear = statement.closingDate.formatted(.dateTime.month().year())
        let remaining = store.remainingAmount(of: statement)
        let total = statement.totalAmount
        let remainingStr = remaining.formatted(.currency(code: "BRL"))
        let totalStr = total.formatted(.currency(code: "BRL"))
        return "Fatura \(monthYear) · Faltam \(remainingStr) de \(totalStr)"
    }

    private var footerText: Text {
        if splitMode {
            return Text(
                "Distribua o valor da transferência entre as Faturas. A soma não precisa cobrir o total, mas não pode passar."
            )
        }
        return Text(
            "A transferência vai aplicar o valor cheio à Fatura selecionada. Ative o modo split pra dividir entre várias."
        )
    }

    // MARK: - Save

    private var canSave: Bool {
        guard !description.trimmingCharacters(in: .whitespaces).isEmpty,
              amountCents > 0,
              accountId != nil,
              categoryId != nil
        else { return false }
        // Transferência exige destino diferente da origem. `destinationAccountId`
        // nulo é aceito (transferência neutra, compat com legados); o que
        // bloqueia é destino == origem.
        if selectedCategoryKind == .transfer,
           let dest = destinationAccountId,
           dest == accountId
        {
            return false
        }
        // Em split mode, soma não pode exceder o valor da transferência —
        // pagar mais que se transferiu é incoerente.
        if splitMode, shouldShowStatementPicker {
            let totalSplit = splitAmountsCents.values.reduce(0, +)
            if totalSplit > amountCents { return false }
        }
        return true
    }

    /// `kind` da categoria atualmente selecionada — usado pra decidir se mostra
    /// o picker de destino, decidir se persiste `destinationAccountId`, etc.
    /// `nil` se a categoria ainda não foi carregada (race entre `onAppear` e
    /// o stream de categorias) ou nenhuma foi escolhida.
    private var selectedCategoryKind: CategoryKind? {
        guard let categoryId else { return nil }
        return store.categories.first { $0.id == categoryId }?.kind
    }

    /// Opções pro picker de destino: todas as contas menos a de origem
    /// (transferir pra si mesmo não faz sentido). Inclui arquivadas só se
    /// já era a contraparte de uma transferência existente — assim a edição
    /// não "perde" a conta arquivada do dropdown.
    private var destinationAccountOptions: [Account] {
        store.accounts.filter { account in
            guard account.id != accountId else { return false }
            if account.archived {
                return existing?.destinationAccountId == account.id
            }
            return true
        }
    }

    private var isPayingCreditCard: Bool {
        guard selectedCategoryKind == .transfer,
              let dest = destinationAccountId,
              let account = store.account(for: dest)
        else { return false }
        return account.type == .creditCard
    }

    private var openStatementsForDestination: [Statement] {
        guard let dest = destinationAccountId else { return [] }
        return store.openStatements(for: dest)
    }

    /// Limpa estado de pagamento de fatura (split e single). Chamado quando
    /// destination muda ou categoria deixa de ser transfer — evita carregar
    /// estado stale entre alternâncias.
    private func resetStatementPayment() {
        selectedStatementId = nil
        splitMode = false
        splitAmountsCents = [:]
    }

    /// Auto-sugere a Fatura cujo saldo restante mais se aproxima do valor da
    /// transferência. Roda quando o destino muda, quando o valor da
    /// transferência muda, ou quando o stream de statements chega no momento
    /// certo. Só age em modo simples (split é controlado manualmente) e só
    /// quando ainda não há seleção (não sobrescreve escolha do usuário).
    private func autoSelectClosestStatementIfNeeded() {
        guard !splitMode, isPayingCreditCard, selectedStatementId == nil else { return }
        let target = Decimal(amountCents) / 100
        let closest = openStatementsForDestination.min(by: { lhs, rhs in
            let lhsDiff = (store.remainingAmount(of: lhs) - target).magnitude
            let rhsDiff = (store.remainingAmount(of: rhs) - target).magnitude
            return lhsDiff < rhsDiff
        })
        selectedStatementId = closest?.id
    }

    private func loadExisting() {
        guard let existing else {
            // Defaults em "novo": primeira conta + primeira categoria raiz.
            // Pickers exigem uma seleção válida (sem opção "Selecione").
            if accountId == nil { accountId = store.accounts.first?.id }
            if categoryId == nil { categoryId = store.rootCategories.first?.id }
            return
        }
        description = existing.description
        amountCents = Int(truncatingIfNeeded: Converters.decimalToCents(existing.amount))
        occurredAt = existing.occurredAt
        accountId = existing.accountId
        categoryId = existing.categoryId
        subcategoryId = existing.subcategoryId
        destinationAccountId = existing.destinationAccountId
        notes = existing.notes ?? ""

        // Carregar payments existentes pra preservar a alocação na edição.
        // `store.statementPayments` é streamado — em race, fica vazio e o
        // form começa "limpo"; usuário re-escolhe no save.
        let existingPayments = store.statementPayments.filter { $0.transactionId == existing.id }
        switch existingPayments.count {
        case 0:
            break // nada a fazer
        case 1:
            selectedStatementId = existingPayments[0].statementId
        default:
            splitMode = true
            splitAmountsCents = Dictionary(
                uniqueKeysWithValues: existingPayments.map { payment in
                    (payment.statementId, Int(truncatingIfNeeded: Converters.decimalToCents(payment.appliedAmount)))
                }
            )
        }
    }

    private func save() async {
        guard let accountId, let categoryId else { return }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesValue = trimmedNotes.isEmpty ? nil : trimmedNotes
        let amount = Decimal(amountCents) / 100

        // Só persiste destino quando a categoria é transferência. Trocar a
        // categoria pra outro kind sem reabrir o form não devia acontecer
        // (zeramos no onChange), mas o guard aqui é cinto + suspensório.
        let resolvedDestination: UUID? = (selectedCategoryKind == .transfer)
            ? destinationAccountId
            : nil

        // Build allocations pro hook de StatementPayment. Vazio quando não é
        // pagamento de fatura — replacePayments aceita array vazio e apaga
        // payments antigos (necessário se usuário re-categorizou).
        let allocations: [UUID: Decimal] = buildAllocationsForSave()

        do {
            if let existing {
                var updated = existing
                updated.accountId = accountId
                updated.categoryId = categoryId
                updated.subcategoryId = subcategoryId
                updated.amount = amount
                updated.occurredAt = occurredAt
                updated.description = description
                updated.notes = notesValue
                updated.destinationAccountId = resolvedDestination
                try await store.update(updated, statementAllocations: allocations)
            } else {
                try await store.add(
                    accountId: accountId,
                    categoryId: categoryId,
                    subcategoryId: subcategoryId,
                    amount: amount,
                    occurredAt: occurredAt,
                    description: description,
                    notes: notesValue,
                    destinationAccountId: resolvedDestination,
                    statementAllocations: allocations
                )
            }
            dismiss()
        } catch {
            saveError = error.localizedDescription
            NoticeCenter.shared.report(error, title: "Falha ao salvar transação")
        }
    }

    private func buildAllocationsForSave() -> [UUID: Decimal] {
        guard isPayingCreditCard else { return [:] }
        if splitMode {
            // Filtra zerados pra não criar StatementPayment com applied = 0.
            return splitAmountsCents
                .filter { $0.value > 0 }
                .reduce(into: [UUID: Decimal]()) { dict, entry in
                    dict[entry.key] = Decimal(entry.value) / 100
                }
        }
        if let id = selectedStatementId {
            return [id: Decimal(amountCents) / 100]
        }
        return [:]
    }
}
