import Foundation

/// Um movimento financeiro: gasto, receita ou transferência.
///
/// **Por que `Decimal` em vez de `Double` para valor monetário:**
/// `Double` é IEEE-754 binário — `0.1 + 0.2 == 0.30000000000000004`. Em
/// finanças isso vira erro acumulado em totalizações. `Decimal` representa
/// números em base 10 (até 38 dígitos) e é exato para as quatro operações
/// quando os operandos cabem na precisão. No SQLite armazenamos como
/// **inteiro de centavos** (ver `Converters`) porque PowerSync só oferece
/// `text`/`integer`/`real` e `real` (Double) perderia a precisão de novo.
struct Transaction: Identifiable, Codable, Hashable {
    let id: UUID
    var accountId: UUID
    var categoryId: UUID
    var subcategoryId: UUID?
    var amount: Decimal
    var occurredAt: Date
    var description: String
    var notes: String?
    // Fase 3: NULL para entradas manuais; preenchido pelo commit de import.
    var importBatchId: UUID?
    /// ID externo (ex: FITID do OFX). Permite detecção exata de duplicata em
    /// re-imports do mesmo extrato — chave única do banco emissor por conta.
    /// NULL pra entradas manuais ou imports CSV/XLSX.
    var externalId: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        accountId: UUID,
        categoryId: UUID,
        subcategoryId: UUID? = nil,
        amount: Decimal,
        occurredAt: Date,
        description: String,
        notes: String? = nil,
        importBatchId: UUID? = nil,
        externalId: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.accountId = accountId
        self.categoryId = categoryId
        self.subcategoryId = subcategoryId
        self.amount = amount
        self.occurredAt = occurredAt
        self.description = description
        self.notes = notes
        self.importBatchId = importBatchId
        self.externalId = externalId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
