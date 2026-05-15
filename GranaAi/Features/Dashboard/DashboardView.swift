import SwiftUI

/// Tela principal de visualização da saúde financeira do período.
///
/// **Layouts divergentes Mac vs iPhone** (via `#if os(macOS)`):
/// - Mac: 4 cards + 2 gráficos grandes, idiomático "command center" desktop.
/// - iPhone: card grande de saldo + lista de últimas 5 transações + botão `+`.
///   Sem gráficos no celular — não cabem com qualidade no espaço disponível.
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var store: DashboardStore?
    /// Modo do gráfico de receita vs. despesa. Reside como `@State` local
    /// porque é estado **só** de visualização — não afeta queries, não
    /// precisa persistir entre sessões. Reabrir o app volta pra `.both`.
    @State private var incomeVsExpenseMode: IncomeVsExpenseMode = .both

    var body: some View {
        Group {
            if let store {
                content(store: store)
                    .environment(store)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if store == nil {
                store = DashboardStore(database: environment.database)
            }
        }
        .navigationTitle("Dashboard")
    }

    #if os(macOS)
    @ViewBuilder
    private func content(store: DashboardStore) -> some View {
        // `@Bindable` é o equivalente moderno do `@ObservedObject` legado pra
        // tipos `@Observable`. Permite criar `$bindable.filter` (Binding) sem
        // mexer no tipo do parâmetro.
        @Bindable var bindable = store

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Text(store.filter.displayName)
                        .font(.title2.weight(.semibold))

                    Spacer()

                    // 4 presets cobrem os dois "modos" do dashboard: análise
                    // de mês fechado (atual/anterior) vs. tendência longitudinal
                    // (6/12 meses). `custom` segue no enum pro futuro
                    // (date-range picker), mas não está exposto na UI hoje.
                    Picker("Período", selection: $bindable.filter) {
                        Text("Mês atual").tag(PeriodFilter.currentMonth)
                        Text("Mês anterior").tag(PeriodFilter.previousMonth)
                        Text("6 meses").tag(PeriodFilter.last6Months)
                        Text("12 meses").tag(PeriodFilter.last12Months)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                if let error = store.lastError {
                    errorBanner(error)
                }

                cardsGrid(store: store)

                chartsRow(store: store)
            }
            .padding()
        }
        .task {
            await store.refresh()
        }
    }

    private func cardsGrid(store: DashboardStore) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220), spacing: 12)],
            spacing: 12
        ) {
            MetricCard(
                title: "Saldo total",
                value: store.totalBalance,
                icon: .balance,
                accent: .brandPrimary
            )
            // Títulos genéricos ("no período") porque o filtro também muda
            // pra 6/12 meses — "Gastos do mês" seria mentira nesses casos.
            // O header acima já mostra o `displayName` do filtro.
            MetricCard(
                title: "Gastos no período",
                value: store.periodExpenses,
                icon: .expenseFlow,
                accent: .expense
            )
            MetricCard(
                title: "Receitas no período",
                value: store.periodIncome,
                icon: .incomeFlow,
                accent: .income
            )
            MetricCard(
                title: "Patrimônio investido",
                value: store.investmentValue,
                icon: .netResult,
                accent: .brandSecondary,
                placeholder: true
            )
        }
    }

    @ViewBuilder
    private func chartsRow(store: DashboardStore) -> some View {
        // Ambos os modos usam VStack full-width — bar chart horizontal de
        // categoria precisa de espaço pra comparar comprimentos, e o weekday
        // ganha respiro pras 7 barras. Padrão único Mac, sem grid 2-colunas.
        switch store.filter.scope {
        case .singleMonth:
            VStack(spacing: 16) {
                chartCard("Gastos por categoria") {
                    CategoryBarChart(totals: store.expensesByCategory)
                        .frame(minHeight: 320)
                }
                chartCard("Gastos por dia da semana") {
                    WeekdayExpensesChart(totals: store.weekdayExpenses)
                        .frame(minHeight: 280)
                }
            }

        case .multiMonth:
            VStack(spacing: 16) {
                chartCard("Gastos por categoria") {
                    CategoryBarChart(totals: store.expensesByCategory)
                        .frame(minHeight: 320)
                }
                chartCard("Receita vs. despesa (mês a mês)") {
                    // Picker no header escolhe o que entra no plot: ambos
                    // (default), só receita, ou só despesa. Sem reload de
                    // dados — o store já tem income+expense, só filtramos
                    // na renderização.
                    Picker("Modo", selection: $incomeVsExpenseMode) {
                        ForEach(IncomeVsExpenseMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                } content: {
                    IncomeVsExpenseChart(
                        totals: store.monthlyByKind,
                        mode: incomeVsExpenseMode
                    )
                    .frame(minHeight: 280)
                }
            }
        }
    }

    @ViewBuilder
    private func chartCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        chartCard(title, trailing: { EmptyView() }, content: content)
    }

    /// Sobrecarga que aceita conteúdo "trailing" no header (ex: um `Picker`
    /// de modo). Mantém o callsite limpo: cards simples seguem usando a
    /// versão de 1 argumento, cards interativos passam o trailing.
    @ViewBuilder
    private func chartCard<Trailing: View, Content: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                trailing()
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.brandPrimary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func errorBanner(_ error: Error) -> some View {
        Label(error.localizedDescription, systemImage: AppIcon.warning.systemImage)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.danger.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.danger)
    }
    #else

    // MARK: - iPhone

    @State private var transactionStore: TransactionStore?
    @State private var showingForm = false

    @ViewBuilder
    private func content(store: DashboardStore) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let error = store.lastError {
                    Label(error.localizedDescription, systemImage: AppIcon.warning.systemImage)
                        .foregroundStyle(.danger)
                        .font(.callout)
                        .padding(.horizontal)
                }

                MetricCard(
                    title: "Saldo total",
                    value: store.totalBalance,
                    icon: .balance,
                    accent: .brandPrimary
                )
                .padding(.horizontal)

                Section {
                    if store.lastFiveTransactions.isEmpty {
                        ContentUnavailableView(
                            "Sem transações ainda",
                            systemImage: AppIcon.transactionsList.systemImage,
                            description: Text("Toque em + pra adicionar a primeira.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 4) {
                            ForEach(store.lastFiveTransactions) { transaction in
                                TransactionRow(
                                    transaction: transaction,
                                    category: transactionStore?.category(for: transaction.categoryId),
                                    account: transactionStore?.account(for: transaction.accountId),
                                    icon: transactionStore?.icon(for: transaction.categoryId)
                                )
                                .padding(.horizontal)
                                Divider().padding(.leading)
                            }
                        }
                    }
                } header: {
                    Text("Últimas transações")
                        .font(.headline)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .onAppear {
            if transactionStore == nil {
                transactionStore = TransactionStore(database: environment.database)
            }
        }
        .task {
            await store.refresh()
        }
        .task {
            // Precisamos do `TransactionStore` só pra resolver nome/ícone
            // de categoria e conta na lista das últimas 5. `start()` fica
            // rodando enquanto a View existir (`.task` cancela no dismiss).
            await transactionStore?.start()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingForm = true
                } label: {
                    Label("Adicionar", systemImage: AppIcon.add.systemImage)
                }
            }
        }
        .sheet(isPresented: $showingForm, onDismiss: {
            Task { await store.refresh() }
        }) {
            if let transactionStore {
                TransactionFormView()
                    .environment(transactionStore)
            }
        }
    }
    #endif
}

#Preview("Mac") {
    NavigationStack {
        DashboardView()
            .environment(AppEnvironment())
    }
    .frame(width: 1000, height: 700)
}

#Preview("iPhone") {
    NavigationStack {
        DashboardView()
            .environment(AppEnvironment())
    }
}
