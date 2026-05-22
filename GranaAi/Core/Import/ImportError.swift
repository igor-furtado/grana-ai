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
    case csvHeaderMismatch(expected: [String], got: [String])
    case csvRowFieldCount(row: Int, expected: Int, got: Int)
    case creditCardAccountUnnamed
    case creditCardAccountNotSelected

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
        case .csvHeaderMismatch(let expected, let got):
            return "Cabeçalho do CSV não bate. Esperado: \(expected.joined(separator: ", ")). Encontrado: \(got.joined(separator: ", "))."
        case .csvRowFieldCount(let row, let expected, let got):
            return "Linha \(row): número de campos inesperado (esperava \(expected), encontrou \(got))."
        case .creditCardAccountUnnamed:
            return "Defina um nome para a nova conta-cartão antes de avançar."
        case .creditCardAccountNotSelected:
            return "Selecione a conta-cartão de destino antes de avançar."
        }
    }
}
