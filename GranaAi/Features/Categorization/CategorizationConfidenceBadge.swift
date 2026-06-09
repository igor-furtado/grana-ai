import SwiftUI

/// Pill que mostra a confiança da IA (0–100%) com cor por bucket.
/// Verde = alta (auto-aprovada), laranja = média (revisão), vermelho = baixa.
struct CategorizationConfidenceBadge: View {
    let confidence: Double
    let bucket: CategorizationSuggestion.ConfidenceBucket

    var body: some View {
        Text(percentText)
            .font(.caption.monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18))
            .foregroundStyle(tint)
            .clipShape(Capsule())
            .help(helpText)
    }

    private var percentText: String {
        "\(Int((confidence * 100).rounded()))%"
    }

    private var tint: Color {
        switch bucket {
        case .high: .green
        case .medium: .orange
        case .low: .red
        }
    }

    private var helpText: String {
        switch bucket {
        case .high: "Confiança alta — categoria auto-aplicada."
        case .medium: "Confiança média — revise antes de confirmar."
        case .low: "Confiança baixa — categorização incerta."
        }
    }
}
