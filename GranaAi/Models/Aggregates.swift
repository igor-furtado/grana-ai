import Foundation

/// Total acumulado em uma categoria raiz no período filtrado.
///
/// Resultado direto de um SQL `SUM(amount_cents) ... GROUP BY category_id` com
/// JOIN em `categories` — por isso o struct já carrega `categoryName` e `icon`
/// resolvidos, evitando segunda viagem ao banco pra cada item do donut.
struct CategoryTotal: Identifiable, Hashable {
    let categoryId: UUID
    let categoryName: String
    let icon: CategoryIcon?
    let total: Decimal

    var id: UUID {
        categoryId
    }
}

/// Total acumulado em um dia da semana ao longo do período filtrado.
/// Usado pelo gráfico "gastos por dia da semana" — pra responder "tem
/// algum dia da semana em que eu gasto mais sistematicamente?".
///
/// `weekday` segue a convenção do `Calendar`: 1 = domingo, 2 = segunda,
/// ..., 7 = sábado. A View reordena pra Seg→Dom na exibição.
struct WeekdayTotal: Identifiable, Hashable {
    let weekday: Int
    let total: Decimal
    /// Quantas transações caíram nesse dia da semana no período. Útil pra
    /// distinguir "soma alta porque um único dia foi outlier" de "soma alta
    /// porque sistematicamente gasto nesse dia".
    let count: Int

    var id: Int {
        weekday
    }
}

/// Total de uma categoria raiz em um mês específico. Usado pelo gráfico de
/// barras empilhadas mês a mês (cada barra é um mês, cada segmento uma
/// categoria). `monthStart` é o primeiro dia do mês 00:00:00 local.
struct MonthlyCategoryTotal: Identifiable, Hashable {
    let monthStart: Date
    let categoryId: UUID
    let categoryName: String
    let icon: CategoryIcon?
    let total: Decimal

    /// Composto porque (mês × categoria) é o que identifica unicamente um
    /// segmento — só `categoryId` se repetiria entre meses.
    var id: String {
        "\(monthStart.timeIntervalSince1970)-\(categoryId.uuidString)"
    }
}

/// Totais de receita e despesa de um mês. Usado pelo gráfico "receita vs.
/// despesa" — uma única linha já carrega as duas barras lado a lado.
struct MonthlyKindTotal: Identifiable, Hashable {
    let monthStart: Date
    let income: Decimal
    let expense: Decimal

    var id: Date {
        monthStart
    }

    /// Diferença (positiva = sobrou; negativa = estourou). Útil pra anotação.
    var net: Decimal {
        income - expense
    }
}
