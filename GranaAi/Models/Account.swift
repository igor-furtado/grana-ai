import Foundation

/// Conta onde o dinheiro reside.
///
/// A partir da Fase 4.5 não há mais campo `name` — a conta é identificada pela
/// combinação `institution + tipo + dados específicos do tipo` (número/agência
/// pra bancos, últimos 4 dígitos pra cartão). O nome amigável usado pela UI é
/// derivado em runtime via `AccountStore.displayName(for:)`.
///
/// **Campos opcionais por tipo:**
/// - `branchId` / `accountNumber`: para contas bancárias (checking/savings/brokerage).
///   Obrigatórios na prática se quiser importar OFX (auto-detect usa a tripla),
///   mas o schema do PowerSync não enforce isso.
/// - `cardLastFour`: só pra `creditCard`. 4 dígitos. Convenção PCI (nunca o
///   número completo).
struct Account: Identifiable, Codable, Hashable {
    let id: UUID
    var type: AccountType
    var initialBalance: Decimal
    var archived: Bool
    var institutionId: UUID?
    var branchId: String?
    var accountNumber: String?
    /// Últimos 4 dígitos do cartão de crédito. NULL pra qualquer outro tipo.
    var cardLastFour: String?
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
        branchId: String? = nil,
        accountNumber: String? = nil,
        cardLastFour: String? = nil,
        currency: String = "BRL",
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.type = type
        self.initialBalance = initialBalance
        self.archived = archived
        self.institutionId = institutionId
        self.branchId = branchId
        self.accountNumber = accountNumber
        self.cardLastFour = cardLastFour
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

extension Account {
    /// Compõe o nome amigável da conta a partir de `instituição + tipo +
    /// identificador específico` (número da conta pra banco/corretora,
    /// `••••last4` pra cartão). Caller passa o array de instituições
    /// disponível no escopo — evita acoplar o model a um store ou container.
    ///
    /// **Exemplos:**
    /// - `Inter Corrente · 310013887`
    /// - `Inter Cartão · ••••1234`
    /// - `XP Corretora · 9876543`
    ///
    /// Quando os campos opcionais estão vazios, o sufixo correspondente é
    /// omitido (não vira pontuação solta). Quando a instituição não está
    /// disponível (caso degenerado), cai pro nome do tipo só.
    static func displayName(for account: Account, institutions: [Institution]) -> String {
        let institutionName = account.institutionId.flatMap { id in
            institutions.first { $0.id == id }?.name
        }

        let prefix = [institutionName, account.type.shortDisplayName]
            .compactMap { $0 }
            .joined(separator: " ")

        if let suffix = identifierSuffix(for: account) {
            return "\(prefix) · \(suffix)"
        }
        return prefix
    }

    private static func identifierSuffix(for account: Account) -> String? {
        switch account.type {
        case .creditCard:
            guard let last4 = account.cardLastFour, !last4.isEmpty else { return nil }
            return "••••\(last4)"
        case .checking:
            guard let number = account.accountNumber, !number.isEmpty else { return nil }
            return number
        }
    }
}
