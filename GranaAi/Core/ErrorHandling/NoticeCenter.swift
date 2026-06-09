import Foundation
import Observation
import OSLog

/// Coletor global de notificações in-app — toasts no canto superior-direito
/// da janela. Cobre erros (`report`), confirmações (`success`) e avisos
/// neutros (`info`), todos com suporte a botões de ação inline (ex: "Desfazer"
/// após um import).
///
/// **Por que centralizar:** padrão único de feedback in-app. Sem isso, cada
/// feature reinventa toast/banner/alert do seu jeito e o usuário acaba vendo
/// linguagens visuais diferentes pra coisas equivalentes.
///
/// **Por que singleton (`shared`):** posts acontecem em repositories,
/// services e tasks soltas que não têm acesso ao `@Environment`. Manter um
/// ponto fixo evita injeção em cascata só pra notificar.
///
/// **`CancellationError` é silenciosamente ignorado** — cancelamento de
/// Task é comportamento esperado da SwiftUI (View saiu de cena), não é
/// falha que mereça toast.
@MainActor
@Observable
final class NoticeCenter {
    static let shared = NoticeCenter()

    // MARK: - Tipos

    /// Categoria visual + semântica de uma notice. Determina cor, ícone e
    /// timeout default.
    enum Kind: Equatable {
        case error
        case success
        case info
    }

    /// Papel visual de um botão de ação na notice. `default` é a ação
    /// principal (azul); `destructive` é vermelho — usado pra "Desfazer",
    /// "Apagar" etc.
    enum ActionRole: Equatable {
        case `default`
        case destructive
    }

    /// Botão clicável renderizado dentro do card da notice. Tocar dispara
    /// `handler` e descarta a notice (sempre — não há caso de uso pra
    /// "ação que mantém o toast aberto" hoje).
    struct Action: Identifiable {
        let id = UUID()
        let title: String
        let role: ActionRole
        let handler: @MainActor () -> Void

        init(title: String, role: ActionRole = .default, handler: @escaping @MainActor () -> Void) {
            self.title = title
            self.role = role
            self.handler = handler
        }
    }

    /// Item ativo na pilha de toasts. `message` é opcional pra suportar
    /// notices curtas ("Importação concluída") sem corpo secundário.
    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let kind: Kind
        let title: String
        let message: String?
        let createdAt: Date
        let actions: [Action]
        let dismissAfter: Duration

        /// Comparação por identidade. `Action.handler` é closure e não é
        /// Equatable; identidade é suficiente pra animações de `ForEach` e
        /// diffing do `@Observable`.
        static func == (lhs: Notice, rhs: Notice) -> Bool {
            lhs.id == rhs.id
        }
    }

    // MARK: - Estado

    private(set) var notices: [Notice] = []

    /// Tasks de auto-dismiss por notice — cancelar ao dispensar manualmente
    /// evita race: usuário fecha → timer dispararia removendo quem já não
    /// existe (e a animação ficaria estranha se outro toast tivesse herdado
    /// o slot).
    private var autoDismissTasks: [UUID: Task<Void, Never>] = [:]

    private init() {}

    // MARK: - API: Erros

    /// Reporta um `Error`. Filtra `CancellationError` (silencioso) e
    /// duplicatas em janela <1s. Toast vermelho com timeout de 6s.
    func report(_ error: Error, title overrideTitle: String? = nil) {
        if error is CancellationError { return }
        let presentation = AppErrorPresentation.from(error, overrideTitle: overrideTitle)
        post(Notice(
            kind: .error,
            title: presentation.title,
            message: presentation.message,
            createdAt: Date(),
            actions: [],
            dismissAfter: .seconds(6)
        ))
    }

    /// Erro ad-hoc sem tipo definido. Útil pra validações de UI
    /// ("Selecione uma conta antes de continuar").
    func report(title: String, message: String) {
        post(Notice(
            kind: .error,
            title: title,
            message: message,
            createdAt: Date(),
            actions: [],
            dismissAfter: .seconds(6)
        ))
    }

    // MARK: - API: Sucesso

    /// Toast verde de confirmação. Timeout maior (10s) quando há ações pra
    /// dar tempo do usuário ler e decidir; sem ações, 4s — sucessos não
    /// precisam ficar lá tanto tempo quanto erros.
    @discardableResult
    func success(title: String, message: String? = nil, actions: [Action] = []) -> UUID {
        post(Notice(
            kind: .success,
            title: title,
            message: message,
            createdAt: Date(),
            actions: actions,
            dismissAfter: actions.isEmpty ? .seconds(4) : .seconds(10)
        ))
    }

    // MARK: - API: Info

    /// Toast neutro pra avisos não-críticos. Mesma lógica de timeout do
    /// `success`.
    @discardableResult
    func info(title: String, message: String? = nil, actions: [Action] = []) -> UUID {
        post(Notice(
            kind: .info,
            title: title,
            message: message,
            createdAt: Date(),
            actions: actions,
            dismissAfter: actions.isEmpty ? .seconds(5) : .seconds(10)
        ))
    }

    // MARK: - Controle

    /// Dispensa um toast (botão X, ação executada ou auto-dismiss).
    func dismiss(_ id: UUID) {
        notices.removeAll { $0.id == id }
        autoDismissTasks[id]?.cancel()
        autoDismissTasks[id] = nil
    }

    /// Limpa tudo. Usado em previews/testes; produção raramente precisa.
    func dismissAll() {
        for task in autoDismissTasks.values {
            task.cancel()
        }
        autoDismissTasks.removeAll()
        notices.removeAll()
    }

    // MARK: - Interno

    @discardableResult
    private func post(_ notice: Notice) -> UUID {
        // Dedup: ignora se já existe notice com mesma identidade textual em
        // janela <1s. Notices com `actions` NÃO deduplicam — se um fluxo
        // dispara duas ações de undo na sequência, o usuário precisa de
        // dois botões pra desfazer cada uma.
        if notice.actions.isEmpty {
            let now = Date()
            if let existing = notices.first(where: {
                $0.kind == notice.kind
                    && $0.title == notice.title
                    && $0.message == notice.message
                    && now.timeIntervalSince($0.createdAt) < 1.0
            }) {
                // Devolve o id da notice que já está na fila — o id da nova
                // (que vai pro lixo) levaria callers a chamar `dismiss(id)`
                // num UUID que nunca existiu na fila.
                return existing.id
            }
        }

        notices.append(notice)
        logNotice(notice)
        scheduleAutoDismiss(for: notice.id, after: notice.dismissAfter)
        return notice.id
    }

    private func logNotice(_ notice: Notice) {
        // Body fica `.private`: mensagens de erro podem incluir nomes de
        // conta/contraparte vindas do OFX. Título é genérico ("Erro no
        // banco", "Importação concluída") e fica `.public` pra agrupar no
        // Console.
        let body = notice.message ?? ""
        switch notice.kind {
        case .error:
            log.ui.error("Notice[error]: \(notice.title, privacy: .public) — \(body, privacy: .private)")
        case .success:
            log.ui.info("Notice[success]: \(notice.title, privacy: .public) — \(body, privacy: .private)")
        case .info:
            log.ui.info("Notice[info]: \(notice.title, privacy: .public) — \(body, privacy: .private)")
        }
    }

    private func scheduleAutoDismiss(for id: UUID, after duration: Duration) {
        autoDismissTasks[id]?.cancel()
        autoDismissTasks[id] = Task { [weak self, duration] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismiss(id)
        }
    }
}

// MARK: - Helpers

extension NoticeCenter {
    /// Atalho pra reportar erro de contextos não-MainActor sem boilerplate
    /// de `Task { @MainActor in ... }`. Útil em closures de URLSession,
    /// callbacks de SDK, etc.
    nonisolated static func capture(_ error: Error, title: String? = nil) {
        Task { @MainActor in
            NoticeCenter.shared.report(error, title: title)
        }
    }
}
