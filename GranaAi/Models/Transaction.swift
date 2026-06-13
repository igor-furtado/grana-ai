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
    /// Fase 3: NULL para entradas manuais; preenchido pelo commit de import.
    var importBatchId: UUID?
    /// ID externo (ex: FITID do OFX). Permite detecção exata de duplicata em
    /// re-imports do mesmo extrato — chave única do banco emissor por conta.
    /// NULL pra entradas manuais ou imports CSV/XLSX.
    var externalId: String?
    /// Conta de destino quando a transação é uma transferência entre contas
    /// próprias do usuário (categoria com `kind = transfer`). Saldo subtrai da
    /// `accountId` e soma na `destinationAccountId`. Sem destino → transferência
    /// fica neutra de saldo (ex: importações antigas). Não é exposto pela IA;
    /// usuário preenche manualmente ao categorizar como Transferência.
    var destinationAccountId: UUID?
    /// Fase 4.7: vínculo "esta compra entrou nesta fatura". Só preenchido
    /// quando `accountId` aponta pra conta-cartão — invariante validada no
    /// `TransactionRepository.insert/update` (PowerSync não tem NOT NULL).
    /// O resolver de janela cria/encontra a Statement lazy no insert.
    /// **Distinto de `StatementPayment`**: aqui é compra→fatura; lá é
    /// transferência→fatura paga.
    var statementId: UUID?
    /// Compra original revertida por este lançamento. Quando preenchido,
    /// esta transação é um estorno de cartão: mantém magnitude positiva,
    /// herda conta/categoria da compra e reduz a fatura do próprio ciclo.
    var refundOfTransactionId: UUID?
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
        destinationAccountId: UUID? = nil,
        statementId: UUID? = nil,
        refundOfTransactionId: UUID? = nil,
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
        self.destinationAccountId = destinationAccountId
        self.statementId = statementId
        self.refundOfTransactionId = refundOfTransactionId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
