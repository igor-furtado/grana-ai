import SwiftUI

/// Preferência de tema do app. Persistida em `UserDefaults` via `@AppStorage`
/// — sobrevive entre execuções sem precisar tocar no `AppEnvironment`.
///
/// O caso `.system` (default) deixa o app seguir o tema do macOS, que é
/// a expectativa nativa de qualquer app desktop Apple.
enum AppColorScheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "Sistema"
        case .light:  "Claro"
        case .dark:   "Escuro"
        }
    }

    /// `nil` significa "deixa o sistema decidir" — é o que o
    /// `.preferredColorScheme(_:)` espera pra desligar o override.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }
}

/// Picker do tema (Sistema / Claro / Escuro). Vive sob "Configurações > Tema"
/// na sidebar/hub. Conteúdo intencionalmente enxuto — outras preferências
/// (notificações, formato de data, etc.) entram em telas próprias quando o
/// roadmap pedir, e não num "balcão" único.
struct ThemeView: View {
    /// A mesma chave é lida pelo `ContentView` pra aplicar
    /// `.preferredColorScheme` no root — qualquer mudança aqui reflete
    /// instantâneamente no app inteiro.
    @AppStorage("appColorScheme") private var appColorScheme: AppColorScheme = .system

    var body: some View {
        Form {
            Section("Aparência") {
                Picker("Tema", selection: $appColorScheme) {
                    ForEach(AppColorScheme.allCases) { scheme in
                        Text(scheme.displayName).tag(scheme)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Tema")
        .navigationSubtitle("Aparência do app (claro, escuro ou sistema)")
    }
}

#Preview {
    NavigationStack {
        ThemeView()
    }
    .frame(width: 600, height: 400)
}
