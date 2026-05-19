import Foundation
import Observation
import OSLog

/// Coletor global de erros. **Todo `catch` do app deve passar por aqui** —
/// é o único ponto que decide o que vai pra UI (toast) e o que vai pro log.
///
/// Por que singleton (`shared`) e não Environment-only: catches acontecem em
/// repositories, services e tasks soltas que não têm acesso ao `@Environment`.
/// Manter um ponto fixo evita injeção em cascata só pra reportar erro.
/// A UI continua observando via `@Bindable` quando precisa.
///
/// `CancellationError` é **silenciosamente ignorado** — cancelamento de Task
/// é comportamento esperado da SwiftUI (View saiu de cena) e não é falha.
@MainActor
@Observable
final class ErrorCenter {
    static let shared = ErrorCenter()

    /// Item ativo na pilha de toasts. Identificável pra `ForEach` + animação.
    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let message: String
        let createdAt = Date()
    }

    private(set) var notices: [Notice] = []

    /// Tasks de auto-dismiss por notice — cancelar ao dispensar manualmente
    /// evita race: usuário fecha → 5s depois o timer dispararia removendo
    /// quem já não existe (e a animação ficaria estranha se outro toast
    /// tivesse herdado o slot).
    private var autoDismissTasks: [UUID: Task<Void, Never>] = [:]

    /// Tempo que um toast fica visível antes de sumir sozinho. Erros
    /// raramente exigem ação imediata; o usuário pode reagir lendo e o toast
    /// some — se quiser revisitar, o log do Console.app guarda tudo.
    private let autoDismissAfter: Duration = .seconds(6)

    private init() {}

    // MARK: - Entrada

    /// API principal. Aceita qualquer `Error`. Filtra cancelamentos e
    /// duplicatas consecutivas (mesma mensagem em menos de 1s = um único
    /// toast — evita spam quando um stream falha em loop).
    func report(_ error: Error, title overrideTitle: String? = nil) {
        if error is CancellationError { return }

        let presentation = AppErrorPresentation.from(error, overrideTitle: overrideTitle)
        append(title: presentation.title, message: presentation.message, underlying: error)
    }

    /// Reporta um erro ad-hoc sem precisar criar um tipo. Útil pra validações
    /// de UI ("Selecione uma conta antes de continuar").
    func report(title: String, message: String) {
        append(title: title, message: message, underlying: nil)
    }

    /// Dispensa um toast (botão X ou auto-dismiss).
    func dismiss(_ id: UUID) {
        notices.removeAll { $0.id == id }
        autoDismissTasks[id]?.cancel()
        autoDismissTasks[id] = nil
    }

    /// Limpa tudo. Usado em previews/testes; produção raramente precisa.
    func dismissAll() {
        for task in autoDismissTasks.values { task.cancel() }
        autoDismissTasks.removeAll()
        notices.removeAll()
    }

    // MARK: - Interno

    private func append(title: String, message: String, underlying: Error?) {
        // Dedup: ignora se já existe um toast com mesmo título+mensagem em
        // janela <1s — não só o último, porque erros intercalados (A, B, A, B)
        // de fontes diferentes deduplicavam mal se comparássemos só
        // `notices.last`. Stream com erro recorrente dispararia 10 toasts iguais.
        let now = Date()
        if notices.contains(where: {
            $0.title == title
                && $0.message == message
                && now.timeIntervalSince($0.createdAt) < 1.0
        }) {
            return
        }

        let notice = Notice(title: title, message: message)
        notices.append(notice)

        if let underlying {
            log.ui.error("ErrorCenter: \(title, privacy: .public) — \(String(describing: underlying), privacy: .public)")
        } else {
            log.ui.error("ErrorCenter: \(title, privacy: .public) — \(message, privacy: .public)")
        }

        scheduleAutoDismiss(for: notice.id)
    }

    private func scheduleAutoDismiss(for id: UUID) {
        autoDismissTasks[id]?.cancel()
        autoDismissTasks[id] = Task { [weak self, autoDismissAfter] in
            try? await Task.sleep(for: autoDismissAfter)
            guard !Task.isCancelled else { return }
            self?.dismiss(id)
        }
    }
}

// MARK: - Helpers

extension ErrorCenter {
    /// Atalho pra reportar de contextos não-MainActor sem boilerplate de
    /// `Task { @MainActor in ... }`. Útil em closures de URLSession,
    /// callbacks de SDK, etc.
    nonisolated static func capture(_ error: Error, title: String? = nil) {
        Task { @MainActor in
            ErrorCenter.shared.report(error, title: title)
        }
    }
}

/// Envolve um bloco assíncrono e captura qualquer erro lançado no
/// `ErrorCenter`. Substitui o pattern repetido `do { try ... } catch { ... }`.
///
/// Uso: `await reportingErrors { try await store.refresh() }`
@discardableResult
@MainActor
func reportingErrors<T>(
    title: String? = nil,
    _ operation: () async throws -> T
) async -> T? {
    do {
        return try await operation()
    } catch is CancellationError {
        return nil
    } catch {
        ErrorCenter.shared.report(error, title: title)
        return nil
    }
}
