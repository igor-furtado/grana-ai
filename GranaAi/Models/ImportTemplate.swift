import Foundation

/// Mapeamento de colunas salvo para reuso entre importações do mesmo banco.
/// O `mapping` é serializado como JSON na coluna `mapping_json` — manter como
/// JSON em vez de N colunas evita migration toda vez que o formato de
/// mapeamento evoluir.
struct ImportTemplate: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var sourceKind: ImportSourceKind
    var mapping: ColumnMapping
    /// Formato esperado da coluna de data, no DSL do `DateFormatter` (ex:
    /// `dd/MM/yyyy`). Templates diferentes podem precisar de formatos diferentes
    /// (Itaú costuma vir `dd/MM/yyyy`, planilhas exportadas como ISO vêm
    /// `yyyy-MM-dd`).
    var dateFormat: String
    /// Separador decimal da coluna de valor: "," (BR) ou "." (US/ISO).
    var decimalSeparator: String
    var defaultAccountId: UUID?
    let createdAt: Date
    var updatedAt: Date
}

/// Mapeia campos da `Transaction` para índices de coluna da planilha. Quando
/// a planilha traz duas colunas separadas para débito/crédito (padrão Itaú,
/// Bradesco, Inter), preencher `debit`/`credit` em vez de `amount`. O parser
/// reconcilia: débito → negativo, crédito → positivo.
struct ColumnMapping: Codable, Hashable, Sendable {
    var date: Int?
    var description: Int?
    /// "Valor unificado" — usa quando a planilha tem UMA coluna com sinal.
    /// Mutuamente exclusivo com (`debit`, `credit`).
    var amount: Int?
    var debit: Int?
    var credit: Int?
    var notes: Int?

    /// Linhas iniciais a pular (cabeçalho do banco + linhas decorativas).
    /// Default 1 cobre o caso mais comum (uma linha de header).
    var headerRowsToSkip: Int

    init(
        date: Int? = nil,
        description: Int? = nil,
        amount: Int? = nil,
        debit: Int? = nil,
        credit: Int? = nil,
        notes: Int? = nil,
        headerRowsToSkip: Int = 1
    ) {
        self.date = date
        self.description = description
        self.amount = amount
        self.debit = debit
        self.credit = credit
        self.notes = notes
        self.headerRowsToSkip = headerRowsToSkip
    }

    /// Mapeamento mínimo viável: precisa de data, descrição e (valor unificado
    /// OU as duas colunas débito/crédito). Sem isso, parser não tem como gerar
    /// uma Transaction válida.
    var isComplete: Bool {
        guard date != nil, description != nil else { return false }
        if amount != nil { return true }
        return debit != nil && credit != nil
    }
}
