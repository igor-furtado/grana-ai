import Foundation
import SwiftUI

/// Catálogo read-only das instituições com suporte nativo no app — auto-detect
/// via código FEBRABAN no import OFX, ícone canônico e cor da marca. O
/// usuário não cria nem edita instituições; o que ele cria é **conta** (que
/// referencia uma instituição). Esta tela existe pra responder "que bancos
/// o Grana AI reconhece?" sem ter que abrir o form de conta.
struct SupportedInstitutionsView: View {
    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 16),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(
                    "Bancos com auto-detecção de extrato OFX e identidade visual própria. Bancos fora dessa lista funcionam normalmente — entram como “Outro” na criação da conta."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(InstitutionKind.supported, id: \.rawValue) { kind in
                        InstitutionCatalogCard(kind: kind)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Bancos suportados")
        .navigationSubtitle("\(InstitutionKind.supported.count) bancos disponíveis")
    }
}

private struct InstitutionCatalogCard: View {
    let kind: InstitutionKind

    var body: some View {
        HStack(spacing: 14) {
            InstitutionIcon(kind: kind, size: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName)
                    .font(.body.weight(.semibold))
                if let code = kind.defaultCode {
                    Text("FEBRABAN \(code)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(kind.brandColor.opacity(0.25), lineWidth: 1)
        )
    }
}
