import SwiftUI

/// Card de métrica única, usado pelos 4 cards do dashboard.
struct MetricCard: View {
    let title: String
    let value: Decimal
    let icon: AppIcon?
    let accent: Color

    /// Mostra "—" em vez do valor. Usado em "Patrimônio investido" enquanto
    /// a Fase 6 não chegou — sinaliza visualmente que a métrica existe mas
    /// ainda não tem dado, em vez de mostrar "R$ 0,00" (que confundiria com
    /// "tem 0 reais investidos").
    var placeholder: Bool = false

    var body: some View {
        // `GroupBox` é o container HIG-padrão pra agrupamentos visuais
        // discretos (material backdrop, corner radius do sistema). O sinal
        // de "kind" (income/expense/transfer) vive no ícone tingido com
        // `accent` — sem mais tint de fundo, que perdemos junto.
        GroupBox {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.xs) {
                    if let icon {
                        Image(systemName: icon.systemImage)
                            .font(.callout)
                            .foregroundStyle(accent)
                    }
                    Text(title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text(placeholder ? "—" : value.formatted(.currency(code: "BRL")))
                    // `monospacedDigit()` alinha os números entre cards com
                    // largura visualmente igual — sem ele, o "1" ocuparia menos
                    // espaço que o "8" e os valores ficariam visualmente desalinhados.
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(placeholder ? Color.secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        MetricCard(
            title: "Saldo total",
            value: 12345.67,
            icon: .balance,
            accent: .brandPrimary
        )
        MetricCard(
            title: "Gastos do mês",
            value: 2340.00,
            icon: .expenseFlow,
            accent: .expense
        )
        MetricCard(
            title: "Patrimônio investido",
            value: 0,
            icon: .netResult,
            accent: .income,
            placeholder: true
        )
    }
    .padding()
    .frame(width: 320)
}
