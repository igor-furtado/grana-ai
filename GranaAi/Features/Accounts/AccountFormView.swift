import Foundation
import SwiftUI

/// Form de criação/edição de conta. Apresentado como **sheet modal** pela
/// `AccountsView` (`.sheet(item:)`). Padrão idiomático no macOS pra
/// create/edit (Mail, Reminders, Notes) — dá foco total e mantém o tamanho
/// dos campos consistente.
///
/// **Seções condicionais por tipo.** O picker de tipo dispara a aparição da
/// seção apropriada (banco vs cartão). Submit escreve `accounts` + tabela-irmã
/// (`bank_accounts` ou `credit_cards`) numa única `writeTransaction`.
///
/// **Sem campo "Nome".** O nome amigável é derivado em runtime via
/// `Account.displayName(for:institutions:bankAccounts:creditCards:)`.
struct AccountFormView: View {
    private enum CycleChangeScope: String, CaseIterable {
        case current
        case future

        var label: String {
            switch self {
            case .current: "Ciclo atual"
            case .future: "Próximo ciclo"
            }
        }
    }

    @Environment(AccountStore.self) private var store

    let existing: Account?
    /// Quando a tela que abriu o form tem intenção específica (ex: tela de
    /// Cartões só cria cartões), passa o tipo travado aqui. O picker de tipo
    /// some e `type` fica fixo. Em edição, esse parâmetro é ignorado (usa o
    /// tipo do `existing`).
    let lockedType: AccountType?
    let onCancel: () -> Void
    let onSaved: () -> Void

    @State private var type: AccountType = .checking
    @State private var balanceCents: Int = 0
    @State private var balanceIsNegative: Bool = false
    @State private var institutionId: UUID?
    @State private var currency: String = "BRL"

    // Bank fields
    @State private var branchId: String = ""
    @State private var accountNumber: String = ""

    // Credit card fields
    @State private var cardLastFour: String = ""
    @State private var creditLimitCents: Int = 0
    @State private var hasCreditLimit: Bool = false
    @State private var statementClosingDay: Int = 1
    @State private var paymentDueDay: Int = 10
    @State private var cycleChangeScope: CycleChangeScope = .future

    @State private var saveError: String?
    @State private var isSaving: Bool = false
    @State private var showsCurrentCyclePreview = false

    init(
        existing: Account? = nil,
        lockedType: AccountType? = nil,
        onCancel: @escaping () -> Void,
        onSaved: @escaping () -> Void
    ) {
        self.existing = existing
        self.lockedType = lockedType
        self.onCancel = onCancel
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                if type == .creditCard {
                    cardDetailsSection
                    cardCycleSection
                }
                if type == .checking {
                    bankIdentitySection
                }
                if type != .creditCard {
                    balanceSection
                }
                if let saveError {
                    errorSection(message: saveError)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Cadastrar" : "Salvar") {
                        if cycleConfigurationChanged, cycleChangeScope == .current {
                            showsCurrentCyclePreview = true
                        } else {
                            Task { await save() }
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .alert("Prévia do recálculo", isPresented: $showsCurrentCyclePreview) {
                Button("Cancelar", role: .cancel) {}
                Button("Confirmar alteração") {
                    Task { await save() }
                }
            } message: {
                Text(
                    "O ciclo atual e todos os ciclos posteriores serão reconstruídos. Compras, estornos, créditos, pagamentos e datas de quitação podem ser redistribuídos; a alteração será rejeitada se algum pagamento ficar sem dívida elegível."
                )
            }
        }
        .frame(minWidth: 520, idealWidth: 520, maxWidth: 520, minHeight: 520)
        .onAppear(perform: loadExisting)
        // Race: o stream de instituições pode emitir antes ou depois do
        // `onAppear`. Tentamos no `loadExisting` e também aqui — quem chegar
        // primeiro aplica o default; o outro vira no-op.
        .onChange(of: store.institutions) { _, _ in
            applyDefaultInstitutionIfNeeded()
        }
    }

    /// Pré-seleciona a primeira instituição emitida pelo stream quando o form
    /// é "novo" e ainda não tem nada escolhido. Sem isso o picker abre em
    /// vazio e o `canSave` fica false até o usuário escolher manualmente.
    /// No-op em edição (`institutionId` já vem populado de `loadExisting`).
    private func applyDefaultInstitutionIfNeeded() {
        guard existing == nil, institutionId == nil,
              let first = store.institutions.first
        else { return }
        institutionId = first.id
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section {
            // Picker de tipo só aparece quando a tela invocadora não travou.
            // Tela genérica de Contas → mostra. Cartões → esconde (fixo em
            // creditCard). Edição → esconde (tipo de uma conta existente não
            // muda na prática).
            if lockedType == nil, existing == nil {
                Picker("Tipo", selection: $type) {
                    ForEach(AccountType.allCases, id: \.rawValue) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .onChange(of: type) { _, newValue in
                    // Limpa campos que pertencem ao tipo "saída" pra evitar que
                    // valores digitados num modo vazem visualmente quando o
                    // usuário alterna. O save também filtra por tipo (cinto +
                    // suspensório), mas zerar aqui mantém a UX previsível.
                    if newValue == .creditCard {
                        branchId = ""
                        accountNumber = ""
                    } else {
                        cardLastFour = ""
                        creditLimitCents = 0
                        hasCreditLimit = false
                    }
                    if newValue == .creditCard {
                        balanceCents = 0
                        balanceIsNegative = false
                    }
                }
            }

            Picker(type == .creditCard ? "Emissor" : "Banco", selection: $institutionId) {
                ForEach(store.institutions) { inst in
                    Label(inst.name, systemImage: inst.kind.systemImage)
                        .tag(UUID?.some(inst.id))
                }
            }
        } header: {
            Text("Identidade")
        }
    }

    private var navigationTitle: String {
        if let existing {
            return existing.type == .creditCard ? "Editar cartão" : "Editar conta"
        }
        switch lockedType ?? type {
        case .creditCard: return "Novo cartão"
        case .checking: return "Nova conta"
        }
    }

    private var cardDetailsSection: some View {
        Section {
            TextField("Últimos 4 dígitos", text: $cardLastFour, prompt: Text("Ex: 1234"))
                .onChange(of: cardLastFour) { _, newValue in
                    // Mantém só dígitos, máx 4. Evita o usuário colar o
                    // número completo do cartão e a gente acabar guardando
                    // PAN inteiro (anti-padrão PCI).
                    let digits = newValue.filter(\.isNumber)
                    cardLastFour = String(digits.prefix(4))
                }
            Toggle("Informar limite de crédito", isOn: $hasCreditLimit)
            if hasCreditLimit {
                LabeledContent("Limite") {
                    CurrencyField(cents: $creditLimitCents)
                }
            }
        } header: {
            Text("Detalhes do cartão")
        } footer: {
            if isCardLastFourPartial {
                Text("Informe os 4 dígitos completos.")
                    .foregroundStyle(.danger)
            } else {
                Text(
                    "Last4 aparece no nome da conta como “••••\(cardLastFour.isEmpty ? "1234" : cardLastFour)” — distingue cartões diferentes do mesmo emissor. Limite é opcional."
                )
            }
        }
    }

    private var cardCycleSection: some View {
        Section {
            Picker("Dia de fechamento", selection: $statementClosingDay) {
                ForEach(1 ... 31, id: \.self) { day in
                    Text("\(day)").tag(day)
                }
            }
            Picker("Dia de vencimento", selection: $paymentDueDay) {
                ForEach(1 ... 31, id: \.self) { day in
                    Text("\(day)").tag(day)
                }
            }
            if existing != nil, cycleConfigurationChanged {
                Picker("Aplicar a partir de", selection: $cycleChangeScope) {
                    ForEach(CycleChangeScope.allCases, id: \.rawValue) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
            }
        } header: {
            Text("Ciclo da fatura")
        } footer: {
            Text(
                "Dias inexistentes usam o último dia do mês. Alterar o ciclo atual recalcula faturas, créditos e pagamentos retroativamente."
            )
        }
    }

    private var bankIdentitySection: some View {
        Section {
            TextField("Agência", text: $branchId, prompt: Text("Ex: 0001-9"))
            TextField("Número da conta", text: $accountNumber, prompt: Text("Ex: 310013887"))
        } header: {
            Text("Identidade bancária")
        } footer: {
            Text(
                "Obrigatórios. Distinguem contas do mesmo banco e habilitam o auto-detect da conta no import de OFX."
            )
        }
    }

    private var balanceSection: some View {
        Section {
            LabeledContent("Valor") {
                CurrencyField(cents: $balanceCents)
            }
            Toggle("Saldo negativo", isOn: $balanceIsNegative)
        } header: {
            Text("Saldo inicial")
        } footer: {
            Text(balanceFooterText)
        }
    }

    /// Erros de save aparecem como uma Section própria (em vez de texto
    /// solto), pra manter a consistência visual do Form-grouped.
    private func errorSection(message: String) -> some View {
        Section {
            Label {
                Text(message)
                    .foregroundStyle(.danger)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.danger)
            }
        }
    }

    // MARK: - Lógica

    private var balanceFooterText: String {
        "Quanto você já tem nessa conta hoje. Ative “Saldo negativo” se a conta está no vermelho (cheque especial)."
    }

    /// `true` quando o usuário começou a digitar o last4 mas não chegou nos 4
    /// dígitos. Mostra footer de erro e bloqueia o save.
    private var isCardLastFourPartial: Bool {
        type == .creditCard && !cardLastFour.isEmpty && cardLastFour.count != 4
    }

    private var canSave: Bool {
        // Banco sempre obrigatório (display name depende dele).
        guard institutionId != nil else { return false }

        switch type {
        case .creditCard:
            // Last4 obrigatório (4 dígitos) — distingue múltiplos cartões do
            // mesmo emissor. Ciclo (fechamento + vencimento) já tem default
            // válido via picker, sem possibilidade de input inválido.
            if cardLastFour.count != 4 { return false }
        case .checking:
            // Agência + número obrigatórios — distinguem contas do mesmo
            // banco e habilitam o auto-detect no import OFX.
            let branch = branchId.trimmingCharacters(in: .whitespaces)
            let number = accountNumber.trimmingCharacters(in: .whitespaces)
            if branch.isEmpty || number.isEmpty { return false }
        }
        return true
    }

    private func loadExisting() {
        guard let existing else {
            // Em "novo", aplica o tipo travado pela tela invocadora (se
            // houver). Sem lockedType, mantém o default `.checking`.
            if let lockedType {
                type = lockedType
            }
            applyDefaultInstitutionIfNeeded()
            return
        }
        type = existing.type
        let cents = Int(truncatingIfNeeded: Converters.decimalToCents(existing.initialBalance))
        balanceIsNegative = cents < 0
        balanceCents = abs(cents)
        institutionId = existing.institutionId
        currency = existing.currency

        if let bank = store.bankDetails(for: existing.id) {
            branchId = bank.branchId ?? ""
            accountNumber = bank.accountNumber
        }
        if let card = store.creditCard(for: existing.id) {
            cardLastFour = card.cardLastFour
            statementClosingDay = card.statementClosingDay
            paymentDueDay = card.paymentDueDay
            if let limit = card.creditLimit {
                hasCreditLimit = true
                creditLimitCents = Int(truncatingIfNeeded: Converters.decimalToCents(limit))
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let magnitude = Decimal(balanceCents) / 100
        let amount: Decimal = type == .creditCard
            ? 0
            : (balanceIsNegative ? -magnitude : magnitude)

        let bank: BankAccountDetailsInput? = {
            guard type == .checking else { return nil }
            let branch = branchId.trimmingCharacters(in: .whitespaces)
            let number = accountNumber.trimmingCharacters(in: .whitespaces)
            return BankAccountDetailsInput(
                branchId: branch.isEmpty ? nil : branch,
                accountNumber: number
            )
        }()

        let card: CreditCardDetailsInput? = {
            guard type == .creditCard else { return nil }
            let limit: Decimal? = hasCreditLimit ? Decimal(creditLimitCents) / 100 : nil
            return CreditCardDetailsInput(
                cardLastFour: cardLastFour,
                creditLimit: limit,
                statementClosingDay: statementClosingDay,
                paymentDueDay: paymentDueDay
            )
        }()

        do {
            if let existing {
                var updated = existing
                updated.type = type
                updated.initialBalance = amount
                updated.institutionId = institutionId
                updated.currency = currency
                try await store.update(
                    updated,
                    bankDetails: bank,
                    creditCardDetails: card,
                    cycleEffectiveFrom: cycleEffectiveFrom
                )
            } else {
                try await store.create(
                    type: type,
                    initialBalance: amount,
                    institutionId: institutionId,
                    currency: currency,
                    bankDetails: bank,
                    creditCardDetails: card
                )
            }
            onSaved()
        } catch {
            saveError = error.localizedDescription
            NoticeCenter.shared.report(error, title: "Falha ao salvar conta")
        }
    }

    private var cycleConfigurationChanged: Bool {
        guard let existing, let old = store.creditCard(for: existing.id) else { return false }
        return old.statementClosingDay != statementClosingDay
            || old.paymentDueDay != paymentDueDay
    }

    private var cycleEffectiveFrom: Date? {
        guard cycleConfigurationChanged, cycleChangeScope == .current,
              let existing, let old = store.creditCard(for: existing.id)
        else { return nil }
        return StatementWindow.resolve(
            closingDay: old.statementClosingDay,
            paymentDueDay: old.paymentDueDay,
            on: Date()
        ).openingDate
    }
}
