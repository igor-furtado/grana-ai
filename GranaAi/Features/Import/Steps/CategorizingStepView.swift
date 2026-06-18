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

    private enum LoadingStage {
        case preparing
        case cache
        case ai
        case finishing
    }

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
        case let .classifying(processed, total, message):
            TimelineView(.periodic(from: .now, by: 1.8)) { context in
                Text(rotatingMessage(
                    for: loadingStage(
                        processed: processed,
                        total: total,
                        message: message
                    ),
                    date: context.date
                ))
                .foregroundStyle(.secondary)
            }
        case .ready, .failed:
            EmptyView()
        }
    }

    private func loadingStage(processed: Int, total: Int, message: String) -> LoadingStage {
        if message.contains("cache") {
            return .cache
        }
        if message.contains("Finalizando") || (total > 0 && processed >= total) {
            return .finishing
        }
        if message.contains("IA") || message.contains("prontas") {
            return .ai
        }
        return .preparing
    }

    private func rotatingMessage(for stage: LoadingStage, date: Date) -> String {
        let messages: [String]
        switch stage {
        case .preparing:
            messages = [
                "Preparando categorização…",
                "Organizando transações…",
                "Separando descrições…",
            ]
        case .cache:
            messages = [
                "Verificando cache…",
                "Buscando sugestões salvas…",
                "Reaproveitando padrões…",
            ]
        case .ai:
            messages = [
                "Lendo descrições…",
                "Sugerindo categorias…",
                "Comparando padrões…",
                "Agrupando parecidas…",
            ]
        case .finishing:
            messages = [
                "Finalizando…",
                "Conferindo respostas…",
                "Aplicando sugestões…",
            ]
        }

        let slot = Int(date.timeIntervalSinceReferenceDate / 1.8)
        return messages[abs(slot) % messages.count]
    }
}
