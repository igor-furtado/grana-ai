import Charts
import SwiftUI

/// Gastos somados por dia da semana no período filtrado. Objetivo: identificar
/// padrão semanal — "tem sexta que gasto mais?", "domingo é dia de descansar
/// a carteira?".
///
/// Mostra **sempre os 7 dias** (preenche buckets vazios com 0) pra comparação
/// visual ser justa. Cada barra exibe a soma; o label do eixo X traz "Seg /
/// 4×" — a contagem ajuda a separar "soma alta de gasto sistemático" de
/// "soma alta porque teve um único dia caro".
struct WeekdayExpensesChart: View {
    let totals: [WeekdayTotal]

    /// Ordem de exibição: Seg → Dom (idiomática BR). Calendar usa 1=Dom,
    /// 2=Seg, ..., 7=Sáb — então pegamos [2,3,4,5,6,7,1].
    private static let weekdayOrder: [Int] = [2, 3, 4, 5, 6, 7, 1]

    private static let shortName: [Int: String] = [
        1: "Dom", 2: "Seg", 3: "Ter", 4: "Qua",
        5: "Qui", 6: "Sex", 7: "Sáb",
    ]

    /// Preenche dias sem transação com 0 e ordena Seg→Dom. O preenchimento
    /// fica na View (não no Store) pra manter a fonte SQL fiel à realidade —
    /// "sem rows" e "rows com 0" são coisas diferentes pro repository.
    private var displayed: [WeekdayTotal] {
        let dict = Dictionary(uniqueKeysWithValues: totals.map { ($0.weekday, $0) })
        return Self.weekdayOrder.map { wd in
            dict[wd] ?? WeekdayTotal(weekday: wd, total: 0, count: 0)
        }
    }

    var body: some View {
        if totals.isEmpty {
            ContentUnavailableView(
                "Sem gastos no período",
                systemImage: AppIcon.calendar.systemImage,
                description: Text("Adicione transações pra ver o padrão semanal.")
            )
            .frame(maxWidth: .infinity)
        } else {
            Chart(displayed) { item in
                BarMark(
                    x: .value("Dia", label(for: item)),
                    y: .value("Total", plottable(item.total))
                )
                .foregroundStyle(Color.expense.gradient)
                .cornerRadius(4)
            }
            // Domain explícito força a ordem Seg→Dom no eixo X. Sem isso,
            // Swift Charts ordena alfabeticamente os labels (Dom, Qua, Qui...).
            .chartXScale(domain: displayed.map { label(for: $0) })
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let cents = value.as(Double.self) {
                            Text(cents.formatted(.currency(code: "BRL").precision(.fractionLength(0))))
                        }
                    }
                }
            }
        }
    }

    private func label(for item: WeekdayTotal) -> String {
        let name = Self.shortName[item.weekday] ?? "?"
        // Anota com a contagem entre parênteses só quando há ocorrências —
        // evita "Dom (0×)" poluindo o eixo em dias zerados.
        return item.count > 0 ? "\(name)\n\(item.count)×" : name
    }

    private func plottable(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

#Preview {
    // Distribuição típica de uso pessoal: gasta mais sexta/sábado, menos
    // segunda/terça.
    let samples: [WeekdayTotal] = [
        WeekdayTotal(weekday: 2, total: 120, count: 4), // Seg
        WeekdayTotal(weekday: 3, total: 90, count: 3), // Ter
        WeekdayTotal(weekday: 4, total: 150, count: 4), // Qua
        WeekdayTotal(weekday: 5, total: 180, count: 4), // Qui
        WeekdayTotal(weekday: 6, total: 420, count: 5), // Sex
        WeekdayTotal(weekday: 7, total: 380, count: 4), // Sáb
        WeekdayTotal(weekday: 1, total: 110, count: 2), // Dom
    ]
    return WeekdayExpensesChart(totals: samples)
        .frame(width: 380, height: 280)
        .padding()
}
