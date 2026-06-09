import SwiftUI

/// Row genérica de transação usada em todas as listas (import preview,
/// categorization review, extrato).
///
/// **Por que componente único:** as três telas precisam mostrar transações
/// de jeitos parecidos, mas com colunas diferentes. Manter três rows
/// independentes gerava drift visual (paddings, ícones, badges diferentes).
/// Centralizar aqui força consistência.
///
/// **Slots opcionais via parâmetros nullable:** o caller decide o que mostrar
/// passando (ou não) cada campo. Não há `Variant` enum: hoje só existe um
/// contexto real de uso (preview de import); quando uma segunda tela precisar
/// reusar a row com requisitos diferentes, aí sim avalia introduzir um enum.
struct TransactionRow: View {
    /// Badge de status à direita da row. Genérica — caller define label e tint
    /// conforme contexto (duplicada, revisada, pendente etc.).
    struct Status: Hashable {
        let label: String
        let tint: Tint

        enum Tint {
            case warning, success, info, neutral
        }

        static let duplicate = Status(label: "Já importada", tint: .warning)
    }

    /// Direção semântica do valor. Convenção visual: só **receita** colore
    /// (verde, destaque); saídas e nil ficam neutras (`.primary`),
    /// transferência cinza. Sem isso, em listas onde quase tudo é despesa
    /// (extrato de cartão p.ex.), pintar todo mundo de vermelho vira ruído —
    /// a cor deixa de informar nada.
    ///
    /// Note que `outgoing` (saída) é deliberadamente neutro — o caso "vermelho
    /// pra despesa" não existe nesta tela.
    enum AmountKind {
        case incoming, outgoing, transfer
    }

    let selection: Binding<Bool>?
    let institutionKind: InstitutionKind?
    let description: String
    let memo: String?
    let date: Date
    let amount: Decimal
    let amountKind: AmountKind?
    let status: Status?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let selection {
                Toggle("", isOn: selection)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }

            if let institutionKind {
                InstitutionIcon(kind: institutionKind, size: 24)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(description)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let memo, !memo.isEmpty {
                    Text(memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let status {
                statusBadge(status)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.currencyFormatter.string(from: amount as NSDecimalNumber) ?? "")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(amountColor)
                Text(Self.dateFormatter.string(from: date))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 88, alignment: .trailing)
        }
        // Opacidade reduzida quando há status "neutro" desativado (ex:
        // duplicada não-selecionada) — sinaliza que está pulada sem sumir
        // visualmente.
        .opacity(isDimmed ? 0.55 : 1.0)
    }

    private var amountColor: Color {
        switch amountKind {
        case .incoming: return .income // único destaque
        case .transfer: return .transfer
        case .outgoing, .none: return .primary
        }
    }

    private var isDimmed: Bool {
        guard let status, let selection else { return false }
        return status.tint == .warning && !selection.wrappedValue
    }

    private func statusBadge(_ status: Status) -> some View {
        Text(status.label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background(for: status.tint))
            .foregroundStyle(foreground(for: status.tint))
            .clipShape(Capsule())
    }

    private func background(for tint: Status.Tint) -> Color {
        switch tint {
        case .warning: return .warning.opacity(0.18)
        case .success: return .success.opacity(0.15)
        case .info: return .accentColor.opacity(0.15)
        case .neutral: return .secondary.opacity(0.15)
        }
    }

    private func foreground(for tint: Status.Tint) -> Color {
        switch tint {
        case .warning: return .secondary
        case .success: return .success
        case .info: return .accentColor
        case .neutral: return .secondary
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        return f
    }()

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "pt_BR")
        return f
    }()
}
