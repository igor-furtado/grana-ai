import SwiftUI

/// Indicador horizontal de etapas pra wizards multi-step (ex: import).
///
/// Cada step tem três estados visuais:
/// - **completed**: círculo preenchido com `accent`, número branco.
/// - **current**: círculo preenchido com `accent`, número branco, label em peso médio.
/// - **pending**: círculo com borda cinza, número cinza, label `.secondary`.
///
/// Conectores entre os steps acompanham a cor do step à esquerda — concluído
/// = `accent`, pendente = cinza fraco.
struct WizardStepper: View {
    let steps: [String]
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, label in
                step(index: index, label: label)
                if index < steps.count - 1 {
                    connector(isCompleted: index < currentIndex)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.background.secondary)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private func step(index: Int, label: String) -> some View {
        let state = state(for: index)
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(state == .pending ? Color.clear : Color.accentColor)
                    .frame(width: 22, height: 22)
                Circle()
                    .strokeBorder(
                        state == .pending ? Color.secondary.opacity(0.4) : Color.accentColor,
                        lineWidth: 1.5
                    )
                    .frame(width: 22, height: 22)
                if state == .completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(index + 1)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(state == .current ? .white : .secondary)
                }
            }
            Text(label)
                .font(.callout.weight(state == .current ? .semibold : .regular))
                .foregroundStyle(state == .pending ? .secondary : .primary)
        }
    }

    private func connector(isCompleted: Bool) -> some View {
        Rectangle()
            .fill(isCompleted ? Color.accentColor : Color.secondary.opacity(0.25))
            .frame(height: 1.5)
            .frame(maxWidth: .infinity)
    }

    private enum StepState { case completed, current, pending }

    private func state(for index: Int) -> StepState {
        if index < currentIndex { return .completed }
        if index == currentIndex { return .current }
        return .pending
    }
}

#Preview("Step 1 de 3") {
    VStack(spacing: 0) {
        WizardStepper(steps: ["Revisar", "Categorizar", "Concluir"], currentIndex: 0)
        Color.gray.opacity(0.05).frame(height: 200)
    }
    .frame(width: 700)
}

#Preview("Step 2 de 3") {
    VStack(spacing: 0) {
        WizardStepper(steps: ["Revisar", "Categorizar", "Concluir"], currentIndex: 1)
        Color.gray.opacity(0.05).frame(height: 200)
    }
    .frame(width: 700)
}

#Preview("Step 3 de 3") {
    VStack(spacing: 0) {
        WizardStepper(steps: ["Revisar", "Categorizar", "Concluir"], currentIndex: 2)
        Color.gray.opacity(0.05).frame(height: 200)
    }
    .frame(width: 700)
}
