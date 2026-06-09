import SwiftUI

/// Linha de controle de seleção que vai **dentro do scroll**, logo antes das
/// rows de transação. Fica abaixo do header `Section` (que tem só o título
/// "Transações") pra o checkbox master alinhar verticalmente com a coluna
/// de checkboxes das rows.
///
/// Compartilhada entre [OFXReviewStepView] e [CSVReviewStepView] — ambos os
/// fluxos do wizard precisam do mesmo controle "marcar/desmarcar todas".
struct TransactionsSelectionRow: View {
    let summary: String
    let allSelected: Bool
    let onToggleAll: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { allSelected },
                set: { onToggleAll($0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .help(allSelected ? "Desmarcar todas" : "Marcar todas")
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }
}
