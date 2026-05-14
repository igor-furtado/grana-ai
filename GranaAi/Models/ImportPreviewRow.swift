import Foundation

/// Linha parseada de uma planilha durante o **preview** da importação.
/// Estrutura efêmera — não persiste no banco. O `ImportStore` materializa
/// uma `[ImportPreviewRow]` a partir do `[[String]]` cru + `ColumnMapping`,
/// e depois converte as `valid`/`duplicate` confirmadas em `Transaction` no
/// `confirmImport`.
struct ImportPreviewRow: Identifiable, Hashable, Sendable {
    let id = UUID()
    /// Índice 0-based da linha na planilha original (já considerando
    /// `headerRowsToSkip`). Útil pra mostrar "linha N inválida".
    let rowIndex: Int
    let rawCells: [String]
    var status: PreviewStatus
    /// `nil` quando o parsing falhou (`invalidDate`/`invalidAmount`). Quando
    /// status é `valid` ou `duplicate`, esse é o pré-Transaction (sem ID ainda
    /// — o ID é gerado no `confirmImport`).
    var derived: DerivedTransaction?
}

enum PreviewStatus: Hashable, Sendable {
    case valid
    case duplicate(matching: [UUID])     // IDs das transactions existentes que bateram
    case invalidDate(raw: String)
    case invalidAmount(raw: String)
    case missingFields
}

/// Resultado do parsing de uma linha quando ela é válida o suficiente pra
/// virar uma Transaction. Não tem `id`, `accountId`, `categoryId` nem
/// `importBatchId` ainda — esses entram no `confirmImport`, quando o store
/// já sabe a conta destino + categoria "Não Classificado" + o batch novo.
struct DerivedTransaction: Hashable, Sendable {
    var occurredAt: Date
    var amount: Decimal
    var description: String
    var notes: String?
}
