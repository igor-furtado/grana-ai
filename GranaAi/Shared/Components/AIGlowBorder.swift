import Combine
import Foundation
import SwiftUI

/// Borda energética inspirada na linguagem visual de Apple Intelligence.
/// Usa um gradiente angular compartilhado entre três camadas calibradas para
/// um card pequeno. A lista de stops muda periodicamente e interpola entre
/// distribuições para criar a sensação de glow vivo ao redor do contorno.
struct AIGlowBorder: ViewModifier {
    var cornerRadius: CGFloat = 14
    var borderWidth: CGFloat = 1.5
    var glowWidth: CGFloat = 22
    var glowBlur: CGFloat = 12

    @State private var gradientStops = Self.generateGradientStops()
    @State private var timer: AnyCancellable?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    glow
                    border
                }
                .clipShape(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .allowsHitTesting(false)
            }
            .onAppear { updateAnimationState() }
            .onDisappear { stopAnimation() }
            .onChange(of: reduceMotion, initial: false) { _, _ in
                updateAnimationState()
            }
    }

    private var glow: some View {
        glowLayer
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Color.white, lineWidth: borderWidth)
    }

    private var glowLayer: some View {
        ZStack {
            glowStroke(
                lineWidth: glowWidth * 0.32,
                blur: 1.2,
                opacity: 0.95
            )

            glowStroke(
                lineWidth: glowWidth * 0.62,
                blur: glowBlur * 0.42,
                opacity: 0.58
            )

            glowStroke(
                lineWidth: glowWidth,
                blur: glowBlur,
                opacity: 0.34
            )
        }
    }

    private func glowStroke(
        lineWidth: CGFloat,
        blur: CGFloat,
        opacity: Double
    ) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                AngularGradient(gradient: Gradient(stops: gradientStops), center: .center),
                lineWidth: lineWidth
            )
            .blur(radius: blur)
            .opacity(opacity)
    }

    private func updateAnimationState() {
        if reduceMotion {
            stopAnimation()
            gradientStops = Self.initialGradientStops
            return
        }

        if timer == nil {
            timer = Timer.publish(every: 0.5, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    withAnimation(.easeInOut(duration: 1.0)) {
                        gradientStops = Self.generateGradientStops()
                    }
                }
        }
    }

    private func stopAnimation() {
        timer?.cancel()
        timer = nil
    }

    private static func generateGradientStops() -> [Gradient.Stop] {
        palette.map { color in
            Gradient.Stop(
                color: color,
                location: Double.random(in: 0...1)
            )
        }
        .sorted { $0.location < $1.location }
    }

    private static let initialGradientStops: [Gradient.Stop] = palette.enumerated()
        .map { index, color in
            Gradient.Stop(color: color, location: initialLocations[index])
        }
        .sorted { $0.location < $1.location }

    /// Paleta mais enxuta, ainda equilibrada entre quentes e frios.
    private static let palette: [Color] = [
        Color(red: 1.00, green: 0.55, blue: 0.65), // pink
        Color(red: 1.00, green: 0.75, blue: 0.50), // peach
        Color(red: 0.84, green: 0.63, blue: 0.96), // lavender
        Color(red: 0.55, green: 0.85, blue: 0.95), // cyan
        Color(red: 0.72, green: 0.88, blue: 0.78), // mint
        Color(red: 0.60, green: 0.75, blue: 1.00), // blue
    ]

    private static let initialLocations: [Double] = [
        0.00, 0.16, 0.33, 0.51, 0.72, 0.89,
    ]
}

extension View {
    /// Aplica a borda energética de IA.
    func aiGlowBorder(
        cornerRadius: CGFloat = 14,
        borderWidth: CGFloat = 1.5,
        glowWidth: CGFloat = 22,
        glowBlur: CGFloat = 12
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
