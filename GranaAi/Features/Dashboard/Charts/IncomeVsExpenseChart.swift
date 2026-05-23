import Charts
import SwiftUI

/// Modos de exibição do gráfico de receita vs. despesa. Controla quais
/// séries entram no plot — a View do dashboard expõe via `Picker` no
/// header do card.
enum IncomeVsExpenseMode: String, CaseIterable, Identifiable {
    case both, income, expense

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .both: "Ambos"
        case .income: "Receitas"
        case .expense: "Despesas"
        }
    }
}

/// Barras de receita e/ou despesa por mês.
///
/// Quando `mode == .both`, duas barras lado a lado por mês via
/// `position(by:)` — Swift Charts agrupa automaticamente. Em `.income` ou
/// `.expense` sobra uma série só, e as barras ocupam o slot inteiro do mês.
struct IncomeVsExpenseChart: View {
    let totals: [MonthlyKindTotal]
    var mode: IncomeVsExpenseMode = .both

    private struct Point: Hashable {
        let month: Date
        let label: String // "Receita" | "Despesa"
        let value: Decimal
    }

    private var points: [Point] {
        totals.flatMap { item -> [Point] in
            var pts: [Point] = []
            if mode != .expense {
                pts.append(Point(month: item.monthStart, label: "Receita", value: item.income))
            }
            if mode != .income {
                pts.append(Point(month: item.monthStart, label: "Despesa", value: item.expense))
            }
            return pts
        }
    }

    var body: some View {
        if totals.isEmpty {
            ContentUnavailableView(
                "Sem dados de receita/despesa",
                systemImage: AppIcon.chart.systemImage,
                description: Text("Adicione transações pra comparar entradas e saídas mês a mês.")
            )
            .frame(maxWidth: .infinity)
        } else {
            Chart(points, id: \.self) { point in
                BarMark(
                    x: .value("Mês", point.month, unit: .month),
                    y: .value("Total", plottable(point.value))
                )
                .position(by: .value("Tipo", point.label))
                .foregroundStyle(by: .value("Tipo", point.label))
                .cornerRadius(2)
            }
            .chartForegroundStyleScale([
                "Receita": Color.income,
                "Despesa": Color.expense,
            ])
            // Legenda só faz sentido quando há duas séries — quando o modo
            // é single-kind, esconde pra não mostrar uma legenda redundante.
            .chartLegend(mode == .both ? .visible : .hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
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

    private func plottable(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

#Preview {
    let cal = Calendar.current
    let today = Date()
    let startOfThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: today))!

    let samples: [MonthlyKindTotal] = (0 ..< 8).reversed().map { offset in
        let month = cal.date(byAdding: .month, value: -offset, to: startOfThisMonth)!
        return MonthlyKindTotal(
            monthStart: month,
            income: Decimal(5000 + Int.random(in: -800 ... 800)),
            expense: Decimal(3500 + Int.random(in: -1200 ... 1500))
        )
    }

    return VStack(spacing: 24) {
        IncomeVsExpenseChart(totals: samples, mode: .both)
            .frame(height: 220)
        IncomeVsExpenseChart(totals: samples, mode: .income)
            .frame(height: 220)
        IncomeVsExpenseChart(totals: samples, mode: .expense)
            .frame(height: 220)
    }
    .padding()
    .frame(width: 700)
}
