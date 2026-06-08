import Foundation
import SwiftUI

/// Lista de lançamentos da fatura selecionada. Stream reativo via
/// `watchByStatement` — re-emite quando uma transação é editada/inserida/
/// deletada e o `statement_id` casa. Componente independente pra que sua
/// `.task(id:)` reinicie sozinha quando o `statementId` muda.
///
/// Mantém `[UUID: Category]` carregado uma vez (snapshot) pra resolver o
/// nome + ícone da categoria de cada row sem segundo round-trip.
struct StatementTransactionsList: View {
    let statementId: UUID
    let container: AppContainer

    @State private var transactions: [Transaction] = []
    @State private var categoryById: [UUID: Category] = [:]
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            if isLoading, transactions.isEmpty {
                ProgressView()
                    .padding(.vertical, 20)
            } else if transactions.isEmpty {
                emptyView
            } else {
                rows
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .task(id: statementId) {
            await loadCategoriesOnce()
            await streamTransactions()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Sem lançamentos nesta fatura")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(transactions.enumerated()), id: \.element.id) { idx, transaction in
                if idx > 0 { Divider() }
                row(for: transaction)
            }
        }
    }

    private func row(for transaction: Transaction) -> some View {
        let category = categoryById[transaction.categoryId]
        return HStack(spacing: 12) {
            Text(Self.dayMonthFormatter.string(from: transaction.occurredAt))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)

            if let icon = category?.icon {
                CategoryIconBubble(icon: icon, size: 28)
            } else {
                placeholderIcon
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(transaction.description)
                    .font(.callout)
                    .lineLimit(1)
                if let category {
                    Text(category.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("-\(transaction.amount.magnitude.formatted(.currency(code: "BRL")))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var placeholderIcon: some View {
        Circle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: "questionmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
    }

    private static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd 'de' MMM"
        f.locale = Locale(identifier: "pt_BR")
        return f
    }()

    // MARK: - Stream

    private func streamTransactions() async {
        isLoading = true
        defer { isLoading = false }
        do {
            for try await rows in try container.transactions.watchByStatement(statementId: statementId) {
                transactions = rows
                isLoading = false
            }
        } catch is CancellationError {
        } catch {
            ErrorCenter.shared.report(error)
        }
    }

    /// Carrega categorias uma vez (snapshot) — não precisam de stream porque
    /// raramente mudam durante a visualização. Mapa por id pro lookup O(1)
    /// no `row(for:)`.
    private func loadCategoriesOnce() async {
        guard categoryById.isEmpty else { return }
        do {
            let categories = try await container.categories.getAll()
            categoryById = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        } catch {
            // Não bloqueante — sem categoria a row mostra só descrição.
            ErrorCenter.capture(error, title: "Falha ao carregar categorias")
        }
    }
}

/// Bolha redonda com o ícone da categoria + cor associada. Match visual
/// com o resto do app (sidebar de Categorias usa o mesmo padrão).
struct CategoryIconBubble: View {
    let icon: CategoryIcon
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(icon.color.opacity(0.18))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: icon.systemImage)
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(icon.color)
            }
    }
}
