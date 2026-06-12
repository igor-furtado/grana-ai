import Foundation
import SwiftUI

/// Borda animada com gradiente colorido pastel, inspirada na linguagem
/// visual de **Apple Intelligence** e do **Xcode AI input**. Sinaliza
/// visualmente "tem IA acontecendo aqui" — use em qualquer view que esteja
/// em loading de operação IA (categorização, sugestão, geração).
///
/// **Aplicação:** modifier `.aiGlowBorder()` em qualquer View.
///
/// **Visual:** borda branca crisp de 1.5pt **por cima** de um halo colorido
/// blurred que **sangra pra dentro e pra fora** da forma. O halo é um
/// stroke largo (`glowWidth`) preenchido com `MeshGradient` animado e
/// blurrado pesadamente — metade do stroke fica fora do container, metade
/// dentro, criando a sensação de "glow invadindo o container" do Xcode AI.
///
/// **Container ideal:** transparente (sem `.background(.background)`) ou
/// translúcido. Background sólido bloqueia o glow interno e mata o efeito.
///
/// **Acessibilidade:** respeita `accessibilityReduceMotion` — em modo
/// reduzido, congela no frame inicial em vez de animar.
struct AIGlowBorder: ViewModifier {
    var cornerRadius: CGFloat = 14
    /// Espessura da borda branca crisp por cima do halo.
    var borderWidth: CGFloat = 1.5
    /// Espessura do stroke que recebe o gradiente colorido. Quanto maior,
    /// mais o halo bleeda pra dentro e pra fora.
    var glowWidth: CGFloat = 22
    /// Raio do blur aplicado ao stroke colorido. Suaviza o halo —
    /// valores altos espalham mais luz, baixos mantêm contorno mais nítido.
    var glowBlur: CGFloat = 16

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    glow
                    border
                }
                .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    private var glow: some View {
        if reduceMotion {
            glowLayer(time: 0)
        } else {
            TimelineView(.animation) { context in
                let t = Float(context.date.timeIntervalSinceReferenceDate)
                glowLayer(time: t)
            }
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Color.white, lineWidth: borderWidth)
    }

    private func glowLayer(time t: Float) -> some View {
        // `amp` controla quanto cada ponto interno se desloca da posição
        // central (0.25 = ±25% do tamanho). Mais que isso e o mesh começa
        // a "colapsar" visualmente nas bordas.
        let amp: Float = 0.25
        // `speed` é a velocidade-base do oscilador. Cada ponto interno
        // multiplica por um fator distinto (0.6 / 0.8 / 0.9 / 1.1) pra
        // evitar sincronia visual que ficaria mecânica.
        let speed: Float = 0.6

        let points: [SIMD2<Float>] = [
            SIMD2(0, 0),
            SIMD2(0.5 + amp * sin(t * speed), 0),
            SIMD2(1, 0),
            SIMD2(0, 0.5 + amp * cos(t * speed * 0.8)),
            SIMD2(0.5, 0.5),
            SIMD2(1, 0.5 + amp * sin(t * speed * 1.1)),
            SIMD2(0, 1),
            SIMD2(0.5 + amp * cos(t * speed * 0.9), 1),
            SIMD2(1, 1),
        ]

        return MeshGradient(
            width: 3,
            height: 3,
            points: points,
            colors: Self.palette
        )
        .mask {
            // Stroke largo, centrado no path da borda. SwiftUI stroke
            // distribui a espessura metade pra cada lado do path — então
            // `glowWidth: 22` significa ~11pt de glow pra dentro e ~11pt
            // pra fora do retângulo. O blur suaviza e estende ainda mais.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(lineWidth: glowWidth)
        }
        .blur(radius: glowBlur)
    }

    /// Paleta vibrante inspirada em Apple Intelligence. Saturação um pouco
    /// mais alta que pastel puro pra compensar a perda de intensidade do
    /// blur pesado. Ordem segue grid 3×3 (linha por linha, top-left →
    /// bottom-right) — trocar índices muda o fluxo de cor.
    private static let palette: [Color] = [
        Color(red: 1.00, green: 0.55, blue: 0.65), // pink
        Color(red: 1.00, green: 0.75, blue: 0.50), // peach
        Color(red: 1.00, green: 0.85, blue: 0.55), // yellow
        Color(red: 0.75, green: 0.55, blue: 0.95), // purple
        Color(red: 0.95, green: 0.80, blue: 1.00), // lavender (center)
        Color(red: 0.55, green: 0.85, blue: 0.95), // cyan
        Color(red: 0.60, green: 0.75, blue: 1.00), // blue
        Color(red: 0.75, green: 0.90, blue: 0.75), // mint
        Color(red: 1.00, green: 0.65, blue: 0.85), // pink-magenta
    ]
}

extension View {
    /// Aplica a borda animada de "IA acontecendo aqui" — ver `AIGlowBorder`.
    func aiGlowBorder(
        cornerRadius: CGFloat = 14,
        borderWidth: CGFloat = 1.5,
        glowWidth: CGFloat = 22,
        glowBlur: CGFloat = 16
    ) -> some View {
        modifier(
            AIGlowBorder(
                cornerRadius: cornerRadius,
                borderWidth: borderWidth,
                glowWidth: glowWidth,
                glowBlur: glowBlur
            )
        )
    }
}
