import Foundation
import SwiftUI

/// Form de criação/edição de conta. Apresentado como **sheet modal** pela
/// `AccountsView` (`.sheet(item:)`). Padrão idiomático no macOS pra
/// create/edit (Mail, Reminders, Notes) — dá foco total e mantém o tamanho
/// dos campos consistente.
///
/// **Sem campo "Nome".** O nome amigável é derivado em runtime via
/// `Account.displayName(for:institutions:)`.
struct AccountFormView: View {
    @Environment(AccountStore.self) private var store

    let existing: Account?
    let onCancel: () -> Void
    let onSaved: () -> Void

    @State private var type: AccountType = .checking
    @State private var balanceCents: Int = 0
    @State private var balanceIsNegative: Bool = false
    @State private var institutionId: UUID?
    @State private var branchId: String = ""
    @State private var accountNumber: String = ""
    @State private var cardLastFour: String = ""
    @State private var currency: String = "BRL"
    @State private var saveError: String?
    @State private var isSaving: Bool = false

    init(
        existing: Account? = nil,
        onCancel: @escaping () -> Void,
        onSaved: @escaping () -> Void
    ) {
        self.existing = existing
        self.onCancel = onCancel
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                if type == .creditCard {
                    cardDetailsSection
                }
                if usesBankIdentity {
                    bankIdentitySection
                }
                balanceSection
                if let saveError {
                    errorSection(message: saveError)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existing == nil ? "Nova conta" : "Editar conta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Cadastrar" : "Salvar") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
        .frame(minWidth: 520, idealWidth: 520, maxWidth: 520, minHeight: 480)
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
                }
                // Default de saldo: cartão começa "negativo" (dívida da fatura) e
                // banco começa positivo. Só aplica quando o usuário ainda não
                // digitou um valor — preserva input explícito se já tiver algo.
                if balanceCents == 0 {
                    balanceIsNegative = (newValue == .creditCard)
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
        } header: {
            Text("Detalhes do cartão")
        } footer: {
            if isCardLastFourPartial {
                Text("Informe os 4 dígitos completos.")
                    .foregroundStyle(.danger)
            } else {
                Text(
                    "Obrigatório. Aparece no nome da conta como “••••\(cardLastFour.isEmpty ? "1234" : cardLastFour)” — distingue cartões diferentes do mesmo emissor."
                )
            }
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

    private var usesBankIdentity: Bool {
        type != .creditCard
    }

    private var balanceFooterText: String {
        switch type {
        case .creditCard:
            return "Informe a dívida atual da fatura aberta (se houver). Desmarque “Saldo negativo” se o cartão tiver crédito a receber (caso raro)."
        default:
            return "Quanto você já tem nessa conta hoje. Ative “Saldo negativo” se a conta está no vermelho (cheque especial)."
        }
    }

    /// `true` quando o usuário começou a digitar o last4 mas não chegou nos 4
    /// dígitos. Mostra footer de erro e bloqueia o save.
    private var isCardLastFourPartial: Bool {
        type == .creditCard && !cardLastFour.isEmpty && cardLastFour.count != 4
    }

    private var canSave: Bool {
        // Banco sempre obrigatório (display name depende dele).
        guard institutionId != nil else { return false }
        // Cartão: last4 obrigatório (4 dígitos) — distingue múltiplos cartões
        // do mesmo emissor.
        if type == .creditCard, cardLastFour.count != 4 { return false }
        // Banco/Poupança/Corretora: agência + número obrigatórios — distinguem
        // contas do mesmo banco e habilitam o auto-detect no import OFX.
        if usesBankIdentity {
            let branch = branchId.trimmingCharacters(in: .whitespaces)
            let number = accountNumber.trimmingCharacters(in: .whitespaces)
            if branch.isEmpty || number.isEmpty { return false }
        }
        return true
    }

    private func loadExisting() {
        guard let existing else {
            applyDefaultInstitutionIfNeeded()
            return
        }
        type = existing.type
        let cents = Int(truncatingIfNeeded: Converters.decimalToCents(existing.initialBalance))
        balanceIsNegative = cents < 0
        balanceCents = abs(cents)
        institutionId = existing.institutionId
        branchId = existing.branchId ?? ""
        accountNumber = existing.accountNumber ?? ""
        cardLastFour = existing.cardLastFour ?? ""
        currency = existing.currency
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let magnitude = Decimal(balanceCents) / 100
        let amount = balanceIsNegative ? -magnitude : magnitude

        let branch = usesBankIdentity && !branchId.trimmingCharacters(in: .whitespaces).isEmpty ? branchId : nil
        let number = usesBankIdentity && !accountNumber.trimmingCharacters(in: .whitespaces)
            .isEmpty ? accountNumber : nil
        let last4 = type == .creditCard && !cardLastFour.isEmpty ? cardLastFour : nil

        do {
            if let existing {
                var updated = existing
                updated.type = type
                updated.initialBalance = amount
                updated.institutionId = institutionId
                updated.branchId = branch
                updated.accountNumber = number
                updated.cardLastFour = last4
                updated.currency = currency
                try await store.update(updated)
            } else {
                try await store.create(
                    type: type,
                    initialBalance: amount,
                    institutionId: institutionId,
                    branchId: branch,
                    accountNumber: number,
                    cardLastFour: last4,
                    currency: currency
                )
            }
            onSaved()
        } catch {
            saveError = error.localizedDescription
            ErrorCenter.shared.report(error, title: "Falha ao salvar conta")
        }
    }
}

#Preview("Nova") {
    let env = AppEnvironment()
    let store = AccountStore(container: env.container)
    return AccountFormView(onCancel: {}, onSaved: {})
        .environment(store)
}

#Preview("Edição") {
    let env = AppEnvironment()
    let store = AccountStore(container: env.container)
    let sample = Account(
        id: UUID(),
        type: .checking,
        initialBalance: 1500.00,
        archived: false,
        institutionId: nil,
        branchId: "0001-9",
        accountNumber: "310013887",
        currency: "BRL",
        createdAt: Date(),
        updatedAt: Date()
    )
    return AccountFormView(existing: sample, onCancel: {}, onSaved: {})
        .environment(store)
}
