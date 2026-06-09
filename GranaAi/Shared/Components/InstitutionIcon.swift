import AppKit
import SwiftUI

/// Avatar quadrado da instituição: fundo na cor da marca, cantos arredondados
/// e o logo (asset do catálogo) centralizado com padding interno. Quando o
/// asset não está cadastrado, cai num SF Symbol genérico como fallback.
///
/// O `cornerRadius` e o `padding` escalam proporcionalmente ao `size` para
/// manter a mesma proporção visual em qualquer tamanho — basta passar `size`.
///
/// **Como adicionar um logo real:**
/// 1. Adquira o logo da marca (PNG transparente ou SVG).
/// 2. Arraste pra `Resources/Assets.xcassets` com o nome retornado por
///    `InstitutionKind.logoAssetName` (ex: `inter-logo`).
/// 3. Rebuild — o asset entra no lugar do SF Symbol automaticamente.
struct InstitutionIcon: View {
    let kind: InstitutionKind
    var size: CGFloat = 40

    private var cornerRadius: CGFloat {
        size * 0.22
    }

    private var padding: CGFloat {
        size * 0.16
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(kind.brandColor)
            .frame(width: size, height: size)
            .overlay {
                logo
                    .padding(padding)
            }
    }

    // `NSImage(named:)` em runtime: SwiftUI não tem API pra "este asset existe?".
    // Resolve no asset catalog do bundle principal e retorna `nil` se não achar.
    // Barato (macOS cacheia) e dá fallback gracioso sem warnings de build.
    @ViewBuilder
    private var logo: some View {
        if let assetName = kind.logoAssetName, NSImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: kind.systemImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.white)
        }
    }
}
