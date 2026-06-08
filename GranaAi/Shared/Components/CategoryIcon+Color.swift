import SwiftUI

/// Cor associada a cada ícone de categoria raiz. Match semântico com o
/// **glyph**, não com o `CategoryKind` — `heart.fill` é vermelho, `airplane`
/// é teal, `bus` é amarelo, etc. Caso ambíguo (ícones de figura humana,
/// ícones genéricos), pesa-se a "vibe" típica da atividade.
///
/// **Renderização canônica** (HIG-aceita):
///
/// ```swift
/// Image(systemName: icon.systemImage)
///     .symbolRenderingMode(.hierarchical)
///     .foregroundStyle(icon.color.gradient)
/// ```
///
/// `.hierarchical` divide o glyph em layers com opacity decrescente; o
/// `.gradient` no `Color` aplica um subtle dark-to-light por cima. É o
/// mesmo combo que Music, Photos, Reminders no macOS Sequoia/Tahoe usam.
///
/// **Paleta:** mistura `Color.<system>` quando o sistema tem um match
/// natural (vermelho pra coração, verde pra dinheiro) e literais inline
/// quando precisamos diferenciar entre dois ícones que cairiam na mesma
/// cor do sistema (ex: dança × cuidados pessoais, ambos rosados).
extension CategoryIcon {
    var color: Color {
        switch self {
        case .income: Color(red: 0.15, green: 0.55, blue: 0.30) // money green (cédula/dollar bill)
        case .food: .orange
        case .housing: .brown
        case .exercise: Color(red: 0.95, green: 0.40, blue: 0.10) // fire / energia (Apple Fitness rings)
        case .dance: Color(red: 0.88, green: 0.30, blue: 0.55) // magenta vivo
        case .shopping: Color(red: 0.85, green: 0.25, blue: 0.30) // scarlet (retail energy)
        case .connectivity: .cyan
        case .personalCare: Color(red: 0.95, green: 0.65, blue: 0.78) // rose pastel
        case .taxes: .gray
        case .investments: .mint
        case .entertainment: Color(red: 0.55, green: 0.20, blue: 0.30) // wine/burgundy (cortina de teatro)
        case .party: Color(red: 0.95, green: 0.30, blue: 0.65) // hot pink (confetti vibe)
        case .mobility: .yellow
        case .motorcycle: Color(red: 0.40, green: 0.50, blue: 0.25) // verde musgo (moto IRL)
        case .unclassified: Color(red: 0.60, green: 0.60, blue: 0.65) // gray neutro
        case .withdrawal: Color(red: 0.45, green: 0.65, blue: 0.45) // verde oliva
        case .health: .red
        case .professional: Color(red: 0.30, green: 0.40, blue: 0.55) // navy slate
        case .streaming: .indigo
        case .work: Color(red: 0.45, green: 0.48, blue: 0.55) // slate gray (ferramenta profissional)
        case .travel: .teal
        case .transfer: Color(red: 0.40, green: 0.55, blue: 0.85) // steel blue
        case .education: Color(red: 0.55, green: 0.40, blue: 0.75) // violeta acadêmico
        }
    }
}
