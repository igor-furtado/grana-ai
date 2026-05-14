import Foundation

/// Abstrai a leitura de uma planilha como matriz crua `[[String]]`. O parser
/// (`ImportParser`) recebe essa matriz já normalizada — não sabe se ela veio
/// de XLSX ou CSV. Isso isola o resto do pipeline das particularidades de
/// cada formato.
protocol SpreadsheetReader {
    /// Lê a primeira sheet/aba do arquivo e devolve linhas × células.
    /// Linhas vazias **continuam** no array (sem dropar) — o parser decide o
    /// que fazer com elas, pra não perder o alinhamento com o número de linha
    /// original mostrado no preview.
    func readRows(from url: URL) throws -> [[String]]
}

/// Dispatcher por extensão. OFX **não** vem por aqui — ele tem fluxo próprio
/// (não cabe no contrato `[[String]]`), então o `ImportStore` ramifica por
/// `ImportSourceKind` antes de chamar qualquer reader.
enum SpreadsheetReaderFactory {
    static func reader(for url: URL) throws -> SpreadsheetReader {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "xlsx": return XLSXReader()
        case "csv":  return CSVReader()
        default:     throw ImportError.unsupportedFormat(extension: ext)
        }
    }

    static func sourceKind(for url: URL) throws -> ImportSourceKind {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "xlsx": return .xlsx
        case "csv":  return .csv
        case "ofx":  return .ofx
        default:     throw ImportError.unsupportedFormat(extension: ext)
        }
    }
}
