import Foundation

/// Erros tipados do transporte remoto e do pipeline de categorização.
/// Mensagens em PT-BR pra subir direto pra UI quando necessário.
enum AIError: LocalizedError {
    case invalidConfiguration(String)
    case requestFailed(Error)
    case invalidResponse(String)
    case httpStatus(Int, body: String?)
    case responseParse(String)
    case decoding(Error)
    case unknownCategorySlug(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(key):
            return "Configuração ausente ou inválida para \(key)."
        case .requestFailed:
            return "Não foi possível falar com o serviço de categorização."
        case let .invalidResponse(message):
            return "O serviço de categorização respondeu em formato inválido: \(message)"
        case let .httpStatus(code, _):
            return "O serviço de categorização respondeu com HTTP \(code)."
        case .responseParse:
            return "Resposta do serviço de categorização veio em formato inesperado."
        case .decoding:
            return "Não foi possível interpretar a resposta do serviço de categorização."
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
