import SwiftUI

/// Cor associada a cada ícone de categoria raiz. Usada no donut chart e em
/// badges/cards no dashboard. Mantida em extension separada (não no model)
/// porque `Color` é do SwiftUI e o model deve ser livre de UIKit/SwiftUI.
///
/// **Paleta:** tons dessaturados/mid-tone que combinam com a identidade
/// graphite + gold do app. Ícones semânticos (dinheiro/receita, comida/
/// despesa, transferência) reusam os tokens do Theme; o restante usa
/// literais inline pra manter 13+ cores distinguíveis no donut sem
/// criar 13 `.colorset` separados.
extension CategoryIcon {
    var color: Color {
        switch self {
        case .dollarSign: .income
        case .shoppingBag: Color(red: 0.722, green: 0.408, blue: 0.435) // dusty rose
        case .car: Color(red: 0.741, green: 0.471, blue: 0.310) // terracotta laranja
        case .monitor: Color(red: 0.553, green: 0.451, blue: 0.643) // muted purple
        case .utensils: .expense
        case .zap: Color(red: 0.788, green: 0.620, blue: 0.290) // ochre/amber
        case .creditCard: Color(red: 0.388, green: 0.404, blue: 0.620) // indigo dust
        case .heart: Color(red: 0.737, green: 0.435, blue: 0.541) // rose
        case .shield: .transfer
        case .trendingUp: Color(red: 0.408, green: 0.671, blue: 0.557) // mint sage
        case .fileText: Color(red: 0.510, green: 0.435, blue: 0.357) // warm taupe
        case .banknote: Color(red: 0.275, green: 0.529, blue: 0.553) // teal
        case .helpCircle: Color(red: 0.561, green: 0.522, blue: 0.494) // warm gray
        case .dice: Color(red: 0.396, green: 0.580, blue: 0.620) // dusty cyan
        case .arrowRightLeft: .transfer
        case .airplane: Color(red: 0.486, green: 0.561, blue: 0.741) // dusty blue
        case .graduationCap: Color(red: 0.620, green: 0.580, blue: 0.380) // olive/khaki
        case .briefcase: Color(red: 0.435, green: 0.502, blue: 0.580) // slate azulado
        case .calendarClock: Color(red: 0.690, green: 0.349, blue: 0.580) // orquídea/magenta
        case .gamepad: Color(red: 0.490, green: 0.404, blue: 0.682) // violeta
        case .home: Color(red: 0.706, green: 0.518, blue: 0.388) // argila/areia
        case .motorcycle: Color(red: 0.749, green: 0.349, blue: 0.302) // vermelho queimado
        case .users: Color(red: 0.851, green: 0.510, blue: 0.435) // coral
        case .user: Color(red: 0.604, green: 0.553, blue: 0.741) // lavanda
        case .dumbbell: Color(red: 0.502, green: 0.706, blue: 0.310) // verde lima
        case .laptop: Color(red: 0.318, green: 0.357, blue: 0.439) // grafite azulado
        case .playCircle: Color(red: 0.243, green: 0.553, blue: 0.831) // azul royal
        case .antenna: Color(red: 0.353, green: 0.706, blue: 0.659) // turquesa
        case .scissors: Color(red: 0.847, green: 0.467, blue: 0.580) // rosa cobre
        }
    }
}
