import Foundation

/// Container de serviços globais injetado via SwiftUI Environment.
///
/// Por que `@Observable` em vez de `ObservableObject`:
/// - `@Observable` é a macro do Swift 5.9 que substitui o protocolo legado.
/// - Não precisa marcar propriedades com `@Published`: a macro gera o tracking
///   por propriedade, então a UI re-renderiza só quando *o campo lido* muda.
/// - Em SwiftUI moderno (macOS 14+), Views observam classes `@Observable`
///   automaticamente quando elas vêm do Environment ou de `@State`.
///
/// Por que injeção via Environment em vez de singleton:
/// - Testabilidade: podemos passar um environment "fake" em previews/testes.
/// - Escopo explícito: dependências sobem pela árvore de Views, sem estado
///   global escondido.
@Observable
final class AppEnvironment {
    let container: AppContainer
    /// Quando o setup do banco falha, mantemos o app vivo pra mostrar diagnóstico.
    let setupError: Error?

    init() {
        self.container = AppContainer.setup()
        self.setupError = nil
    }

    private init(container: AppContainer?, error: Error?) {
        // Construtor de fallback. `setup()` hoje não lança (PowerSyncDatabase
        // é factory síncrona não-throwing), mas mantemos o caminho pronto pra
        // Fase 5, quando `connect(connector:)` vai entrar e poderá falhar.
        self.container = container ?? AppContainer.placeholder()
        self.setupError = error
    }

    static func failed(error: Error) -> AppEnvironment {
        AppEnvironment(container: nil, error: error)
    }
}
