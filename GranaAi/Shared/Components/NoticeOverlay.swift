import SwiftUI

/// Overlay global de toasts. Plugado uma única vez na raiz da árvore
/// (`ContentView`). Observa o `NoticeCenter.shared` e renderiza um stack de
/// cards no canto superior-direito da janela.
///
/// **Posição:** top-trailing. Padrão macOS pra notificações in-app — não
/// compete com o sidebar (à esquerda) nem com o conteúdo principal (centro).
/// **Auto-dismiss:** controlado pelo `NoticeCenter` (timeout varia por
/// `Kind` e pela presença de ações). Card também tem botão X pra dispensa
/// manual e botões de ação inline.
struct NoticeOverlay: ViewModifier {
    let center: NoticeCenter

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            VStack(spacing: 10) {
                ForEach(center.notices) { notice in
                    NoticeCard(notice: notice) {
                        center.dismiss(notice.id)
                    }
                    // Hit testing fica isolado no card. Padding ao redor e o
                    // frame externo de 420pt não capturam cliques, então o
                    // conteúdo embaixo continua interativo.
                    .allowsHitTesting(true)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .padding(16)
            .frame(maxWidth: 420, alignment: .trailing)
            .animation(.spring(duration: 0.35, bounce: 0.15), value: center.notices)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Card

private struct NoticeCard: View {
    let notice: NoticeCenter.Notice
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notice.kind.iconName)
                .font(.title3)
                .foregroundStyle(notice.kind.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let message = notice.message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !notice.actions.isEmpty {
                    actionsRow
                }
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Fechar")
            .accessibilityLabel("Fechar notificação")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(notice.kind.tint.opacity(0.5), lineWidth: 1)
        )
    }

    private var actionsRow: some View {
        HStack(spacing: 8) {
            ForEach(notice.actions) { action in
                Button(action.title) {
                    action.handler()
                    // Toast some assim que a ação é executada — comportamento
                    // padrão de "Undo snackbar" do Material/HIG. Sem isso o
                    // usuário teria que clicar Undo e depois X, em sequência.
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(action.role == .destructive ? .danger : .accentColor)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Kind → visual

extension NoticeCenter.Kind {
    var iconName: String {
        switch self {
        case .error: AppIcon.error.systemImage
        case .success: AppIcon.success.systemImage
        case .info: AppIcon.info.systemImage
        }
    }

    var tint: Color {
        switch self {
        case .error: .danger
        case .success: .success
        case .info: .brandPrimary
        }
    }
}

// MARK: - View modifier helper

extension View {
    /// Atalho semântico pra plugar o overlay global. Chamar uma única vez na
    /// raiz da janela. Resolve `NoticeCenter.shared` no MainActor — o default
    /// argument inline daria warning Swift 6 (`.shared` é MainActor-isolated).
    @MainActor
    func noticeOverlay() -> some View {
        modifier(NoticeOverlay(center: NoticeCenter.shared))
    }

    /// Variante com injeção explícita (testes/previews).
    @MainActor
    func noticeOverlay(center: NoticeCenter) -> some View {
        modifier(NoticeOverlay(center: center))
    }
}

#Preview("Notificações") {
    struct Demo: View {
        var body: some View {
            VStack(spacing: 16) {
                Button("Erro genérico") {
                    NoticeCenter.shared.report(
                        title: "Erro inesperado",
                        message: "Algo deu errado executando essa ação."
                    )
                }
                Button("Erro tipado") {
                    NoticeCenter.shared.report(DatabaseError.notInitialized)
                }
                Button("Sucesso simples") {
                    NoticeCenter.shared.success(title: "Conta criada")
                }
                Button("Sucesso com ação") {
                    NoticeCenter.shared.success(
                        title: "Importação concluída",
                        message: "12 transações em 1 lote.",
                        actions: [
                            .init(title: "Desfazer", role: .destructive) {
                                NoticeCenter.shared.info(title: "Lote desfeito")
                            }
                        ]
                    )
                }
                Button("Info") {
                    NoticeCenter.shared.info(
                        title: "Categorização parcial",
                        message: "3 itens caíram pro fallback."
                    )
                }
                Button("Limpar") {
                    NoticeCenter.shared.dismissAll()
                }
            }
            .padding(40)
            .frame(width: 700, height: 500)
            .noticeOverlay()
        }
    }
    return Demo()
}
