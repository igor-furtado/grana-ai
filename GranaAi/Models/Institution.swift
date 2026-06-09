import Foundation
import SwiftUI

/// Instituição financeira (banco / corretora). Várias `Account` podem
/// referenciar a mesma — uma corrente + uma poupança no mesmo banco
/// compartilham a Institution.
struct Institution: Identifiable, Codable, Hashable {
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
/// nome canônico, **cor da marca** e auto-detect a partir do código FEBRABAN.
/// Bancos fora dessa lista entram como `.other` e o usuário preenche o nome
/// livre na criação da Account.
///
/// **Por que enum em vez de dados editáveis pelo usuário:** identidade visual
/// de banco é dado público fixo — Inter é laranja, Nubank é roxo, etc. Manter
/// no código garante consistência visual sem ficar dependendo de seed/import.
/// Quando um banco novo precisa de suporte rico, adicionar um caso aqui é
/// uma linha; bancos não listados continuam funcionando via `.other`.
enum InstitutionKind: String, Codable, CaseIterable {
    case inter
    case itau
    case bb
    case caixa
    case c6
    case xp
    case other

    var displayName: String {
        switch self {
        case .inter: "Banco Inter"
        case .itau: "Itaú"
        case .bb: "Banco do Brasil"
        case .caixa: "Caixa Econômica Federal"
        case .c6: "C6 Bank"
        case .xp: "XP Investimentos"
        case .other: "Outro"
        }
    }

    /// FEBRABAN/COMPE oficial. Usado pelo seed inicial e pelo auto-detect
    /// no OFX (`fromCode("077") == .inter`).
    var defaultCode: String? {
        switch self {
        case .inter: "077"
        case .itau: "341"
        case .bb: "001"
        case .caixa: "104"
        case .c6: "336"
        case .xp: "102"
        case .other: nil
        }
    }

    /// SF Symbol usado como **fallback** quando o asset real do logo não
    /// está disponível no catálogo. Renderizar logos reais vs. fallback é
    /// resolvido em runtime pelo `InstitutionIcon`.
    var systemImage: String {
        switch self {
        case .other: "building.columns"
        default: "building.columns.fill"
        }
    }

    /// Nome do asset (no `Assets.xcassets`) que contém o logo real da marca.
    /// `nil` significa "use o `systemImage` como fallback".
    ///
    /// **Como ativar logo real:** arraste o PNG (1x/2x/3x) ou SVG da marca
    /// pro asset catalog com o nome retornado aqui (ex: `inter-logo`). O
    /// `InstitutionIcon` detecta automaticamente e passa a renderizar
    /// o asset no lugar do SF Symbol genérico — não precisa mexer em código.
    var logoAssetName: String? {
        switch self {
        case .inter: "inter-logo"
        case .itau: "itau-logo"
        case .bb: "bb-logo"
        case .caixa: "caixa-logo"
        case .c6: "c6-logo"
        case .xp: "xp-logo"
        case .other: nil
        }
    }

    /// Cor da marca conforme guidelines públicas (ou aproximações fiéis quando
    /// a marca não publica hex oficial). Sources documentadas no commit que
    /// trouxe estes valores; refinar em PR caso a marca atualize o branding.
    var brandColor: Color {
        switch self {
        case .inter: Color(red: 1.000, green: 0.478, blue: 0.000) // #FF7A00 — Flush Orange
        case .itau: Color(red: 1.00, green: 0.384, blue: 0.000) // #FF6200 — Blaze Orange (Pentagram 2023)
        case .bb: Color(red: 0.988, green: 0.988, blue: 0.188) // #FCFC30 — Golden Fizz
        case .caixa: Color(red: 0.004, green: 0.361, blue: 0.663) // #015CA9 — Endeavour
        case .c6: Color(red: 0.141, green: 0.141, blue: 0.161) // #242429 — Shark
        case .xp: Color(red: 0.000, green: 0.000, blue: 0.000) // #000000 — Black
        case .other: Color.secondary
        }
    }

    /// Cor de texto/ícone ideal pra sobrepor `brandColor`. Default branco
    /// porque a maioria das marcas usa cores escuras saturadas; exceção BB
    /// (amarelo claro) onde branco fica ilegível.
    var onBrandColor: Color {
        switch self {
        case .bb: .black
        default: .white
        }
    }

    /// Resolve `InstitutionKind` a partir do código FEBRABAN. Retorna `.other`
    /// pra códigos desconhecidos.
    static func fromCode(_ code: String) -> InstitutionKind {
        let normalized = code.trimmingCharacters(in: .whitespaces)
        for kind in allCases where kind.defaultCode == normalized {
            return kind
        }
        return .other
    }

    /// Subconjunto "suportado nativamente" — todos os casos com `defaultCode`
    /// não-nulo. Usado pela tela de Bancos suportados e pelo seed.
    static var supported: [InstitutionKind] {
        allCases.filter { $0.defaultCode != nil }
    }
}
