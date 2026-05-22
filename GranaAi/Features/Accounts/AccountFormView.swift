import Foundation
import SwiftUI

/// Form de criação/edição de conta. Modo "novo" se `existing == nil`,
/// "edição" caso contrário — padrão idêntico ao `TransactionFormView`.
///
/// Quando `type != .wallet` os campos bancários (instituição, agência, número)
/// aparecem. Carteira não tem banco, então a seção bancária some — evita o
/// usuário preencher dados que não fazem sentido pra essa categoria.
struct AccountFormView: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let existing: Account?

    @State private var name: String = ""
    @State private var type: AccountType = .checking
    @State private var initialBalanceCents: Int = 0
    @State private var institutionId: UUID?
    @State private var branchId: String = ""
    @State private var accountNumber: String = ""
    @State private var currency: String = "BRL"
    @State private var saveError: String?

    init(existing: Account? = nil) {
        self.existing = existing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Conta") {
                    TextField("Nome", text: $name, prompt: Text("Ex: Conta Inter principal"))
                    Picker("Tipo", selection: $type) {
                        ForEach(AccountType.allCases, id: \.rawValue) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    LabeledContent("Saldo inicial") {
                        CurrencyField(cents: $initialBalanceCents)
                    }
                }

                if type != .wallet {
                    Section("Banco") {
                        Picker("Instituição", selection: $institutionId) {
                            Text("Nenhuma").tag(UUID?.none)
                            ForEach(store.institutions) { inst in
                                Label(inst.name, systemImage: inst.kind.systemImage)
                                    .tag(UUID?.some(inst.id))
                            }
                        }
                        TextField("Agência", text: $branchId, prompt: Text("Ex: 0001-9"))
                        TextField("Número da conta", text: $accountNumber, prompt: Text("Ex: 310013887"))
                        Picker("Moeda", selection: $currency) {
                            Text("BRL").tag("BRL")
                        }
                    }
                }

                if let saveError {
                    Text(saveError)
                        .foregroundStyle(.danger)
                        .font(.callout)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existing == nil ? "Nova conta" : "Editar conta")
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
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func loadExisting() {
        guard let existing else { return }
        name = existing.name
        type = existing.type
        initialBalanceCents = Int(truncatingIfNeeded: Converters.decimalToCents(existing.initialBalance))
        institutionId = existing.institutionId
        branchId = existing.branchId ?? ""
        accountNumber = existing.accountNumber ?? ""
        currency = existing.currency
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = Decimal(initialBalanceCents) / 100
        let branch = branchId.trimmingCharacters(in: .whitespaces).isEmpty ? nil : branchId
        let number = accountNumber.trimmingCharacters(in: .whitespaces).isEmpty ? nil : accountNumber
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
            dismiss()
        } catch {
            saveError = error.localizedDescription
            ErrorCenter.shared.report(error, title: "Falha ao salvar conta")
        }
    }
}

#Preview("Nova") {
    let env = AppEnvironment()
    let store = AccountStore(container: env.container)
    return AccountFormView()
        .environment(store)
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
    return AccountFormView(existing: sample)
        .environment(store)
}
