import Foundation

/// Uma execução de importação de planilha. Existe pra dois motivos:
/// rastrear *de onde* veio cada transaction (`Transaction.importBatchId`) e
/// permitir desfazer um import inteiro como unidade (DELETE em cascata).
struct ImportBatch: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var sourceFilename: String
    var sourceKind: ImportSourceKind
    /// Template usado nessa importação. NULL quando o usuário mapeou colunas
    /// manualmente sem salvar como template.
    var templateId: UUID?
    var accountId: UUID
    var rowCount: Int
    var importedAt: Date
    let createdAt: Date
    var updatedAt: Date
}

enum ImportSourceKind: String, Codable, CaseIterable, Sendable {
    case xlsx
    case csv
    case ofx

    var displayName: String {
        switch self {
        case .xlsx: "Excel (XLSX)"
        case .csv:  "CSV"
        case .ofx:  "OFX"
        }
    }
}
