import AppKit
import SwiftUI

/// Estado vazio padronizado do app. Wrapper em torno de
/// `ContentUnavailableView` que força o uso do catálogo `AppIcon` e aplica um
/// tratamento visual consistente ao símbolo (hierárquico + gradiente da brand
/// + variant `.circle.fill` quando existe).
///
/// **Use isto em vez de `ContentUnavailableView` direto.** O wrapper centraliza
/// a linguagem visual e permite trocar o look ou adicionar variantes em um
/// único lugar.
struct EmptyStateView<Actions: View>: View {
    private let title: String
    private let icon: AppIcon
    private let descriptionText: String?
    private let actions: Actions

    init(
        _ title: String,
        icon: AppIcon,
        description: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.icon = icon
        self.descriptionText = description
        self.actions = actions()
    }

    var body: some View {
        // `Label { } icon: { }` (em vez de `Label(_:systemImage:)`) é necessário
        // pra que o `symbolRenderingMode` e o `foregroundStyle` do gradiente se
        // apliquem só à `Image` e não vazem pro título. O `.labelStyle` custom
        // força o tamanho do ícone — sem ele, o `ContentUnavailableView` aplica
        // sua tipografia interna, ignorando `.font` aplicado direto na `Image`.
        ContentUnavailableView {
            Label {
                Text(title)
            } icon: {
                iconView
            }
            .labelStyle(EmptyStateLabelStyle(iconSize: 48))
        } description: {
            if let descriptionText {
                Text(descriptionText)
            }
        } actions: {
            actions
        }
    }

    /// Ícone unificado dos empty states. Três tratamentos sempre aplicados:
    /// — resolve pro variant `.circle.fill` do símbolo quando existe no SF
    ///   Symbols (presença confirmada via `NSImage(systemSymbolName:)`); senão
    ///   mantém o nome original.
    /// — `symbolRenderingMode(.hierarchical)` produz tiers de opacidade na
    ///   camada do símbolo, dando profundidade sem precisar de cores múltiplas.
    /// — `foregroundStyle(.gradient)` em cima do `Color.primary` combina com
    ///   o gradiente das tiers do modo hierárquico.
    /// O tamanho do símbolo é definido no `EmptyStateLabelStyle` (não aqui),
    /// porque `.font` aplicado direto na `Image` é sobreposto pelo
    /// `ContentUnavailableView`.
    private var iconView: some View {
        Image(systemName: Self.resolveSymbol(icon.systemImage))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.primary.gradient)
    }

    /// Procura o variant `.circle.fill` do símbolo. Estratégia em ordem:
    /// 1. Se já termina em `.circle.fill`, é o variant — usa direto.
    /// 2. Tenta `<nome>.circle.fill`.
    /// 3. Se o nome termina em `.fill`, tenta `<base>.circle.fill`.
    /// 4. Sem variant disponível, devolve o nome original.
    /// `NSImage(systemSymbolName:)` valida a existência em tempo de execução —
    /// sem ele, símbolos inexistentes renderizariam vazios silenciosamente.
    /// Resultado é memoizado por nome em `SymbolResolver` — o universo é
    /// finito (`AppIcon`) e a resposta não muda em runtime, então uma única
    /// probe por símbolo basta.
    private static func resolveSymbol(_ name: String) -> String {
        SymbolResolver.resolve(name)
    }
}

/// Resolução cacheada de símbolos SF. Fora da `EmptyStateView` porque tipos
/// genéricos não suportam `static var` armazenado. Acesso é MainActor — bodies
/// SwiftUI rodam no MainActor.
@MainActor
private enum SymbolResolver {
    private static var cache: [String: String] = [:]

    static func resolve(_ name: String) -> String {
        if let cached = cache[name] {
            return cached
        }
        let resolved = compute(name)
        cache[name] = resolved
        return resolved
    }

    private static func compute(_ name: String) -> String {
        if name.hasSuffix(".circle.fill") {
            return name
        }
        var candidates = ["\(name).circle.fill"]
        if name.hasSuffix(".fill") {
            candidates.append("\(name.dropLast(5)).circle.fill")
        }
        for candidate in candidates where exists(candidate) {
            return candidate
        }
        return name
    }

    private static func exists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}

// MARK: - LabelStyle

/// `LabelStyle` que reempilha ícone + título verticalmente e força o tamanho
/// do símbolo via `.font`. Necessário porque o `ContentUnavailableView` usa um
/// `LabelStyle` interno que sobrepõe `.font` aplicado diretamente na `Image`
/// dentro do slot `icon:` — sem custom style, o ícone fica proporcional ao
/// título e qualquer `.font` na `Image` é ignorada.
private struct EmptyStateLabelStyle: LabelStyle {
    let iconSize: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 12) {
            configuration.icon
                .font(.system(size: iconSize, weight: .bold))
            configuration.title
        }
    }
}

// MARK: - Conveniência sem actions

extension EmptyStateView where Actions == EmptyView {
    init(
        _ title: String,
        icon: AppIcon,
        description: String? = nil
    ) {
        self.init(title, icon: icon, description: description) {
            EmptyView()
        }
    }
}
