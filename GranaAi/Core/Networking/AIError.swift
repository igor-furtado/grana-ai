import Foundation

/// Erros tipados do shell-out pro `claude` CLI e do pipeline de categorização.
/// Mensagens em PT-BR pra subir direto pra UI quando necessário.
enum AIError: LocalizedError {
    /// Não achou o executável `claude` em nenhum caminho conhecido nem no
    /// `Config.claudeCLIPath`.
    case cliNotFound(searchedPaths: [String])
    /// O processo terminou com exit code ≠ 0. Carrega stderr (truncado) pra
    /// diagnóstico — não é mostrado direto pro usuário.
    case cliExitCode(Int, stderr: String)
    /// Timeout estourou antes do CLI responder.
    case cliTimeout(seconds: TimeInterval)
    /// Stdout do CLI veio mas não bateu com o formato esperado (wrapper
    /// `{"result":"..."}` ou JSON interno do schema).
    case responseParse(String)
    case decoding(Error)
    case unknownCategorySlug(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "CLI do Claude Code não encontrado. Instale com `npm i -g @anthropic-ai/claude-code` ou configure `Config.claudeCLIPath`."
        case let .cliExitCode(code, _):
            return "Claude CLI terminou com erro (exit \(code))."
        case let .cliTimeout(seconds):
            return "Claude CLI não respondeu em \(Int(seconds))s."
        case .responseParse:
            return "Resposta do Claude CLI veio em formato inesperado."
        case .decoding:
            return "Não foi possível interpretar a resposta do Claude CLI."
        case let .unknownCategorySlug(slug):
            return "A IA sugeriu uma categoria desconhecida (\(slug))."
        case .cancelled:
            return "Operação cancelada."
        }
    }
}

/// Erros do pipeline de categorização — separados do `AIError` porque
/// modelam falhas de aplicação (não de transporte/IA).
enum CategorizationError: LocalizedError {
    case noTransactionsToClassify
    case categoryNotFound(slug: String)
    case persistFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noTransactionsToClassify:
            return "Nenhuma transação pendente de categorização."
        case let .categoryNotFound(slug):
            return "Categoria com slug '\(slug)' não encontrada no banco — seed corrompido?"
        case let .persistFailed(underlying):
            return "Falha ao persistir categorizações: \(underlying.localizedDescription)"
        }
    }
}
