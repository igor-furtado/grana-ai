import SwiftUI

/// Hub de Configurações usado no **iPhone** (TabView). Cada item navega pra
/// sua tela própria — Categorias, Contas e Tema. No Mac o equivalente é a
/// `Section("Configurações")` da sidebar em `ContentView`, que aponta
/// direto pras mesmas três telas sem passar por hub.
///
/// Mantido como `SettingsView` (em vez de `SettingsHubView`) porque o ponto
/// de entrada no tab continua sendo "Configurações" — o tipo já comunica
/// que é a tela raiz daquela aba.
struct SettingsView: View {
    var body: some View {
        List {
            NavigationLink {
                CategoriesView()
            } label: {
                Label("Categorias", systemImage: AppSection.categories.systemImage)
            }

            NavigationLink {
                AccountsView()
            } label: {
                Label("Contas", systemImage: AppSection.accounts.systemImage)
            }

            NavigationLink {
                ThemeView()
            } label: {
                Label("Tema", systemImage: AppSection.theme.systemImage)
            }
        }
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
    .environment(AppEnvironment())
}
