import SwiftUI

/// Preferência de tema do app. Persistida em `UserDefaults` via `@AppStorage`
/// — sobrevive entre execuções sem precisar tocar no `AppEnvironment`.
///
/// O caso `.system` (default) deixa o app seguir o tema do sistema
/// operacional, que é a expectativa nativa de macOS/iOS.
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

struct SettingsView: View {
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
                #if os(macOS)
                .pickerStyle(.segmented)
                #endif
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Configurações")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .frame(width: 600, height: 400)
}
