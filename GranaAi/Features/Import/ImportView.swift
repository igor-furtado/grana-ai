import SwiftUI
import UniformTypeIdentifiers

/// Wizard de importação OFX/CSV apresentado como **sheet modal** sobre a tela
/// de Transações (e a partir da tela de Histórico de Importações). Não vive
/// na navegação principal — sempre é triggerado pelo usuário via botão
/// "Importar extrato" ou pelo drag & drop da tela de histórico.
///
/// **Por que `@State` pra `ImportStore`:** store é local à apresentação, não
/// faz sentido subir pra `AppEnvironment`. Quando o modal é fechado, o store
/// some junto — cada nova abertura começa em `.idle`.
///
/// **Composição:** este arquivo só lida com (a) bootstrap do store, (b)
/// roteamento de `phase` → step view e (c) o `fileImporter` do sistema. Cada
/// step do enum `Phase` vive num arquivo separado em [Steps/], pra essa view
/// não virar um catch-all de 800+ linhas.
struct ImportView: View {
    /// Quando setado, pula o file picker do sistema e carrega esse arquivo
    /// diretamente — usado pelo drag & drop da tela de histórico, onde o
    /// usuário já indicou o arquivo soltando-o na janela.
    let initialFile: URL?

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var store: ImportStore?
    @State private var fileImporterShown = false
    /// Marcada como `true` no callback do `fileImporter` quando o usuário
    /// efetivamente escolhe um arquivo (ou bate num erro real). Permite
    /// distinguir cancelamento do picker (binding flipa pra false sem
    /// callback) de seleção bem-sucedida, e fechar a sheet no primeiro caso.
    @State private var fileWasPicked = false
    /// Guard contra `initialize()` rodar duas vezes — `.task` pode reentrar
    /// se a sheet for re-renderizada antes do `await loadInitialData()`
    /// retornar (raríssimo, mas o efeito colateral seria dois pickers
    /// abrindo em sequência).
    @State private var didInitialize = false

    init(initialFile: URL? = nil) {
        self.initialFile = initialFile
    }

    var body: some View {
        NavigationStack {
            Group {
                if let store {
                    wizard(store: store)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .task { initialize() }
                }
            }
            .navigationTitle("Importar extrato")
            .fileImporter(
                isPresented: $fileImporterShown,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    if let url = urls.first {
                        fileWasPicked = true
                        Task { await store?.loadFile(url: url) }
                    }
                case let .failure(err):
                    fileWasPicked = true
                    store?.reportFileImportFailure(err)
                }
            }
            .onChange(of: fileImporterShown) { _, isShown in
                if isShown {
                    fileWasPicked = false
                    return
                }
                // Picker fechou. Se não houve seleção, é cancelamento — fecha
                // a sheet, já que o botão que abriu também dispara o picker.
                // Delay curto pra dar tempo do callback do fileImporter rodar
                // antes da gente decidir (ordem entre callback e binding flip
                // não é garantida no SwiftUI).
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    if !fileWasPicked { dismiss() }
                }
            }
        }
        // Sheet sem cap de altura crescia além da janela em telas pequenas.
        // Limita o tamanho mantendo um ideal confortável.
        .frame(
            minWidth: 700, idealWidth: 760, maxWidth: 900,
            minHeight: 540, idealHeight: 660, maxHeight: 760
        )
    }

    private func initialize() {
        guard !didInitialize else { return }
        didInitialize = true
        let s = ImportStore(container: environment.container)
        store = s
        Task {
            // Sequenciamento crítico: `loadInitialData` popula `accounts` /
            // `institutions`, que `loadCSV` e o picker de conta no preview OFX
            // precisam ler. Sem o await aqui, `loadCSV` pode rodar contra um
            // `accounts` vazio e falhar com `noCreditCardAccount` mesmo quando
            // o usuário tem conta-cartão cadastrada.
            await s.loadInitialData()
            guard !Task.isCancelled else { return }

            if let initialFile {
                // Drop: usuário já indicou o arquivo. Pula o picker.
                await s.loadFile(url: initialFile)
            } else {
                // Manual: abre o picker do sistema pra escolher arquivo.
                fileImporterShown = true
            }
        }
    }

    private func wizard(store: ImportStore) -> some View {
        VStack(spacing: 0) {
            if let stepperIndex = Self.stepperIndex(for: store.phase) {
                WizardStepper(
                    steps: ["Revisar", "Categorizar", "Concluir"],
                    currentIndex: stepperIndex
                )
            }
            phaseContent(store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // `.done` fecha a sheet — toast verde com undo cobre o feedback.
        // `.failed` NÃO fecha: se o usuário já estava no meio da revisão e
        // perdeu o trabalho, ele precisa ver a tela de erro com opção
        // explícita de Recomeçar ou Fechar. O toast vermelho que vem junto
        // mostra a causa.
        .onChange(of: store.phase) { _, newPhase in
            if case .done = newPhase { dismiss() }
        }
    }

    /// Mapeia a `Phase` do wizard pro índice atual do stepper.
    /// `nil` = stepper escondido (idle, loading, failed).
    /// `steps.count` (3) = todos os steps marcados como concluídos.
    private static func stepperIndex(for phase: ImportStore.Phase) -> Int? {
        switch phase {
        case .idle, .loading, .failed:
            return nil
        case .ofxReview, .csvReview:
            return 0
        case .categorizing, .reviewingCategorization:
            return 1
        case .confirming:
            return 2
        case .done:
            return 3
        }
    }

    @ViewBuilder
    private func phaseContent(store: ImportStore) -> some View {
        switch store.phase {
        case .idle:
            // Estado transitório: `initialize()` está esperando
            // `loadInitialData` antes de ou disparar `loadFile` (drag) ou
            // o `.fileImporter` (manual). Sem decisão de fluxo aqui — esse
            // ProgressView é só um placeholder enquanto o bootstrap rola.
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .loading(progress):
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(progress)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ofxReview:
            OFXReviewStepView(store: store, dismiss: dismiss)
        case .csvReview:
            CSVReviewStepView(store: store, dismiss: dismiss)
        case .categorizing:
            CategorizingStepView(store: store)
        case .reviewingCategorization:
            // Tela de revisão como step do wizard, com botões "Voltar" e
            // "Importar". `onImport` chama `finalizeImport` que commita
            // atomicamente; `onBack` volta pro preview sem mexer no banco.
            CategorizationReviewView(
                store: store.categorization,
                mode: .wizard(
                    onImport: { await store.finalizeImport() },
                    onBack: { store.backToPreviewFromReview() },
                    onClose: { dismiss() }
                )
            )
        case .confirming:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Importando…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .done:
            // Placeholder pro frame entre a transição de fase e o `dismiss()`
            // disparado no `onChange`. Nunca fica visível na prática.
            Color.clear
        case let .failed(message):
            FailedStepView(
                message: message,
                onRetry: {
                    // Cancel reseta phase pra `.idle` e limpa drafts; reabrir
                    // o picker dá ao usuário a chance de escolher outro
                    // arquivo (ou o mesmo, caso a falha tenha sido transiente).
                    store.cancel()
                    fileImporterShown = true
                },
                onClose: { dismiss() }
            )
        }
    }
}

/// Tela final pra erros que param o wizard. Dá ao usuário escolha explícita
/// de recomeçar (volta pro `.idle` e reabre o picker) ou fechar. Substitui
/// auto-dismiss + toast: quando o `.failed` vem depois da revisão, perder o
/// wizard sem mais nada é confuso.
private struct FailedStepView: View {
    let message: String
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        EmptyStateView("A importação falhou", icon: .warning, description: message) {
            HStack(spacing: 12) {
                Button("Fechar") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Recomeçar") { onRetry() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
