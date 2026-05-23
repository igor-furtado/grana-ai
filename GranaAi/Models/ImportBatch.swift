import Foundation

/// Uma execução de importação OFX. Existe pra dois motivos: rastrear *de onde*
/// veio cada transaction (`Transaction.importBatchId`) e permitir desfazer um
/// import inteiro como unidade (DELETE em cascata).
struct ImportBatch: Identifiable, Codable, Hashable {
    let id: UUID
    var sourceFilename: String
    var accountId: UUID
    var rowCount: Int
    var importedAt: Date
    let createdAt: Date
    var updatedAt: Date
}
