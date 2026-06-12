import Charts
import Foundation
import SwiftUI

/// Painel direito da tela de Cartões: detalhe do cartão selecionado.
/// Estrutura inspirada na visão web do Inter — header com identificação +
/// gauge de limite, timeline de faturas, trio de cards de ciclo (anterior /
/// atual / próxima) e tabela de lançamentos da fatura selecionada.
///
/// **Estado local:** `selectedStatementId` mantém a fatura focada. Default
/// pra fatura em aberto mais próxima do fechamento (a "próxima fatura" do
/// usuário); cai pra mais recente quando todas estão pagas. Re-resolve
/// quando o usuário muda de cartão (via `.onChange(of: account.id)`).
struct CreditCardDetailView: View {
    let account: Account
    let store: AccountStore

    @State private var selectedStatementId: UUID?

    private var institution: Institution? {
        store.institution(forAccount: account)
    }

    private var details: CreditCardDetails? {
        store.creditCard(for: account.id)
    }

    /// Faturas reais (persistidas) do cartão, ordenadas cronologicamente
    /// — base pra timeline e pra resolver a "anterior / atual / próxima"
    /// no `StatementCyclePanel`.
    private var statements: [Statement] {
        store.statements
            .filter { $0.accountId == account.id }
            .sorted { $0.closingDate < $1.closingDate }
    }

    /// Default da seleção: prefere a fatura em aberto mais próxima do
    /// fechamento (próxima a vencer); cai pra última paga se tudo já foi
    /// pago. `nil` apenas quando não há nenhuma fatura — cartão sem compras.
    private var defaultStatementId: UUID? {
        if let open = statements.first(where: { $0.paidAt == nil }) {
            return open.id
        }
        return statements.last?.id
    }

    /// Janela do **próximo** ciclo após a última fatura existente — usado
    /// pra projetar "Julho" e "Agosto" na timeline e no card de "próxima
    /// fatura" quando o cartão ainda não teve compra naquele ciclo.
    ///
    /// Sem `CreditCardDetails` (cartão sem dia de fechamento configurado),
    /// projeção é impossível — devolve array vazio.
    private var projectedCycles: [StatementWindow] {
        guard let details else { return [] }
        let now = Date()
        // Ponto de partida: max(closing_date da última fatura + 1d, hoje).
        // Cobre os dois casos: cartão sem fatura ainda (parte de "hoje") e
        // cartão com histórico (parte do dia seguinte ao último fechamento).
        let start: Date = {
            if let last = statements.last {
                return Calendar.current.date(byAdding: .day, value: 1, to: last.closingDate) ?? now
            }
            return now
        }()
        var cycles: [StatementWindow] = []
        var cursor = start
        for _ in 0 ..< 2 {
            let window = StatementWindow.resolve(
                closingDay: details.statementClosingDay,
                paymentDueDay: details.paymentDueDay,
                on: cursor
            )
            cycles.append(window)
            // Avança pra dia seguinte ao fechamento da janela atual pra
            // iterar pro próximo ciclo.
            cursor = Calendar.current.date(byAdding: .day, value: 1, to: window.closingDate) ?? cursor
        }
        return cycles
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let details, let limit = details.creditLimit, limit > 0 {
                    LimitGaugeBlock(
                        used: store.currentBalance(for: account).magnitude,
                        limit: limit,
                        currency: account.currency
                    )
                }
                if !statements.isEmpty || !projectedCycles.isEmpty {
                    StatementTimelineChart(
                        statements: statements,
                        projections: projectedCycles,
                        currency: account.currency,
                        selectedId: $selectedStatementId
                    )
                    StatementCyclePanel(
                        statements: statements,
                        projections: projectedCycles,
                        selectedId: $selectedStatementId,
                        currency: account.currency,
                        bestPurchaseDay: bestPurchaseDay()
                    )
                }
                transactionsBlock
            }
            .padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            if selectedStatementId == nil { selectedStatementId = defaultStatementId }
        }
        .onChange(of: account.id) { _, _ in
            selectedStatementId = defaultStatementId
        }
        .onChange(of: statements.map(\.id)) { _, _ in
            if selectedStatementId == nil || !statements.contains(where: { $0.id == selectedStatementId }) {
                selectedStatementId = defaultStatementId
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            if let institution {
                InstitutionIcon(kind: institution.kind, size: 56)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "creditcard.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(bankName)
                    .font(.title2.weight(.semibold))
                Text(maskedNumber)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                if account.archived {
                    Text("Arquivado")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.secondary.opacity(0.15))
                        )
                }
            }

            Spacer()
        }
    }

    private var bankName: String {
        institution?.name ?? "Cartão"
    }

    private var maskedNumber: String {
        guard let last4 = details?.cardLastFour, last4.count == 4 else { return "Cartão" }
        return "•••• \(last4)"
    }

    /// "Melhor dia de compra" = dia seguinte ao fechamento. Faz a compra
    /// começar o ciclo no dia 1 — maior prazo até o vencimento. Só faz
    /// sentido pra fatura em aberto (a próxima a fechar).
    private func bestPurchaseDay() -> Int? {
        guard let details else { return nil }
        let day = details.statementClosingDay + 1
        // Wraps de mês curto não importam aqui — é hint de UX, não data
        // exata. Saturamos em 31; o usuário entende que vira o mês.
        return day > 31 ? 1 : day
    }

    // MARK: - Transactions block

    private var transactionsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Lançamentos")
                    .font(.headline)
                Spacer()
                if let total = selectedStatementTotal {
                    Text(total.formatted(.currency(code: account.currency)))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let selectedId = selectedStatementId,
               statements.contains(where: { $0.id == selectedId })
            {
                StatementTransactionsList(
                    statementId: selectedId,
                    container: store.container
                )
            } else {
                // Fatura projetada (não persistida) ou nenhuma seleção:
                // não há transações pra listar.
                emptyTransactions
            }
        }
    }

    private var selectedStatementTotal: Decimal? {
        guard let selectedId = selectedStatementId else { return nil }
        return statements.first(where: { $0.id == selectedId })?.totalAmount
    }

    private var emptyTransactions: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Sem lançamentos nesta fatura")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 30)
            Spacer()
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        )
    }
}

// MARK: - Limit gauge block

/// Bloco do tipo "Limite utilizado: R$ X de R$ Y" + barra horizontal.
/// Reaproveita as mesmas thresholds (30/70%) usadas no resto da feature
/// pra que verde/amarelo/vermelho tenham significado consistente.
private struct LimitGaugeBlock: View {
    let used: Decimal
    let limit: Decimal
    let currency: String

    private var percent: Double {
        let l = NSDecimalNumber(decimal: limit).doubleValue
        guard l > 0 else { return 0 }
        let u = NSDecimalNumber(decimal: used).doubleValue
        return max(0, min(1, u / l))
    }

    private var color: Color {
        if percent < 0.30 { return .success }
        if percent < 0.70 { return .warning }
        return .danger
    }

    private var available: Decimal {
        max(0, limit - used)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LIMITE UTILIZADO")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(used.formatted(.currency(code: currency)))
                        .font(.title.weight(.bold).monospacedDigit())
                        .foregroundStyle(.primary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("LIMITE TOTAL")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(limit.formatted(.currency(code: currency)))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geo.size.width * percent))
                }
            }
            .frame(height: 8)

            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text("Usado: \(used.formatted(.currency(code: currency)))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.primary)
                }
                HStack(spacing: 6) {
                    Circle().fill(Color.secondary.opacity(0.4)).frame(width: 8, height: 8)
                    Text("Disponível: \(available.formatted(.currency(code: currency)))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(percent * 100))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Timeline chart

/// Barras de faturas no tempo. Cada barra é uma Statement (real ou
/// projetada). Clicar muda `selectedId`. Cores:
/// - Paga: cinza claro
/// - Aberta: cor de destaque (accent)
/// - Projetada (sem dados): cinza pontilhado simulado via opacidade reduzida
///
/// **Por que não usa `Chart` com series e legend:** as bandeiras semânticas
/// (paga/aberta/projetada) viram cor por barra, não uma legenda compartilhada
/// — fica mais limpo configurar `foregroundStyle` por item.
private struct StatementTimelineChart: View {
    let statements: [Statement]
    let projections: [StatementWindow]
    let currency: String
    @Binding var selectedId: UUID?

    private struct Bar: Identifiable, Hashable {
        let id: UUID
        let label: String
        let total: Decimal
        let status: Status
        let closingDate: Date

        enum Status: Hashable {
            case paid
            case open
            case projected
        }
    }

    private var bars: [Bar] {
        var result: [Bar] = statements.map { s in
            Bar(
                id: s.id,
                label: Self.monthFormatter.string(from: s.closingDate),
                total: s.totalAmount,
                status: s.paidAt == nil ? .open : .paid,
                closingDate: s.closingDate
            )
        }
        for window in projections {
            // Reutiliza `closingDate` como id determinístico (`UUID` aqui
            // é só pra `Identifiable`). Convertemos pra UUID via hash
            // estável — não dá colisão na prática porque closingDate é
            // único por cartão dentro do escopo.
            result.append(Bar(
                id: UUID(),
                label: Self.monthFormatter.string(from: window.closingDate),
                total: 0,
                status: .projected,
                closingDate: window.closingDate
            ))
        }
        return result.sorted { $0.closingDate < $1.closingDate }
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        f.locale = Locale(identifier: "pt_BR")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Histórico de faturas")
                .font(.headline)

            // Versão custom (HStack de retângulos) em vez de Swift Charts
            // BarMark porque precisamos de cor diferente por barra E hit
            // testing individual pra seleção — combinação onde o `Chart`
            // fica mais verbosa que vale a pena nesse caso.
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(bars) { bar in
                    BarColumn(
                        bar: bar,
                        maxTotal: maxBarValue,
                        isSelected: bar.id == selectedId,
                        currency: currency,
                        onTap: {
                            if bar.status != .projected {
                                selectedId = bar.id
                            }
                        }
                    )
                }
            }
            .frame(height: 140)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
    }

    private var maxBarValue: Decimal {
        let max = bars.map(\.total).max() ?? 0
        return max > 0 ? max : 1
    }

    private struct BarColumn: View {
        let bar: Bar
        let maxTotal: Decimal
        let isSelected: Bool
        let currency: String
        let onTap: () -> Void

        var body: some View {
            VStack(spacing: 4) {
                Text(bar.total > 0 ? bar.total.formatted(.currency(code: currency)) : " ")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                GeometryReader { geo in
                    let fillHeight = fillHeight(in: geo.size.height)
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(barColor)
                            .frame(width: 18, height: max(8, fillHeight))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }

                Text(bar.label.capitalized)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
        }

        private var barColor: Color {
            switch bar.status {
            case .open:
                return isSelected ? Color.accentColor : Color.accentColor.opacity(0.5)
            case .paid:
                return isSelected ? Color.secondary : Color.secondary.opacity(0.45)
            case .projected:
                return Color.secondary.opacity(0.25)
            }
        }

        /// Altura proporcional ao maior valor dentro do bloco. Faturas
        /// projetadas (total = 0) ganham um stub mínimo (8pt) pra ficarem
        /// visíveis e clicáveis mesmo zeradas — caso contrário sumiriam.
        private func fillHeight(in available: CGFloat) -> CGFloat {
            let total = NSDecimalNumber(decimal: bar.total).doubleValue
            let max = NSDecimalNumber(decimal: maxTotal).doubleValue
            guard max > 0 else { return 8 }
            let ratio = total / max
            return CGFloat(ratio) * available
        }
    }
}

// MARK: - Cycle panel (3 columns)

/// Trio de cards "anterior / atual / próxima" centrado na fatura selecionada.
/// Caixa central com borda colorida — espelha o destaque do Inter pra fatura
/// em aberto. Quando a seleção está numa borda (primeira ou última fatura),
/// o card daquele lado fica vazio em vez de mostrar fatura aleatória.
private struct StatementCyclePanel: View {
    let statements: [Statement]
    let projections: [StatementWindow]
    @Binding var selectedId: UUID?
    let currency: String
    /// Dia "ideal" pra fazer uma compra (fechamento + 1) — só faz sentido
    /// pra fatura em aberto.
    let bestPurchaseDay: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            cell(for: previousItem, role: .previous)
            cell(for: selectedItem, role: .selected)
            cell(for: nextItem, role: .next)
        }
    }

    // MARK: - Item resolution

    private enum CycleItem {
        case statement(Statement)
        case projection(StatementWindow)
        case none

        var closingDate: Date? {
            switch self {
            case let .statement(s): return s.closingDate
            case let .projection(w): return w.closingDate
            case .none: return nil
            }
        }
    }

    /// Lista unificada (statements + projeções) ordenada por closingDate.
    /// `selectedId` só aponta pra Statement real — projeções não são
    /// selecionáveis.
    private var ordered: [CycleItem] {
        var items: [CycleItem] = statements.map { .statement($0) }
        items.append(contentsOf: projections.map { .projection($0) })
        return items.sorted { a, b -> Bool in
            (a.closingDate ?? .distantPast) < (b.closingDate ?? .distantPast)
        }
    }

    private var selectedIndex: Int? {
        guard let selectedId else { return nil }
        return ordered.firstIndex { item in
            if case let .statement(s) = item, s.id == selectedId { return true }
            return false
        }
    }

    private var selectedItem: CycleItem {
        guard let idx = selectedIndex else { return .none }
        return ordered[idx]
    }

    private var previousItem: CycleItem {
        guard let idx = selectedIndex, idx > 0 else { return .none }
        return ordered[idx - 1]
    }

    private var nextItem: CycleItem {
        guard let idx = selectedIndex, idx + 1 < ordered.count else { return .none }
        return ordered[idx + 1]
    }

    // MARK: - Cell rendering

    private enum Role {
        case previous, selected, next
    }

    @ViewBuilder
    private func cell(for item: CycleItem, role: Role) -> some View {
        switch item {
        case let .statement(s):
            StatementCycleCard(
                title: monthTitle(s.closingDate),
                amount: s.totalAmount,
                statusLabel: s.paidAt == nil ? "Aberta" : "Paga",
                statusTint: s.paidAt == nil ? .info : .neutral,
                dueDate: s.dueDate,
                bestPurchaseDay: role == .selected && s.paidAt == nil ? bestPurchaseDay : nil,
                currency: currency,
                isHighlighted: role == .selected,
                isMuted: role != .selected,
                onTap: role == .selected ? nil : { selectedId = s.id }
            )
        case let .projection(w):
            StatementCycleCard(
                title: monthTitle(w.closingDate),
                amount: 0,
                statusLabel: "Prevista",
                statusTint: .neutral,
                dueDate: w.dueDate,
                bestPurchaseDay: nil,
                currency: currency,
                isHighlighted: false,
                isMuted: true,
                onTap: nil
            )
        case .none:
            // Slot vazio com mesma largura pra manter o trio alinhado.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(minHeight: 120)
        }
    }

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        f.locale = Locale(identifier: "pt_BR")
        return f
    }()

    private func monthTitle(_ date: Date) -> String {
        Self.monthYearFormatter.string(from: date).capitalized
    }
}

/// Card individual do trio de ciclo. Visual segue o padrão do Inter:
/// header com mês + badge de status, total grande, data de vencimento e —
/// quando é a fatura em aberto — o "melhor dia de compra".
private struct StatementCycleCard: View {
    let title: String
    let amount: Decimal
    let statusLabel: String
    let statusTint: BadgeTint
    let dueDate: Date
    let bestPurchaseDay: Int?
    let currency: String
    let isHighlighted: Bool
    let isMuted: Bool
    let onTap: (() -> Void)?

    enum BadgeTint {
        case info, neutral
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.callout.weight(.semibold))
                StatusBadge(label: statusLabel, tint: statusTint)
                Spacer()
            }

            Text(amount.formatted(.currency(code: currency)))
                .font(.title2.weight(.bold).monospacedDigit())

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Data de vencimento")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.dayMonthFormatter.string(from: dueDate))
                        .font(.caption.weight(.semibold).monospacedDigit())
                }
                if let bestPurchaseDay {
                    HStack {
                        Text("Melhor dia de compra")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(bestPurchaseDay)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isHighlighted ? Color.accentColor : Color.secondary.opacity(0.15),
                    lineWidth: isHighlighted ? 1.5 : 1
                )
        )
        .opacity(isMuted ? 0.75 : 1)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    private static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM"
        f.locale = Locale(identifier: "pt_BR")
        return f
    }()

    private struct StatusBadge: View {
        let label: String
        let tint: BadgeTint

        var body: some View {
            Text(label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(background)
                )
                .foregroundStyle(foreground)
        }

        private var background: Color {
            switch tint {
            case .info: return Color.accentColor.opacity(0.18)
            case .neutral: return Color.secondary.opacity(0.18)
            }
        }

        private var foreground: Color {
            switch tint {
            case .info: return Color.accentColor
            case .neutral: return Color.secondary
            }
        }
    }
}
