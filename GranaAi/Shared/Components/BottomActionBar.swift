import SwiftUI

/// Faixa horizontal padrão de rodapé pra wizards e sheets de revisão.
///
/// Layout fixo:
/// - `Divider()` no topo, separando do conteúdo acima.
/// - Caption à esquerda (contagem, status) — opcional, oculta quando `nil`.
/// - Conteúdo do `trailing` (geralmente 1–2 botões) ancorado à direita via `Spacer`.
/// - Padding consistente: `20pt` horizontal · `12pt` vertical, alinhando com
///   o título da toolbar do sheet.
///
/// **Por que componente compartilhado:** as telas de import (OFX preview) e
/// de revisão de categorização repetiam o mesmo padrão. Centralizar evita
/// drift visual (padding diferente, espaçamentos diferentes) entre as telas.
///
/// Uso:
/// ```swift
/// BottomActionBar(caption: "7 transações selecionadas em 1 conta") {
///     Button("Voltar") { ... }
///     Button("Importar") { ... }
///         .buttonStyle(.borderedProminent)
/// }
/// ```
struct BottomActionBar<Trailing: View>: View {
    let caption: String?
    @ViewBuilder var trailing: () -> Trailing

    init(
        caption: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.caption = caption
        self.trailing = trailing
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                trailing()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}

#Preview("Com caption e dois botões") {
    VStack(spacing: 0) {
        Color.gray.opacity(0.1)
            .frame(maxHeight: .infinity)
        BottomActionBar(caption: "7 transações selecionadas em 1 conta") {
            Button("Voltar") {}
            Button("Importar 7 transações") {}
                .buttonStyle(.borderedProminent)
        }
    }
    .frame(width: 700, height: 200)
}

#Preview("Sem caption, um botão") {
    VStack(spacing: 0) {
        Color.gray.opacity(0.1)
            .frame(maxHeight: .infinity)
        BottomActionBar {
            Button("Avançar") {}
                .buttonStyle(.borderedProminent)
        }
    }
    .frame(width: 700, height: 200)
}
