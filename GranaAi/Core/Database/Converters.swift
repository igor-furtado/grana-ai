import Foundation

/// Conversores usados pelos mappers de repository.
///
/// **`nonisolated` no enum:** o target tem `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, então tipos sem anotação ficam MainActor-isolated por padrão.
/// Os conversores são chamados de mappers `@Sendable` (rodam off-main no
/// PowerSync) e de closures de `writeTransaction` — precisam ser nonisolated
/// pra serem chamáveis de qualquer contexto.
///
/// **Por que armazenamos dinheiro como Int64 de centavos:**
/// PowerSync expõe apenas três tipos de coluna no schema (`text`, `integer`,
/// `real`). `real` é Double — perde precisão em operações decimais (clássico
/// `0.1 + 0.2 != 0.3`). `integer` é exato. Multiplicamos o `Decimal` por 100
/// e arredondamos pra fora os centavos, persistimos como Int64, e na leitura
/// dividimos de volta. Toda a aritmética monetária em runtime continua em
/// `Decimal` — o `Int64` só vive no banco.
nonisolated enum Converters {
    /// Decimal real → Int64 de centavos. Arredonda half-up (.plain) na 2ª casa.
    static func decimalToCents(_ value: Decimal) -> Int64 {
        var multiplied = value * 100
        var rounded = Decimal()
        // `.plain` é o "arredondamento bancário" tradicional: half away from zero.
        NSDecimalRound(&rounded, &multiplied, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    /// Int64 de centavos → Decimal real (dividido por 100).
    static func centsToDecimal(_ cents: Int64) -> Decimal {
        Decimal(cents) / 100
    }

    /// ISO8601 com frações de segundo. `ISO8601DateFormatter` é thread-safe
    /// desde macOS 10.12 (diferente de `DateFormatter`), então usar como
    /// singleton é seguro e mais barato que criar a cada chamada.
    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func dateToString(_ date: Date) -> String {
        iso8601.string(from: date)
    }

    static func stringToDate(_ string: String) -> Date? {
        iso8601.date(from: string)
    }
}
