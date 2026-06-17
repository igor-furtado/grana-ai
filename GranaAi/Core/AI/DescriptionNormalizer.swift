import CryptoKit
import Foundation

/// Normaliza descrições de transações pra dois usos:
///
/// 1. **Chave de cache** — descrições com pequenas diferenças (case, espaço
///    duplo, acento) devem cair no mesmo cache hit. Caso contrário a IA é
///    chamada várias vezes pro mesmo lançamento recorrente (ex: "iFood",
///    "IFOOD", "iFood ").
/// 2. **Contexto da IA** — texto normalizado reduz ruído no prompt.
///
/// **Estratégia:**
/// - Folding diacrítico + lowercase (Locale-aware pra português).
/// - Trim e colapso de whitespace.
/// - **Remove sequências contíguas de ≥ 4 dígitos** — pega FITID, CPF
///   parcial, referências bancárias longas (`ref 20240315`, `doc 998877`).
///   Mantém runs curtos (data `dia 5`, parcela `1/3`, `12/24`) porque ajudam
///   o modelo a distinguir contextos. `12/24` é preservado porque a barra
///   quebra o run — cada lado tem só 2 dígitos.
///
/// **`nonisolated`:** chamado tanto da MainActor (Stores) quanto do service
/// rodando off-main (Tasks detached). Funções puras → sem custo.
nonisolated enum DescriptionNormalizer {
    static func normalize(_ raw: String) -> String {
        let folded = raw.folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
            .lowercased()

        let withoutLongDigits = removeLongDigitRuns(folded)

        let collapsed = withoutLongDigits
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// SHA256 hex da descrição normalizada. Chave do `categorization_cache`.
    static func hash(_ raw: String) -> String {
        let normalized = normalize(raw)
        return sha256Hex(normalized)
    }

    /// SHA256 hex direto de uma string já normalizada (evita re-normalizar).
    static func hashNormalized(_ normalized: String) -> String {
        sha256Hex(normalized)
    }

    private static func sha256Hex(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Remove runs de 4+ dígitos. Mantém runs curtos.
    private static func removeLongDigitRuns(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)

        var digitRun = ""

        func flushDigitRun() {
            if digitRun.count < 4 {
                result.append(digitRun)
            }
            digitRun.removeAll(keepingCapacity: true)
        }

        for ch in s {
            if ch.isASCII && ch.isNumber {
                digitRun.append(ch)
            } else {
                flushDigitRun()
                result.append(ch)
            }
        }
        flushDigitRun()
        return result
    }
}
