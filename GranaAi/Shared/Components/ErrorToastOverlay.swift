import SwiftUI

/// Overlay global de toasts de erro. Plugado uma única vez na raiz da árvore
/// (`ContentView`). Observa o `ErrorCenter.shared` e renderiza um stack de
/// cards no canto superior-direito da janela.
///
/// **Posição:** top-trailing. Padrão macOS pra notificações in-app — não
/// compete com o sidebar (à esquerda) nem com o conteúdo principal (centro).
/// **Auto-dismiss:** controlado pelo `ErrorCenter`. Card também tem botão X
/// pra dispensa manual.
struct ErrorToastOverlay: ViewModifier {
    @Bindable var center: ErrorCenter

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            VStack(spacing: 10) {
                ForEach(center.notices) { notice in
                    ErrorToastCard(notice: notice) {
                        center.dismiss(notice.id)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .padding(16)
            .frame(maxWidth: 400, alignment: .trailing)
            .animation(.spring(duration: 0.35, bounce: 0.15), value: center.notices)
            // O overlay não deve roubar hit-testing fora dos cards — assim
            // o usuário continua interagindo com o conteúdo abaixo dele.
            .allowsHitTesting(!center.notices.isEmpty)
        }
    }
}

private struct ErrorToastCard: View {
    let notice: ErrorCenter.Notice
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: AppIcon.error.systemImage)
                .font(.title3)
                .foregroundStyle(.expense)

            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(notice.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                .stroke(Color.expense.opacity(0.5), lineWidth: 1)
        )
    }
}

extension View {
    /// Atalho semântico pra plugar o overlay global. Chamar uma única vez na
    /// raiz da janela. Resolve `ErrorCenter.shared` no MainActor — o default
    /// argument inline daria warning Swift 6 (`.shared` é MainActor-isolated).
    @MainActor
    func errorToastOverlay() -> some View {
        modifier(ErrorToastOverlay(center: ErrorCenter.shared))
    }

    /// Variante com injeção explícita (testes/previews).
    @MainActor
    func errorToastOverlay(center: ErrorCenter) -> some View {
        modifier(ErrorToastOverlay(center: center))
    }
}

#Preview("Toasts") {
    struct Demo: View {
        var body: some View {
            VStack(spacing: 16) {
                Button("Disparar erro genérico") {
                    ErrorCenter.shared.report(
                        title: "Erro inesperado",
                        message: "Algo deu errado executando essa ação."
                    )
                }
                Button("Disparar DatabaseError") {
                    ErrorCenter.shared.report(DatabaseError.notInitialized)
                }
                Button("Limpar") {
                    ErrorCenter.shared.dismissAll()
                }
            }
            .padding(40)
            .frame(width: 700, height: 500)
            .errorToastOverlay()
        }
    }
    return Demo()
}
