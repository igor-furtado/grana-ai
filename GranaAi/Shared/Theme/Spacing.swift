import CoreGraphics

/// Escala de spacing semântica baseada no grid de 8pt da Apple HIG (com 4 e
/// 12 incluídos por serem onipresentes em controles do sistema). Use estas
/// constantes em vez de números mágicos — quando o ritmo visual do app
/// precisar ajustar, muda aqui e propaga.
///
/// **Como escolher**:
/// - `xs` (4): elementos colados/relacionados (ícone + label no mesmo control)
/// - `sm` (8): default entre items numa row/HStack
/// - `md` (12): entre seções pequenas de um card
/// - `lg` (16): margens padrão, entre cards num grid
/// - `xl` (20): entre seções num screen
/// - `xxl` (24): padding top-level de telas
/// - `xxxl` (32): entre blocos majoritários (separar grupos visuais grandes)
///
/// **Quando NÃO usar**: tamanhos de elementos (ex: altura fixa de um card,
/// largura de um ícone). Pra isso, declare constantes locais nomeadas no
/// próprio arquivo — `Spacing` é apenas pra distância entre elementos.
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}
