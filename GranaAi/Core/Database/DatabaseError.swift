import Foundation

enum DatabaseError: LocalizedError {
    case setupFailed(Error)
    case notInitialized
    case invalidUUID(column: String, value: String)
    case invalidDate(column: String, value: String)
    case invalidEnum(column: String, value: String)

    var errorDescription: String? {
        switch self {
        case .setupFailed(let underlying):
            return "Falha ao inicializar o banco de dados: \(underlying.localizedDescription)"
        case .notInitialized:
            return "Banco de dados não inicializado. Reinicie o aplicativo."
        case .invalidUUID(let column, let value):
            return "UUID inválido na coluna \(column): \(value)"
        case .invalidDate(let column, let value):
            return "Data inválida na coluna \(column): \(value)"
        case .invalidEnum(let column, let value):
            return "Valor de enum inválido na coluna \(column): \(value)"
        }
    }
}
