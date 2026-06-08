import Foundation
import SwiftUI

/// Tela "Importações" do menu lateral: lista visual de `ImportBatch` agrupada
/// por período (Hoje / Ontem / Esta semana / Este mês / Mais antigos), com
/// logo da instituição em cada card e botão de desfazer. Toolbar primária
/// abre a `ImportView` em sheet modal.
struct ImportHistoryView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var store: ImportStore?
    @State private var pendingDeleteBatch: ImportBatch?
    @State private var showingImportSheet = false

    var body: some View {
        Group {
            if let store {
                content(store: store)
                    .task { await store.start() }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { store = ImportStore(container: environment.container) }
            }
        }
        .navigationTitle("Importações")
        .navigationSubtitle(importsSubtitle)
        .toolbar {
            // Só renderiza o botão da toolbar quando já existe histórico — no
            // empty state o CTA principal vive no centro da tela, então repetir
            // o ícone aqui é redundante.
            if let store, !store.batches.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingImportSheet = true
                    } label: {
                        Label("Importar extrato", systemImage: AppIcon.importFile.systemImage)
                    }
                }
            }
        }
        .sheet(isPresented: $showingImportSheet) {
            ImportView()
                .environment(environment)
        }
    }

    private var importsSubtitle: String {
        guard let store, !store.batches.isEmpty else { return "" }
        let totalRows = store.batches.reduce(0) { $0 + $1.rowCount }
        let lots = store.batches.count
        let txWord = totalRows == 1 ? "transação" : "transações"
        let lotWord = lots == 1 ? "importação" : "importações"
        return "\(totalRows) \(txWord) em \(lots) \(lotWord)"
    }

    @ViewBuilder
    private func content(store: ImportStore) -> some View {
        if store.batches.isEmpty {
            ContentUnavailableView {
                Label("Sem importações", systemImage: AppIcon.inbox.systemImage)
            } description: {
                Text("Importe um extrato bancário (OFX) ou fatura de cartão Inter (CSV) para começar.")
            } actions: {
                Button {
                    showingImportSheet = true
                } label: {
                    Label("Importar extrato", systemImage: AppIcon.importFile.systemImage)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
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
                    Text(
                        "As \(batch.rowCount) transações de **\(batch.sourceFilename)** serão removidas permanentemente."
                    )
                }
        }
    }

    private func list(store: ImportStore) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(groupedBatches(store.batches), id: \.bucket) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.bucket.title)
                            .font(.caption.weight(.semibold))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        VStack(spacing: 8) {
                            ForEach(group.batches) { batch in
                                ImportBatchRow(
                                    batch: batch,
                                    accountDisplayName: accountDisplayName(for: batch, store: store),
                                    institution: institution(for: batch, store: store),
                                    onUndo: { pendingDeleteBatch = batch }
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func institution(for batch: ImportBatch, store: ImportStore) -> Institution? {
        guard let account = store.account(for: batch.accountId),
              let id = account.institutionId else { return nil }
        return store.institutions.first { $0.id == id }
    }

    private func accountDisplayName(for batch: ImportBatch, store: ImportStore) -> String? {
        guard let account = store.account(for: batch.accountId) else { return nil }
        return Account.displayName(
            for: account,
            institutions: store.institutions,
            bankAccounts: store.bankDetails,
            creditCards: store.creditCards
        )
    }

    /// Bucketing por janela de tempo relativa, ordenado do mais recente pro
    /// mais antigo dentro de cada bucket. Calendar.current = fuso local
    /// (datas comparadas por dia local, igual ao resto do app).
    private func groupedBatches(_ batches: [ImportBatch]) -> [(bucket: PeriodBucket, batches: [ImportBatch])] {
        let calendar = Calendar.current
        let now = Date()
        let sorted = batches.sorted { $0.importedAt > $1.importedAt }

        var groups: [PeriodBucket: [ImportBatch]] = [:]
        for batch in sorted {
            let bucket = PeriodBucket.bucket(for: batch.importedAt, now: now, calendar: calendar)
            groups[bucket, default: []].append(batch)
        }

        return PeriodBucket.allCases
            .compactMap { bucket in
                guard let batches = groups[bucket], !batches.isEmpty else { return nil }
                return (bucket, batches)
            }
    }
}

// MARK: - Period bucket

private enum PeriodBucket: CaseIterable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case older

    var title: String {
        switch self {
        case .today: "HOJE"
        case .yesterday: "ONTEM"
        case .thisWeek: "ESTA SEMANA"
        case .thisMonth: "ESTE MÊS"
        case .older: "MAIS ANTIGOS"
        }
    }

    static func bucket(for date: Date, now: Date, calendar: Calendar) -> PeriodBucket {
        if calendar.isDateInToday(date) { return .today }
        if calendar.isDateInYesterday(date) { return .yesterday }
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) { return .thisWeek }
        if calendar.isDate(date, equalTo: now, toGranularity: .month) { return .thisMonth }
        return .older
    }
}

// MARK: - Row

private struct ImportBatchRow: View {
    let batch: ImportBatch
    let accountDisplayName: String?
    let institution: Institution?
    let onUndo: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            iconView

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(batch.rowCount) \(batch.rowCount == 1 ? "transação" : "transações")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(batch.sourceFilename)

            Button(role: .destructive, action: onUndo) {
                Label("Desfazer", systemImage: AppIcon.undo.systemImage)
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(.danger)
            .opacity(isHovered ? 1 : 0.7)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .contextMenu {
            Button("Desfazer importação", role: .destructive, action: onUndo)
        }
    }

    @ViewBuilder
    private var iconView: some View {
        if let institution {
            InstitutionIcon(kind: institution.kind, size: 40)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Título derivado do filename — quando óbvio (`fatura`/`extrato`),
    /// nomeia o tipo de import. Caso contrário, usa o filename sem extensão.
    private var title: String {
        let lower = batch.sourceFilename.lowercased()
        if lower.contains("fatura") { return "Fatura" }
        if lower.contains("extrato") { return "Extrato" }
        return (batch.sourceFilename as NSString).deletingPathExtension
    }

    /// Filename não entra aqui — já está no `.help(...)` do card (tooltip),
    /// evitando duplicar com o título quando ele cai no fallback "filename
    /// sem extensão".
    private var subtitle: String {
        var parts: [String] = []
        if let accountDisplayName {
            parts.append(accountDisplayName)
        }
        parts.append(Self.dateFormatter.string(from: batch.importedAt))
        return parts.joined(separator: " · ")
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f
    }()
}

#Preview {
    NavigationStack { ImportHistoryView() }
        .environment(AppEnvironment())
        .frame(width: 900, height: 600)
}
