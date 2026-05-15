import AppKit
import Foundation
import SwiftUI

/// Campo monetário estilo "calculadora": guarda em centavos (Int) e
/// formata em BRL automaticamente. O usuário só digita números —
/// vírgula e separador de milhar aparecem em tempo real.
///
/// **Por que NSViewRepresentable em vez de `TextField` puro:**
/// `NSTextField` usa um *field editor* interno durante a edição. Atribuir
/// `stringValue` via Binding SwiftUI atualiza o source, mas o field editor
/// só re-lê quando perde o foco — daí o "formata só no blur" que aparece
/// no `TextField` puro. Interceptando `controlTextDidChange` no delegate
/// conseguimos reescrever o conteúdo do field editor a cada tecla.
struct CurrencyField: View {
    @Binding var cents: Int
    var placeholder: String = "R$ 0,00"

    var body: some View {
        CurrencyTextField(cents: $cents, placeholder: placeholder)
            // NSTextField default tem altura ~22; deixa parecido com TextField nativo.
            .frame(height: 22)
    }
}

/// Formatação reaproveitável (usada também na exibição read-only).
enum CurrencyFormat {
    static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.numberStyle = .currency
        f.currencyCode = "BRL"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    static func format(_ cents: Int) -> String {
        let decimal = Decimal(cents) / 100
        return formatter.string(from: decimal as NSDecimalNumber) ?? "R$ 0,00"
    }
}

struct CurrencyTextField: NSViewRepresentable {
    @Binding var cents: Int
    let placeholder: String

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.delegate = context.coordinator
        tf.placeholderString = placeholder
        tf.alignment = .right
        // Sem borda nem fundo: combina com as demais linhas do Form, que são
        // controles plain separados por hairlines.
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.stringValue = CurrencyFormat.format(cents)
        return tf
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        // Só sobrescreve quando o usuário NÃO está editando — caso contrário,
        // re-renders do SwiftUI pisariam por cima do que ele acabou de digitar.
        guard !context.coordinator.isEditing else { return }
        let expected = CurrencyFormat.format(cents)
        if nsView.stringValue != expected {
            nsView.stringValue = expected
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CurrencyTextField
        var isEditing = false

        init(parent: CurrencyTextField) { self.parent = parent }

        func controlTextDidBeginEditing(_ obj: Notification) { isEditing = true }
        func controlTextDidEndEditing(_ obj: Notification) { isEditing = false }

        /// Dispara a cada keystroke. Pegamos o conteúdo do field editor,
        /// extraímos só os dígitos, reformatamos, e reescrevemos — assim o
        /// usuário vê "R$ 0,01 → R$ 0,12 → R$ 1,23" enquanto digita 1, 2, 3.
        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            let digits = tf.stringValue.filter(\.isNumber)
            let newCents = Int(digits) ?? 0
            let formatted = CurrencyFormat.format(newCents)

            if tf.stringValue != formatted {
                tf.stringValue = formatted
                // Cursor sempre no final — input estilo calculadora.
                if let editor = tf.currentEditor() {
                    let end = (formatted as NSString).length
                    editor.selectedRange = NSRange(location: end, length: 0)
                }
            }

            parent.cents = newCents
        }
    }
}

#Preview {
    @Previewable @State var cents = 0
    return Form {
        LabeledContent("Valor") {
            CurrencyField(cents: $cents)
        }
        Text("Centavos: \(cents)")
    }
    .formStyle(.grouped)
    .frame(width: 400, height: 200)
}
