import AppKit
import SwiftUI

/// Renderiza o logo da `InstitutionKind` — usa o asset real do catálogo
/// quando disponível, ou cai num SF Symbol genérico tintado pela cor da
/// marca como fallback.
///
/// **Como adicionar um logo real:**
/// 1. Adquira o logo da marca (PNG transparente ou SVG, idealmente em 3 tamanhos: 1x/2x/3x).
/// 2. Arraste pra `Resources/Assets.xcassets` com o nome retornado por
///    `InstitutionKind.logoAssetName` (ex: `inter-logo`).
/// 3. Rebuild — o asset entra no lugar do SF Symbol automaticamente, sem mexer em código.
///
/// **Por que `NSImage(named:)` em runtime:** SwiftUI não tem API pra "este
/// asset existe?". `NSImage(named:)` resolve no asset catalog do bundle
/// principal e retorna `nil` se não achar. É barato (uma vez por render,
/// macOS cacheia internamente) e dá fallback gracioso sem warnings de build.
struct InstitutionLogoImage: View {
    let kind: InstitutionKind

    var body: some View {
        if let assetName = kind.logoAssetName, hasAsset(named: assetName) {
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            // Fallback: SF Symbol tintado pela cor da marca, com mesmo
            // contentMode pra encaixar no container sem distorcer.
            Image(systemName: kind.systemImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(kind.brandColor)
        }
    }

    private func hasAsset(named name: String) -> Bool {
        NSImage(named: name) != nil
    }
}

#Preview("Catálogo de logos / fallback") {
    HStack(spacing: 16) {
        ForEach(InstitutionKind.supported, id: \.rawValue) { kind in
            VStack(spacing: 6) {
                InstitutionLogoImage(kind: kind)
                    .frame(width: 40, height: 40)
                Text(kind.displayName)
                    .font(.caption2)
            }
        }
    }
    .padding(20)
}
