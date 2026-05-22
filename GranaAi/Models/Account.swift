import Foundation

/// Conta onde o dinheiro reside (corrente, poupança, carteira física,
/// conta corretora).
///
/// **Campos bancários (`institutionId`, `branchId`, `accountNumber`):** todos
/// nullable porque "Carteira" não tem agência nem banco. Contas criadas
/// automaticamente a partir de OFX preenchem os três — o auto-detect usa a
/// tripla `(institutionId, branchId, accountNumber)` como identidade pra
/// decidir entre "reusar conta existente" ou "criar nova".
struct Account: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var type: AccountType
    var initialBalance: Decimal
    var archived: Bool
    var institutionId: UUID?
    var branchId: String?
    var accountNumber: String?
    /// ISO 4217. "BRL" cobre o MVP. Multi-moeda fica fora.
    var currency: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        name: String,
        type: AccountType,
        initialBalance: Decimal,
        archived: Bool,
        institutionId: UUID? = nil,
        branchId: String? = nil,
        accountNumber: String? = nil,
        currency: String = "BRL",
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.initialBalance = initialBalance
        self.archived = archived
        self.institutionId = institutionId
        self.branchId = branchId
        self.accountNumber = accountNumber
        self.currency = currency
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum AccountType: String, Codable, CaseIterable {
    case checking
    case savings
    case wallet
    case brokerage
    case creditCard

    var displayName: String {
        switch self {
        case .checking:   "Conta Corrente"
        case .savings:    "Poupança"
        case .wallet:     "Carteira"
        case .brokerage:  "Conta Corretora"
        case .creditCard: "Cartão de Crédito"
        }
    }
}
