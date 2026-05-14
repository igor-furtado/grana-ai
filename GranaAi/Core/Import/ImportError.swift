import Foundation

enum ImportError: LocalizedError {
    case fileUnreadable(URL)
    case unsupportedFormat(extension: String)
    case emptySheet
    case mappingIncomplete
    case dateParseFailed(row: Int, raw: String)
    case amountParseFailed(row: Int, raw: String)
    case noValidRows
    case batchInsertFailed(underlying: Error)
    case unclassifiedCategoryMissing
    case templateInvalidJSON

    var errorDescription: String? {
        switch self {
        case .fileUnreadable(let url):
            return "Não foi possível ler o arquivo: \(url.lastPathComponent)"
        case .unsupportedFormat(let ext):
            return "Formato não suportado: .\(ext). Use XLSX ou CSV."
        case .emptySheet:
            return "A planilha está vazia."
        case .mappingIncomplete:
            return "Mapeamento incompleto: defina pelo menos as colunas de data, descrição e valor (ou débito/crédito)."
        case .dateParseFailed(let row, let raw):
            return "Linha \(row): data inválida (\"\(raw)\"). Verifique o formato definido no mapeamento."
        case .amountParseFailed(let row, let raw):
            return "Linha \(row): valor inválido (\"\(raw)\")."
        case .noValidRows:
            return "Nenhuma linha válida encontrada para importar."
        case .batchInsertFailed(let underlying):
            return "Falha ao gravar o lote no banco: \(underlying.localizedDescription)"
        case .unclassifiedCategoryMissing:
            return "Categoria \"Não Classificado\" não encontrada. Verifique o seed inicial."
        case .templateInvalidJSON:
            return "Template salvo está corrompido (JSON inválido)."
        }
    }
}
