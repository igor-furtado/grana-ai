import Foundation
import SwiftUI

/// Form inline de criação/edição de conta. Renderizado **dentro** da
/// `AccountsView` (não como sheet), seguindo o padrão do Finest: o usuário
/// vê o form expandindo na mesma página, sem context-switch modal.
///
/// **Identidade visual da conta vem da Institution.** O usuário escolhe o
/// banco (logo + cor da marca canônica) — não há picker de emoji/cor por
/// conta. Reduz fricção e garante consistência ("Inter é sempre laranja").
///
/// **Campos avançados (agência, número, moeda)** ficam atrás de um
/// `DisclosureGroup` colapsado. Continuam existindo porque o auto-detect do
/// importer OFX usa a tripla `(institution, branch, account_number)` pra
/// reusar contas — quem importa OFX precisa preencher; quem não importa,
/// pode ignorar.
struct AccountFormView: View {
    @Environment(AccountStore.self) private var store

    let existing: Account?
    let onCancel: () -> Void
    let onSaved: () -> Void

    @State private var name: String = ""
    @State private var type: AccountType = .checking
    @State private var balanceCents: Int = 0
    @State private var balanceIsNegative: Bool = false
    @State private var institutionId: UUID?
    @State private var branchId: String = ""
    @State private var accountNumber: String = ""
    @State private var currency: String = "BRL"
    @State private var showAdvanced: Bool = false
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(existing == nil ? "Nova conta" : "Editar conta")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Cancelar", action: onCancel)
                    .buttonStyle(.bordered)
            }

            nameField
            typeField
            balanceField
            institutionField

            if usesBankIdentity {
                DisclosureGroup(isExpanded: $showAdvanced) {
                    advancedFields
                        .padding(.top, 8)
                } label: {
                    Text("Avançado")
                        .font(.callout.weight(.medium))
                }
            }

            if let saveError {
                Text(saveError)
                    .foregroundStyle(.danger)
                    .font(.callout)
            }

            Button(action: { Task { await save() } }) {
                HStack {
                    Spacer()
                    if isSaving { ProgressView().controlSize(.small).tint(.white) }
                    Text(existing == nil ? "Cadastrar conta" : "Salvar alterações")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(canSave ? Color.brandSecondary : Color.secondary.opacity(0.4))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSave || isSaving)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.brandSecondary.opacity(0.4), lineWidth: 1)
        )
        .onAppear(perform: loadExisting)
    }

    // MARK: - Campos

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nome da conta").font(.caption.weight(.medium))
            TextField("Ex: Inter principal", text: $name)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var typeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tipo").font(.caption.weight(.medium))
            Picker("Tipo", selection: $type) {
                ForEach(AccountType.allCases, id: \.rawValue) { t in
                    Text(t.displayName).tag(t)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .onChange(of: type) { _, newValue in
                // Mudou pra wallet → limpa o banco selecionado (carteira não
                // tem instituição). Mudou pra qualquer outro → mantém o que
                // estava (geralmente nada).
                if newValue == .wallet { institutionId = nil }
            }
        }
    }

    private var balanceField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Saldo inicial (opcional)").font(.caption.weight(.medium))
            HStack(spacing: 8) {
                Button(action: { balanceIsNegative.toggle() }) {
                    Text(balanceIsNegative ? "−" : "+")
                        .font(.title3.weight(.semibold))
                        .frame(width: 32, height: 28)
                        .foregroundStyle(balanceIsNegative ? .danger : .success)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill((balanceIsNegative ? Color.expense : Color.income).opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .help(balanceIsNegative ? "Saldo negativo (ex: cheque especial)" : "Saldo positivo")

                CurrencyField(cents: $balanceCents)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
            Text("Quanto você já tem nessa conta hoje. Use o botão − para contas no vermelho (cheque especial, fatura aberta).")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var institutionField: some View {
        if type != .wallet {
            VStack(alignment: .leading, spacing: 6) {
                Text(type == .creditCard ? "Emissor" : "Banco")
                    .font(.caption.weight(.medium))
                Picker(selection: $institutionId) {
                    Text("Nenhum").tag(UUID?.none)
                    ForEach(store.institutions) { inst in
                        Label(inst.name, systemImage: inst.kind.systemImage)
                            .tag(UUID?.some(inst.id))
                    }
                } label: { EmptyView() }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private var advancedFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Agência").font(.caption.weight(.medium))
                TextField("Ex: 0001-9", text: $branchId)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Número da conta").font(.caption.weight(.medium))
                TextField("Ex: 310013887", text: $accountNumber)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Preencha agência e número se você for importar extratos OFX desta conta — o app usa esses campos pra detectar e reaproveitar a conta no import.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Lógica

    private var usesBankIdentity: Bool {
        type != .wallet && type != .creditCard
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func loadExisting() {
        guard let existing else { return }
        name = existing.name
        type = existing.type
        let cents = Int(truncatingIfNeeded: Converters.decimalToCents(existing.initialBalance))
        balanceIsNegative = cents < 0
        balanceCents = abs(cents)
        institutionId = existing.institutionId
        branchId = existing.branchId ?? ""
        accountNumber = existing.accountNumber ?? ""
        currency = existing.currency
        showAdvanced = !(existing.branchId ?? "").isEmpty || !(existing.accountNumber ?? "").isEmpty
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let magnitude = Decimal(balanceCents) / 100
        let amount = balanceIsNegative ? -magnitude : magnitude

        let branch = usesBankIdentity && !branchId.trimmingCharacters(in: .whitespaces).isEmpty ? branchId : nil
        let number = usesBankIdentity && !accountNumber.trimmingCharacters(in: .whitespaces).isEmpty ? accountNumber : nil
        let effectiveInstitution = (type == .wallet) ? nil : institutionId

        do {
            if let existing {
                var updated = existing
                updated.name = trimmedName
                updated.type = type
                updated.initialBalance = amount
                updated.institutionId = effectiveInstitution
                updated.branchId = branch
                updated.accountNumber = number
                updated.currency = currency
                try await store.update(updated)
            } else {
                try await store.create(
                    name: trimmedName,
                    type: type,
                    initialBalance: amount,
                    institutionId: effectiveInstitution,
                    branchId: branch,
                    accountNumber: number,
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
        .frame(width: 520)
        .padding()
}

#Preview("Edição") {
    let env = AppEnvironment()
    let store = AccountStore(container: env.container)
    let sample = Account(
        id: UUID(),
        name: "Inter principal",
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
        .frame(width: 520)
        .padding()
}
