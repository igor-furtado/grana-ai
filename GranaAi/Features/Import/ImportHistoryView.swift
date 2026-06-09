import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Tela "Importações" do menu lateral: lista visual de `ImportBatch` agrupada
/// por período (Hoje / Ontem / Esta semana / Este mês / Mais antigos), com
/// logo da instituição em cada card e botão de desfazer. Toolbar primária
/// abre a `ImportView` em sheet modal.
///
/// **Drag & drop:** a tela inteira é um drop target. Arrastar um arquivo OFX
/// ou CSV pra dentro abre o wizard com o arquivo já carregado, pulando o file
/// picker do sistema. Tipos inválidos viram toast via `NoticeCenter` —
/// usuário não fica olhando uma tela "que não fez nada".
struct ImportHistoryView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var store: ImportStore?
    @State private var pendingDeleteBatch: ImportBatch?
    @State private var importContext: ImportContext?
    @State private var isDropTargeted = false

    /// Wrapper `Identifiable` que carrega o arquivo escolhido (nil = manual)
    /// pra dentro da `.sheet(item:)`. Usamos `.sheet(item:)` em vez de
    /// `.sheet(isPresented:)` porque a versão isPresented tem um race entre
    /// o flag e a URL: dois `@State` mutados em sequência podem ser lidos
    /// pela closure de conteúdo em ordens diferentes, fazendo o wizard
    /// abrir com `initialFile == nil` mesmo após drop bem-sucedido. Com
    /// `.sheet(item:)`, o valor é atômico — quando o sheet abre, o item já
    /// está completo, sem janela pra estado intermediário.
    private struct ImportContext: Identifiable {
        let id = UUID()
        let file: URL?
    }

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
                        presentImportSheet(file: nil)
                    } label: {
                        Label("Importar extrato", systemImage: AppIcon.importFile.systemImage)
                    }
                    .help("Importar extrato bancário (OFX ou CSV)")
                }
            }
        }
        // Drop destination cobre a área inteira da tela — incluindo o empty
        // state e a lista populada. O `isTargeted` dirige o overlay visual.
        .dropDestination(for: URL.self, action: handleDrop, isTargeted: setDropTargeted)
        .overlay {
            if isDropTargeted, !(store?.batches.isEmpty ?? true) {
                // Empty state já tem visual de drop zone permanente — overlay
                // só faz sentido por cima da lista populada.
                DropOverlay()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.18), value: isDropTargeted)
        .sheet(item: $importContext) { context in
            ImportView(initialFile: context.file)
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
            EmptyStateDropZone(
                isHighlighted: isDropTargeted,
                onBrowse: { presentImportSheet(file: nil) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
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

    // MARK: - Drop handling

    private func presentImportSheet(file: URL?) {
        // Atribuição única → `.sheet(item:)` abre com o `file` já capturado
        // dentro do contexto. Sem race entre flag de presença e URL.
        importContext = ImportContext(file: file)
    }

    /// Callback do `.dropDestination`. Roda no main actor. Valida extensão e
    /// abre a sheet com o arquivo pré-carregado; arquivos inválidos viram
    /// toast pelo `NoticeCenter` (sem abrir sheet — não faz sentido entrar no
    /// wizard pra logo cair em failed).
    private func handleDrop(_ urls: [URL], at _: CGPoint) -> Bool {
        guard let url = urls.first else { return false }
        let ext = url.pathExtension.lowercased()

        guard ImportStore.supportedExtensions.contains(ext) else {
            NoticeCenter.shared.report(
                ImportError.unsupportedFormat(extension: ext.isEmpty ? "(sem extensão)" : ext),
                title: "Arquivo não suportado"
            )
            return false
        }

        // Múltiplos arquivos: avisa que vamos importar só o primeiro. O wizard
        // é single-file por design (uma instituição/conta por vez no preview).
        // Vira `.info` (não `.error`): nada falhou, só estamos explicando que
        // o input foi reduzido.
        if urls.count > 1 {
            NoticeCenter.shared.info(
                title: "Vários arquivos soltos",
                message: "Importe um por vez. Abrindo \"\(url.lastPathComponent)\"."
            )
        }

        presentImportSheet(file: url)
        return true
    }

    private func setDropTargeted(_ targeted: Bool) {
        isDropTargeted = targeted
    }
}

// MARK: - Empty state drop zone

/// Empty state da tela de Importações. Diferente de um `ContentUnavailableView`
/// genérico, ele é **o próprio drop target visual** — borda tracejada
/// permanente que se destaca durante o drag-over pra reforçar que arrastar
/// arquivos funciona aqui.
///
/// **Por que não deriva de `EmptyStateView`:** não é um anúncio passivo de
/// vazio — é um drop target interativo com animação e highlight de drag-over,
/// que precisa de vocabulário visual próprio (`symbolEffect`, stroke animado,
/// fill que reage ao `isTargeted`). Caber isso no `EmptyStateView` diluiria
/// as duas APIs.
private struct EmptyStateDropZone: View {
    let isHighlighted: Bool
    let onBrowse: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.brandPrimary.opacity(isHighlighted ? 0.18 : 0.10))
                    .frame(width: 84, height: 84)
                Image(systemName: AppIcon.importFile.systemImage)
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(Color.brandPrimary)
                    .symbolEffect(.bounce, value: isHighlighted)
            }

            VStack(spacing: 6) {
                Text(isHighlighted ? "Solte para importar" : "Arraste e solte para importar")
                    .font(.title3.weight(.semibold))
                    .contentTransition(.opacity)
                Text("Aceita OFX (extrato bancário) ou CSV (fatura Inter). Um arquivo por vez.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            HStack(spacing: 10) {
                Text("ou")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Button {
                    onBrowse()
                } label: {
                    Label("Selecionar arquivo", systemImage: AppIcon.importFile.systemImage)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.brandPrimary.opacity(isHighlighted ? 0.06 : 0.0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    Color.brandPrimary.opacity(isHighlighted ? 0.85 : 0.35),
                    style: StrokeStyle(lineWidth: isHighlighted ? 2 : 1.5, dash: [8, 6])
                )
        )
        .scaleEffect(isHighlighted ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.18), value: isHighlighted)
    }
}

// MARK: - Drop overlay (lista populada)

/// Overlay translúcido que aparece por cima da lista durante o drag-over.
/// Mesma linguagem visual do empty state pra continuidade — o usuário sabe
/// que está soltando "no mesmo lugar" independente do estado da tela.
private struct DropOverlay: View {
    var body: some View {
        ZStack {
            // Material translúcido suaviza o conteúdo embaixo sem escondê-lo
            // por completo — HIG: feedback claro mas não destrutivo.
            Rectangle()
                .fill(.regularMaterial)
                .opacity(0.9)

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.brandPrimary.opacity(0.18))
                        .frame(width: 96, height: 96)
                    Image(systemName: AppIcon.importFile.systemImage)
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(Color.brandPrimary)
                }
                Text("Solte para importar")
                    .font(.title2.weight(.semibold))
                Text("OFX ou CSV")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        Color.brandPrimary.opacity(0.7),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                    )
            )
            .padding(40)
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
