import Charts
import SwiftUI

/// Gastos por categoria como **barras horizontais** ordenadas desc.
///
/// **Por que barras horizontais e não donut:** o objetivo é comparar
/// magnitudes ("gastei o dobro em A do que em B?"). Donut comunica
/// proporção, mas o olho humano lê pior diferenças de ângulo do que de
/// comprimento — barra horizontal é a forma canônica pra ranking quantitativo.
///
/// Layout: chart à esquerda, legenda detalhada à direita (swatch + nome +
/// valor formatado em BRL). A barra fica sem label no eixo Y — a legenda
/// lateral já identifica via cor; mostrar nomes nos dois lados é redundante
/// e gasta espaço horizontal precioso.
struct CategoryBarChart: View {
    let totals: [CategoryTotal]

    var body: some View {
        if totals.isEmpty {
            // `.frame(maxWidth: .infinity)` força o empty state a esticar pra
            // a largura disponível — sem isso ele toma só a largura intrínseca
            // do conteúdo e o `VStack(alignment: .leading)` do chartCard pai
            // alinha tudo à esquerda em vez de centralizar.
            ContentUnavailableView(
                "Sem gastos no período",
                systemImage: AppIcon.categoryRankingEmpty.systemImage,
                description: Text("Adicione transações pra ver o ranking por categoria.")
            )
            .frame(maxWidth: .infinity)
        } else {
            HStack(alignment: .top, spacing: 24) {
                chart
                    .frame(maxWidth: .infinity)
                legend
                    .frame(maxWidth: 280, alignment: .leading)
            }
        }
    }

    // MARK: - Chart

    private var chart: some View {
        Chart(totals) { item in
            BarMark(
                x: .value("Total", plottable(item.total)),
                y: .value("Categoria", item.categoryName)
            )
            .foregroundStyle(item.icon?.color ?? .brandPrimary.opacity(0.5))
            .cornerRadius(4)
        }
        // Domain explícito na ordem do array (que já chega desc do
        // repository) — primeira categoria do domain fica em cima no eixo Y,
        // resultando em "maior gasto no topo" e bate com a ordem da legenda.
        .chartYScale(domain: totals.map(\.categoryName))
        // Esconde labels do Y — a legenda lateral cobre a identificação.
        .chartYAxis(.hidden)
        .chartXAxis {
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

    // MARK: - Legenda

    private var legend: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(totals) { item in
                HStack(spacing: 10) {
                    Circle()
                        .fill(item.icon?.color ?? .brandPrimary.opacity(0.5))
                        .frame(width: 10, height: 10)

                    Text(item.categoryName)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    Text(item.total.formatted(.currency(code: "BRL")))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func plottable(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

#Preview {
    CategoryBarChart(totals: [
        // Ordem desc reproduzindo o que o repository devolveria.
        CategoryTotal(categoryId: UUID(), categoryName: "Alimentação e Supermercado", icon: .utensils,   total: 3_200),
        CategoryTotal(categoryId: UUID(), categoryName: "Transporte e Viagem",        icon: .car,        total: 1_850),
        CategoryTotal(categoryId: UUID(), categoryName: "Contas e Serviços",          icon: .zap,        total: 1_240),
        CategoryTotal(categoryId: UUID(), categoryName: "Entretenimento e Lazer",     icon: .monitor,    total: 820),
        CategoryTotal(categoryId: UUID(), categoryName: "Saúde e Medicina",           icon: .heart,      total: 540),
        CategoryTotal(categoryId: UUID(), categoryName: "Compras Pessoais",           icon: .shoppingBag, total: 320),
    ])
    .frame(width: 900, height: 320)
    .padding()
}
