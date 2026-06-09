import AppKit
import SwiftUI

/// Tela de ações administrativas/destrutivas. Hoje hospeda só o reset do
/// banco local — quando aparecerem mais (limpar cache de IA, reseed, etc.),
/// entram aqui. Vive em Ajustes → Avançado pra ficar discoverável sem
/// poluir o fluxo do dia-a-dia.
struct AdvancedSettingsView: View {
    @State private var showingWipeConfirmation = false

    var body: some View {
        Form {
            Section {
                Button(role: .destructive) {
                    showingWipeConfirmation = true
                } label: {
                    Label("Apagar banco de dados e encerrar app", systemImage: "trash")
                }
            } header: {
                Text("Zona de perigo")
            } footer: {
                Text(
                    "Apaga todas as transações, contas, categorias e histórico de importações. O app é encerrado em seguida; ao reabrir, o banco é recriado vazio com a taxonomia padrão atual."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Avançado")
        .confirmationDialog(
            "Apagar todo o banco local?",
            isPresented: $showingWipeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Apagar e encerrar", role: .destructive) {
                AppContainer.wipeLocalDatabase()
                NSApp.terminate(nil)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Esta ação não pode ser desfeita. Todos os dados locais serão perdidos.")
        }
    }
}
