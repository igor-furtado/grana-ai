import SwiftUI

/// Chaves do `UserDefaults` pra preferências da categorização automática.
/// Mantidas num enum pra evitar typo silencioso entre View e Store.
enum CategorizationDefaultsKey {
    static let autoApproved = "categorizationAutoApprovedThreshold"
    static let reviewRequired = "categorizationReviewRequiredThreshold"
}

/// Configurações da categorização automática (Fase 4).
/// - Ajuste dos thresholds de confiança.
/// - Botão "Recategorizar transações antigas" (opt-in).
///
/// Os thresholds são persistidos em `UserDefaults` e lidos pelo
/// `CategorizationStore` na hora de classificar/agrupar.
struct CategorizationSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    @AppStorage(CategorizationDefaultsKey.autoApproved)
    private var autoApproved: Double = 0.85

    @AppStorage(CategorizationDefaultsKey.reviewRequired)
    private var reviewRequired: Double = 0.70

    @State private var store: CategorizationStore?
    @State private var showingReview = false

    var body: some View {
        Form {
            Section {
                thresholdRow(
                    title: "Confiança para auto-aprovar",
                    help: "Sugestões da IA acima deste valor são aplicadas automaticamente, sem revisão.",
                    value: $autoApproved,
                    range: 0.5 ... 1.0
                )
                thresholdRow(
                    title: "Confiança para revisão",
                    help: "Sugestões entre este valor e o de auto-aprovação entram na fila de revisão. Abaixo, ficam em 'Não Classificado'.",
                    value: $reviewRequired,
                    range: 0.3 ... 0.95
                )
                Text(
                    "Atual: ≥ \(percent(autoApproved)) auto-aplica · ≥ \(percent(reviewRequired)) revisar · abaixo cai em Não Classificado."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Confiança")
            } footer: {
                Text(
                    "Valores recomendados: auto-aprovar 0.85, revisão 0.70. Ajuste pra cima se a IA estiver errando muito; pra baixo se você confia bastante no acerto."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Manutenção") {
                Button {
                    runRecategorize()
                } label: {
                    Label("Recategorizar transações antigas", systemImage: "wand.and.stars")
                }
                .disabled(isRunning)
                Text(
                    "Reprocessa todas as transações que ainda estão em 'Não Classificado'. Usa o cache atual + correções recentes."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if let store, case let .classifying(processed, total, message) = store.status {
                    ProgressView(
                        value: Double(processed),
                        total: Double(max(total, 1))
                    ) {
                        Text(message)
                            .font(.caption)
                    }
                }
                if let store, case let .failed(message) = store.status {
                    Text(message).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Categorização")
        .navigationSubtitle("Pipeline de categorização automática via IA")
        .task {
            if store == nil {
                let newStore = CategorizationStore(container: environment.container)
                await newStore.loadCategories()
                store = newStore
            }
            syncThresholdsToStore()
        }
        .onChange(of: autoApproved) { _, _ in syncThresholdsToStore() }
        .onChange(of: reviewRequired) { _, _ in syncThresholdsToStore() }
        .sheet(isPresented: $showingReview) {
            if let store {
                CategorizationReviewView(store: store)
            }
        }
    }

    private func thresholdRow(
        title: String,
        help: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(percent(value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 0.05)
            Text(help).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private var isRunning: Bool {
        guard let store else { return false }
        if case .classifying = store.status { return true }
        return false
    }

    private func runRecategorize() {
        guard let store else { return }
        showingReview = true
        store.recategorizeUnclassified()
    }

    private func syncThresholdsToStore() {
        guard let store else { return }
        store.thresholds = CategorizationService.ConfidenceThresholds(
            autoApproved: autoApproved,
            reviewRequired: reviewRequired,
            absoluteMinimum: 0.30
        )
    }
}

#Preview {
    NavigationStack {
        CategorizationSettingsView()
    }
    .environment(AppEnvironment())
    .frame(width: 700, height: 500)
}
