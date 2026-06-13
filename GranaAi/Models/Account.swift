import Foundation

/// Conta onde o dinheiro reside (ou onde existe dívida, no caso de cartão).
///
/// A partir da Fase 4.6, `Account` é o **primitivo financeiro puro** — só
/// carrega o que é universal entre tipos. Campos específicos vivem em modelos
/// irmãos 1:1: `BankAccountDetails` (agência + número) pra contas correntes,
/// `CreditCardDetails` (last4, limite, dia de fechamento, vencimento) pra
/// cartões. CRUD sempre escreve `Account` + sibling na mesma `writeTransaction`.
///
/// O nome amigável usado pela UI é derivado em runtime via
/// `Account.displayName(for:institutions:creditCards:)`.
struct Account: Identifiable, Codable, Hashable {
    let id: UUID
    var type: AccountType
    var initialBalance: Decimal
    var archived: Bool
    var institutionId: UUID?
    /// ISO 4217. "BRL" cobre o MVP. Multi-moeda fica fora.
    var currency: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        type: AccountType,
        initialBalance: Decimal,
        archived: Bool,
        institutionId: UUID? = nil,
        currency: String = "BRL",
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.type = type
        self.initialBalance = initialBalance
        self.archived = archived
        self.institutionId = institutionId
        self.currency = currency
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum AccountType: String, Codable, CaseIterable {
    case checking
    case creditCard

    var displayName: String {
        switch self {
        case .checking: "Conta Corrente"
        case .creditCard: "Cartão de Crédito"
        }
    }

    /// Versão curta usada no `Account.displayName(for:)` — depois do nome do
    /// banco como prefixo, "Cartão de Crédito" fica verboso ("Inter Cartão de
    /// Crédito · ••••1234"). Mora aqui pra ficar do lado do `displayName`;
    /// adicionar um caso novo no enum força lembrar das duas variantes.
    var shortDisplayName: String {
        switch self {
        case .checking: "Corrente"
        case .creditCard: "Cartão"
        }
    }
}

/// Detalhes específicos de uma conta bancária (`Account.type == .checking`).
/// 1:1 com `Account` via `accountId`. Habilita o auto-detect de OFX e o
/// sufixo do display name (`Inter Corrente · 310013887`).
struct BankAccountDetails: Codable, Hashable {
    let accountId: UUID
    var branchId: String?
    var accountNumber: String
    let createdAt: Date
    var updatedAt: Date
}

/// Detalhes específicos de cartão de crédito (`Account.type == .creditCard`).
/// 1:1 com `Account` via `accountId`. `statementClosingDay` e `paymentDueDay`
/// alimentam o resolver de janela de Fatura (Fase 4.7+).
struct CreditCardDetails: Codable, Hashable {
    let accountId: UUID
    var cardLastFour: String
    /// Limite total em `Decimal` (magnitude positiva). Opcional — usuário pode
    /// não saber ou não querer informar; UI cai em "—" nesse caso.
    var creditLimit: Decimal?
    /// Dia do mês (1–31) em que a fatura fecha.
    var statementClosingDay: Int
    /// Dia do mês (1–31) em que a fatura vence.
    var paymentDueDay: Int
    let createdAt: Date
    var updatedAt: Date
}

/// Versão histórica da configuração de ciclo de um cartão. A vigência sempre
/// começa numa fronteira de ciclo; o primeiro registro também cobre imports
/// anteriores ao cadastro local.
struct CreditCardCycleConfig: Identifiable, Codable, Hashable {
    let id: UUID
    let accountId: UUID
    let effectiveFrom: Date
    let statementClosingDay: Int
    let paymentDueDay: Int
    let createdAt: Date
}

extension Account {
    /// Compõe o nome amigável da conta a partir de `instituição + tipo +
    /// identificador específico` (número da conta pra banco, `••••last4` pra
    /// cartão). Caller passa os arrays de instituições e cartões disponíveis
    /// no escopo — evita acoplar o model a um store ou container.
    ///
    /// **Exemplos:**
    /// - `Inter Corrente · 310013887`
    /// - `Inter Cartão · ••••1234`
    ///
    /// Quando o detail correspondente não está disponível (caso de race com o
    /// stream ainda emitindo), o sufixo é omitido. Quando a instituição não
    /// está disponível (caso degenerado), cai pro nome do tipo só.
    static func displayName(
        for account: Account,
        institutions: [Institution],
        bankAccounts: [BankAccountDetails] = [],
        creditCards: [CreditCardDetails] = []
    ) -> String {
        let institutionName = account.institutionId.flatMap { id in
            institutions.first { $0.id == id }?.name
        }

        let prefix = [institutionName, account.type.shortDisplayName]
            .compactMap { $0 }
            .joined(separator: " ")

        if let suffix = identifierSuffix(
            for: account,
            bankAccounts: bankAccounts,
            creditCards: creditCards
        ) {
            return "\(prefix) · \(suffix)"
        }
        return prefix
    }

    private static func identifierSuffix(
        for account: Account,
        bankAccounts: [BankAccountDetails],
        creditCards: [CreditCardDetails]
    ) -> String? {
        switch account.type {
        case .creditCard:
            guard let details = creditCards.first(where: { $0.accountId == account.id }),
                  !details.cardLastFour.isEmpty
            else { return nil }
            return "••••\(details.cardLastFour)"
        case .checking:
            guard let details = bankAccounts.first(where: { $0.accountId == account.id }),
                  !details.accountNumber.isEmpty
            else { return nil }
            return details.accountNumber
        }
    }
}
