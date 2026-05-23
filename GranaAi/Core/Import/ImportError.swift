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
    /// Usuário tentou avançar sem escolher conta de destino pro statement OFX
    /// ou pra fatura CSV.
    case accountNotSelected
    /// Tentou importar fatura de cartão sem ter nenhuma conta-cartão cadastrada.
    case noCreditCardAccount

    var errorDescription: String? {
        switch self {
        case let .fileUnreadable(url):
            return "Não foi possível ler o arquivo: \(url.lastPathComponent)"
        case let .unsupportedFormat(ext):
            return "Formato não suportado: .\(ext). Use XLSX ou CSV."
        case .emptySheet:
            return "A planilha está vazia."
        case .mappingIncomplete:
            return "Mapeamento incompleto: defina pelo menos as colunas de data, descrição e valor (ou débito/crédito)."
        case let .dateParseFailed(row, raw):
            return "Linha \(row): data inválida (\"\(raw)\"). Verifique o formato definido no mapeamento."
        case let .amountParseFailed(row, raw):
            return "Linha \(row): valor inválido (\"\(raw)\")."
        case .noValidRows:
            return "Nenhuma linha válida encontrada para importar."
        case let .batchInsertFailed(underlying):
            return "Falha ao gravar o lote no banco: \(underlying.localizedDescription)"
        case .unclassifiedCategoryMissing:
            return "Categoria \"Não Classificado\" não encontrada. Verifique o seed inicial."
        case .templateInvalidJSON:
            return "Template salvo está corrompido (JSON inválido)."
        case let .csvHeaderMismatch(expected, got):
            return "Cabeçalho do CSV não bate. Esperado: \(expected.joined(separator: ", ")). Encontrado: \(got.joined(separator: ", "))."
        case let .csvRowFieldCount(row, expected, got):
            return "Linha \(row): número de campos inesperado (esperava \(expected), encontrou \(got))."
        case .accountNotSelected:
            return "Selecione a conta de destino antes de avançar."
        case .noCreditCardAccount:
            return "Cadastre uma conta do tipo \"Cartão de Crédito\" em Configurações > Contas antes de importar uma fatura."
        }
    }
}
