import Foundation
import SwiftUI

/// Tela "Importações" do menu lateral: lista de `ImportBatch` ordenada por
/// data de importação, com ação de desfazer (apaga o batch + cascade nas
/// transactions). Também tem botão pra iniciar uma nova importação na
/// própria toolbar.
struct ImportHistoryView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var store: ImportStore?
    @State private var pendingDeleteBatch: ImportBatch?
    @State private var showingImportSheet = false

    var body: some View {
        Group {
            if let store {
                content(store: store)
                    .task { await store.loadInitialData() }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { store = ImportStore(database: environment.database) }
            }
        }
        .navigationTitle("Importações")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingImportSheet = true
                } label: {
                    Label("Importar OFX", systemImage: AppIcon.importFile.systemImage)
                }
            }
        }
        .sheet(isPresented: $showingImportSheet) {
            ImportView()
                .environment(environment)
        }
    }

    @ViewBuilder
    private func content(store: ImportStore) -> some View {
        if store.batches.isEmpty {
            ContentUnavailableView(
                "Sem importações",
                systemImage: AppIcon.inbox.systemImage,
                description: Text("Toque no ícone de importação na barra superior para importar um extrato bancário.")
            )
        } else {
            list(store: store)
                .confirmationDialog(
                    "Desfazer importação?",
                    isPresented: Binding(
                        get: { pendingDeleteBatch != nil },
                        set: { if !$0 { pendingDeleteBatch = nil } }
                    ),
                    presenting: pendingDeleteBatch
                ) { batch in
                    Button("Apagar lote (\(batch.rowCount) transações)", role: .destructive) {
                        Task {
                            await store.undo(batchId: batch.id)
                            pendingDeleteBatch = nil
                        }
                    }
                    Button("Cancelar", role: .cancel) { pendingDeleteBatch = nil }
                } message: { batch in
                    Text("As \(batch.rowCount) transações de **\(batch.sourceFilename)** serão removidas permanentemente.")
                }
        }
    }

    @ViewBuilder
    private func list(store: ImportStore) -> some View {
        Table(store.batches) {
            TableColumn("Arquivo") { batch in
                Text(batch.sourceFilename)
            }
            TableColumn("Conta") { batch in
                Text(store.account(for: batch.accountId)?.name ?? "—")
            }
            TableColumn("Formato") { batch in
                Text(batch.sourceKind.displayName)
            }
            .width(80)
            TableColumn("Linhas") { batch in
                Text("\(batch.rowCount)").monospacedDigit()
            }
            .width(60)
            TableColumn("Importado em") { batch in
                Text(batch.importedAt, style: .date)
            }
            .width(120)
            TableColumn("") { batch in
                Button(role: .destructive) {
                    pendingDeleteBatch = batch
                } label: {
                    Label("Desfazer", systemImage: AppIcon.undo.systemImage)
                }
            }
            .width(110)
        }
    }
}

#Preview {
    NavigationStack { ImportHistoryView() }
        .environment(AppEnvironment())
}
