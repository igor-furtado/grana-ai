import Foundation
import SwiftUI

/// Formulário de criação/edição de transação.
///
/// **Modo "novo" vs "edição":** o init aceita `Transaction?` — `nil` significa
/// novo registro. O título do sheet e o botão "Salvar" adaptam o
/// comportamento sem precisar de duas Views diferentes.
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
    @State private var occurredAt: Date = Date()
    @State private var accountId: UUID?
    @State private var categoryId: UUID?
    @State private var subcategoryId: UUID?
    @State private var notes: String = ""
    @State private var saveError: String?

    init(existing: Transaction? = nil) {
        self.existing = existing
    }

    var body: some View {
        NavigationStack {
            Form {
                // `prompt:` é o placeholder DENTRO do campo. O primeiro
                // argumento ("Descrição") é o LABEL — no macOS aparece à
                // esquerda do campo; no iOS é só pra acessibilidade.
                TextField(
                    "Descrição",
                    text: $description,
                    prompt: Text("Ex: Almoço no restaurante")
                )

                LabeledContent("Valor") {
                    CurrencyField(cents: $amountCents)
                }

                // Sem opção "Selecione" — o usuário escolhe da lista direto.
                // `accountId` é defaultado pra primeira conta em `loadExisting`.
                Picker("Conta", selection: $accountId) {
                    ForEach(store.accounts) { account in
                        Text(account.name).tag(UUID?.some(account.id))
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
                    }
                }

                if let categoryId,
                   !store.subcategories(of: categoryId).isEmpty {
                    Picker("Subcategoria", selection: $subcategoryId) {
                        Text("(nenhuma)").tag(UUID?.none)
                        ForEach(store.subcategories(of: categoryId)) { sub in
                            Text(sub.name).tag(UUID?.some(sub.id))
                        }
                    }
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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

    // MARK: - Save

    private var canSave: Bool {
        !description.trimmingCharacters(in: .whitespaces).isEmpty
            && amountCents > 0
            && accountId != nil
            && categoryId != nil
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
        notes = existing.notes ?? ""
    }

    private func save() async {
        guard let accountId, let categoryId else { return }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesValue = trimmedNotes.isEmpty ? nil : trimmedNotes
        let amount = Decimal(amountCents) / 100

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
                try await store.update(updated)
            } else {
                try await store.add(
                    accountId: accountId,
                    categoryId: categoryId,
                    subcategoryId: subcategoryId,
                    amount: amount,
                    occurredAt: occurredAt,
                    description: description,
                    notes: notesValue
                )
            }
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#Preview("Nova") {
    let env = AppEnvironment()
    let store = TransactionStore(database: env.database)
    return TransactionFormView()
        .environment(store)
}

#Preview("Edição") {
    let env = AppEnvironment()
    let store = TransactionStore(database: env.database)
    let sample = Transaction(
        id: UUID(),
        accountId: UUID(),
        categoryId: UUID(),
        subcategoryId: nil,
        amount: 42.90,
        occurredAt: Date(),
        description: "Café da manhã",
        notes: "Padaria perto de casa",
        createdAt: Date(),
        updatedAt: Date()
    )
    return TransactionFormView(existing: sample)
        .environment(store)
}
