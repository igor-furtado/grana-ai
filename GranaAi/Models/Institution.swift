import Foundation

/// Instituição financeira (banco / corretora). Várias `Account` podem
/// referenciar a mesma — uma corrente + uma poupança no mesmo banco
/// compartilham a Institution.
struct Institution: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    /// Código FEBRABAN/COMPE (3 dígitos, ex: "077" para o Inter). É o que o
    /// OFX traz em `<FI><FID>` ou `<BANKID>`.
    var code: String
    var name: String
    var kind: InstitutionKind
    let createdAt: Date
    var updatedAt: Date
}

/// Conjunto fechado de instituições com suporte "rico" no app — ícone,
/// nome canônico, auto-detect a partir do código FEBRABAN. Bancos fora dessa
/// lista entram como `.other` e o usuário preenche o nome livre na criação
/// da Account.
///
/// **MVP:** só Inter. Adicionar novos casos = uma linha no enum + uma linha
/// no `displayName` e no `systemImage`. Mapeamento por `code` permite
/// auto-detect no OFX sem precisar de tabela externa.
enum InstitutionKind: String, Codable, CaseIterable, Sendable {
    case inter
    case other

    var displayName: String {
        switch self {
        case .inter: "Banco Inter"
        case .other: "Outro"
        }
    }

    /// FEBRABAN/COMPE oficial. Usado pelo seed inicial e pelo auto-detect
    /// no OFX (`fromCode("077") == .inter`).
    var defaultCode: String? {
        switch self {
        case .inter: "077"
        case .other: nil
        }
    }

    /// SF Symbol genérico no MVP. Quando adicionarmos asset catalog com logos
    /// reais, troca pra `Image(uiImage:)` resolvido por kind.
    var systemImage: String {
        switch self {
        case .inter: "creditcard.circle.fill"
        case .other: "building.columns"
        }
    }

    /// Resolve `InstitutionKind` a partir do código FEBRABAN. Retorna `.other`
    /// pra códigos desconhecidos — caller decide o que fazer (criar Institution
    /// genérica vs. mostrar erro).
    static func fromCode(_ code: String) -> InstitutionKind {
        let normalized = code.trimmingCharacters(in: .whitespaces)
        for kind in allCases where kind.defaultCode == normalized {
            return kind
        }
        return .other
    }
}
