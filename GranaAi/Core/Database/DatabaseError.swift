import Foundation

enum DatabaseError: LocalizedError {
    case setupFailed(Error)
    case notInitialized
    case invalidUUID(column: String, value: String)
    case invalidDate(column: String, value: String)
    case invalidEnum(column: String, value: String)

    var errorDescription: String? {
        switch self {
        case let .setupFailed(underlying):
            return "Falha ao inicializar o banco de dados: \(underlying.localizedDescription)"
        case .notInitialized:
            return "Banco de dados não inicializado. Reinicie o aplicativo."
        case let .invalidUUID(column, value):
            return "UUID inválido na coluna \(column): \(value)"
        case let .invalidDate(column, value):
            return "Data inválida na coluna \(column): \(value)"
        case let .invalidEnum(column, value):
            return "Valor de enum inválido na coluna \(column): \(value)"
        }
    }
}
