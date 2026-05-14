import Foundation

/// Cabeçalho `<FI>` do OFX: organização (banco) + código FEBRABAN. Pode vir
/// ausente em alguns OFX legados — ficam nullable.
struct OFXInstitutionHeader: Hashable, Sendable {
    var organization: String?
    var fid: String?
}

/// `<BANKACCTFROM>`: identidade bancária da conta dona do extrato. `bankId` é
/// o FEBRABAN/COMPE; quando o OFX traz só `BANKID` (sem `<FI>`), usamos ele
/// como FID. `branchId` é a agência; `accountId` é o número da conta no banco;
/// `accountType` é o tipo OFX (CHECKING/SAVINGS/...).
struct OFXAccountKey: Hashable, Sendable {
    var bankId: String
    var branchId: String?
    var accountId: String
    var accountType: String

    /// Mapeia o `accountType` do OFX para o `AccountType` do app. OFX tem
    /// CHECKING/SAVINGS/MONEYMRKT/CREDITLINE — os dois primeiros têm
    /// correspondência direta; o resto vira `.checking` por default.
    var mappedAccountType: AccountType {
        switch accountType.uppercased() {
        case "CHECKING":   return .checking
        case "SAVINGS":    return .savings
        case "MONEYMRKT":  return .savings
        case "CREDITLINE": return .checking
        default:           return .checking
        }
    }
}

/// Uma transação solta `<STMTTRN>`. `fitid` é a chave única emitida pelo
/// banco — usada pra detecção exata de duplicata em re-imports.
struct OFXTransaction: Hashable, Sendable {
    var trnType: String        // CREDIT / DEBIT / PAYMENT / XFER / DEP / ...
    var datePosted: Date
    var amount: Decimal
    var fitid: String
    var name: String?          // contraparte (ex: nome do pagador/recebedor)
    var memo: String?          // descrição livre (ex: "Pix recebido: ...")
    var checkNumber: String?
    var refNumber: String?

    /// Descrição "amigável" pra UI/lista. Prefere `name`; cai pra `memo` se
    /// ausente; cai pra `trnType` em último caso.
    var displayDescription: String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        if let memo = memo?.trimmingCharacters(in: .whitespacesAndNewlines), !memo.isEmpty { return memo }
        return trnType
    }
}

/// Saldo final reportado pelo banco (`<LEDGERBAL>`). Não persistimos hoje —
/// fica disponível pro `ImportStore` mostrar no preview ("seu saldo no banco
/// era R$ X em [data]") e em uma fase futura pra conciliação automática.
struct OFXBalance: Hashable, Sendable {
    var amount: Decimal
    var asOf: Date
}

/// Um `<STMTRS>` completo: identidade da conta, moeda, transações e saldo.
/// Um arquivo OFX pode ter vários `STMTRS` — cada um vira um statement aqui.
struct OFXStatement: Hashable, Sendable {
    var currency: String              // CURDEF (ex: "BRL")
    var institutionHeader: OFXInstitutionHeader
    var account: OFXAccountKey
    var transactions: [OFXTransaction]
    var balance: OFXBalance?
}

/// Resultado completo do parser: cabeçalho do arquivo (charset, versão) +
/// lista de statements. Cabeçalho fica disponível pra logging/troubleshooting.
struct OFXDocument: Hashable, Sendable {
    var version: String                 // "102" pra OFX 1.x; "200"+ pra 2.x
    var encoding: String                // "USASCII" / "UTF-8" / etc.
    var charset: String?                // "1252" no formato 1.x
    var statements: [OFXStatement]
}
