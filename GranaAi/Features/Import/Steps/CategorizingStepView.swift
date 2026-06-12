import SwiftUI

/// Step intermediário: AI rodando antes do commit.
///
/// **Barra determinada quando `total > 0`** (caso comum: já passou pela
/// checagem de cache e sabemos quantos itens vão ser classificados).
/// Fallback pra spinner indeterminado nos primeiros frames antes do
/// `.started` chegar do service.
///
/// **Visual de IA:** o card de loading ganha `aiGlowBorder` — borda
/// animada com gradiente pastel inspirada em Apple Intelligence. Sinaliza
/// "tem IA acontecendo aqui" sem texto extra.
struct CategorizingStepView: View {
    @Bindable var store: ImportStore

    var body: some View {
        VStack(spacing: 20) {
            loadingCard
            Button("Cancelar") { store.backToPreviewFromReview() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    private var loadingCard: some View {
        VStack(spacing: 14) {
            progressIndicator
            statusText
        }
        // Padding interno generoso pra que o halo interno do glow tenha
        // espaço pra "invadir" sem cobrir o conteúdo.
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .frame(maxWidth: 360)
        // Sem `.background(.background)` — o container é transparente
        // intencionalmente, deixa o glow do `aiGlowBorder` sangrar pra
        // dentro e fazer todo o visual sozinho.
        .aiGlowBorder(cornerRadius: 14)
    }

    @ViewBuilder
    private var progressIndicator: some View {
        switch store.categorization.status {
        case let .classifying(processed, total, _) where total > 0:
            ProgressView(value: Double(processed), total: Double(total))
                .progressViewStyle(.linear)
                .animation(.easeOut(duration: 0.25), value: processed)
        default:
            ProgressView()
                .progressViewStyle(.linear)
        }
    }

    /// Só renderiza os sub-estados que o usuário consegue ler antes de o
    /// `awaitCategorizationCompletion` trocar a `phase` — `.ready` e `.failed`
    /// transicionam direto pra `.reviewingCategorization`, então nunca aparecem
    /// aqui.
    @ViewBuilder
    private var statusText: some View {
        switch store.categorization.status {
        case .idle:
            Text("Preparando categorização…").foregroundStyle(.secondary)
        case let .classifying(_, _, message):
            Text(message).foregroundStyle(.secondary)
        case .ready, .failed:
            EmptyView()
        }
    }
}
