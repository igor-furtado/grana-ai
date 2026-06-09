import SwiftUI

/// Step de revisão do OFX: cards de "Conta de destino" (um por `STMTRS`) +
/// lista de transações com checkboxes. Botão primário avança pra
/// categorização pré-commit.
struct OFXReviewStepView: View {
    @Bindable var store: ImportStore
    let dismiss: DismissAction

    private var totalSelected: Int {
        store.ofxResolutions.reduce(0) { $0 + $1.rows.filter(\.selected).count }
    }

    private var allAccountsSelected: Bool {
        store.ofxResolutions.allSatisfy { $0.accountId != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Conta de destino: renderizada FORA do List como `Form { Section }`
            // nativo, pra ter o visual exato das telas Nova conta / Nova
            // transação. Pode ser uma ou múltiplas (multi-statement OFX);
            // empilhadas verticalmente. Sem padding horizontal externo — o
            // Form `.grouped` já entrega seu próprio recuo lateral.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(store.ofxResolutions.indices, id: \.self) { idx in
                    OFXAccountInfoCard(store: store, statementIndex: idx)
                }
            }

            OFXTransactionsListCard(
                resolutions: $store.ofxResolutions,
                showsBankInHeader: store.ofxResolutions.count > 1,
                bankKind: { accountId in bankKind(for: accountId) }
            )

            BottomActionBar(caption: selectionCaption) {
                Button("Fechar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Avançar com \(totalSelected) \(totalSelected == 1 ? "transação" : "transações")") {
                    Task { await store.confirmOFXImport() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(totalSelected == 0 || !allAccountsSelected)
            }
        }
        .navigationSubtitle(store.sourceURL?.lastPathComponent ?? "")
    }

    /// Caption só pra bloqueios. Stats de seleção viraram redundância com o
    /// header da lista + o label do botão primário ("Avançar com N").
    private var selectionCaption: String? {
        allAccountsSelected ? nil : "Escolha a conta de destino de cada extrato"
    }

    /// Resolve o `InstitutionKind` da conta selecionada pra exibir o logo na
    /// row. Devolve `nil` se a conta ainda não foi escolhida ou a instituição
    /// não tem `kind` mapeado.
    private func bankKind(for accountId: UUID?) -> InstitutionKind? {
        guard let accountId,
              let account = store.accounts.first(where: { $0.id == accountId }),
              let institutionId = account.institutionId,
              let institution = store.institutions.first(where: { $0.id == institutionId })
        else { return nil }
        return institution.kind
    }
}

// MARK: - Account info card

/// Card de "Conta de destino" renderizado FORA do `List` — usa `Form { Section }`
/// nativo do macOS pra ter o visual grouped exato das telas Nova conta / Nova
/// transação.
///
/// A partir da Fase 4.5 o import **não cria contas** — só seleciona uma
/// existente. Banco/Conta exibidos no card vêm do OFX (apenas leitura, ajudam
/// o usuário a identificar qual das contas cadastradas é). O picker é
/// obrigatório quando o auto-detect não acha; quando acha, vem pré-preenchido
/// com badge "Detectada".
private struct OFXAccountInfoCard: View {
    @Bindable var store: ImportStore
    let statementIndex: Int

    private var resolution: OFXStatementResolution? {
        store.ofxResolutions.indices.contains(statementIndex)
            ? store.ofxResolutions[statementIndex]
            : nil
    }

    var body: some View {
        Form {
            Section {
                if let resolution {
                    LabeledContent("Banco (do extrato)") {
                        Text(resolution.ofxBankLabel)
                    }
                    LabeledContent("Conta (do extrato)") {
                        Text(resolution.ofxAccountLabel)
                    }
                    Picker(
                        "Conta de destino",
                        selection: Binding(
                            get: { resolution.accountId },
                            set: { newValue in
                                Task { await store.setOFXAccount(statementIndex: statementIndex, to: newValue) }
                            }
                        )
                    ) {
                        Text("Selecione…").tag(UUID?.none)
                        ForEach(availableAccounts) { account in
                            Text(label(for: account)).tag(UUID?.some(account.id))
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Conta de destino")
                    Spacer()
                    if let resolution {
                        statusBadge(for: resolution)
                    }
                }
            }
        }
        .formStyle(.grouped)
        // Form grouped scrolla por dentro; aqui o conteúdo é fixo, então
        // desabilita o scroll pra integrar com o `ScrollView`/layout pai.
        .scrollDisabled(true)
        // Altura do card é ditada pelo conteúdo (4–5 rows). `fixedSize` no
        // eixo vertical evita o Form esticar pra preencher espaço sobrando.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Contas elegíveis como destino do import. Arquivadas ficam fora de
    /// propósito — o usuário tirou do dia-a-dia e importar pra elas seria
    /// inesperado. Quem precisa importar tem que desarquivar primeiro.
    private var availableAccounts: [Account] {
        store.accounts
            .filter { !$0.archived }
            .sorted { label(for: $0).localizedCaseInsensitiveCompare(label(for: $1)) == .orderedAscending }
    }

    private func label(for account: Account) -> String {
        Account.displayName(
            for: account,
            institutions: store.institutions,
            bankAccounts: store.bankDetails,
            creditCards: store.creditCards
        )
    }

    @ViewBuilder
    private func statusBadge(for resolution: OFXStatementResolution) -> some View {
        if resolution.accountId == nil {
            Text("Escolha")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.warning.opacity(0.18))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
                .textCase(nil)
        } else if resolution.wasAutoDetected {
            Text("Detectada")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.success.opacity(0.15))
                .foregroundStyle(.success)
                .clipShape(Capsule())
                .textCase(nil)
        }
    }
}

// MARK: - Transactions list card

/// Section de transações dentro do `List` (virtualizado). Sem pickers de
/// categoria — Fase 4 moveu categorização pro step seguinte.
///
/// `showsBankInHeader` adiciona o nome do banco no título quando há múltiplos
/// statements no mesmo arquivo, pra usuário saber a qual conta o bloco pertence.
/// Card de transações que usa `Form { Section }` com **uma única row**
/// contendo um `ScrollView { LazyVStack }`. O Form entrega o visual nativo de
/// card grouped (igual à `OFXAccountInfoCard`); a LazyVStack interna mantém a
/// virtualização real das transações (só renderiza o viewport).
///
/// Sutileza: Form normalmente não virtualiza rows de uma Section, mas como
/// **temos uma única row** (o ScrollView), Form materializa só ela e a
/// laziness fica por conta da LazyVStack dentro do ScrollView.
private struct OFXTransactionsListCard: View {
    @Binding var resolutions: [OFXStatementResolution]
    let showsBankInHeader: Bool
    let bankKind: (UUID?) -> InstitutionKind?

    private var totalRows: Int {
        resolutions.reduce(0) { $0 + $1.rows.count }
    }

    private var selectedCount: Int {
        resolutions.reduce(0) { $0 + $1.rows.filter(\.selected).count }
    }

    private var duplicateCount: Int {
        resolutions.reduce(0) { $0 + $1.rows.filter(\.isDuplicate).count }
    }

    private var allSelected: Bool {
        let rows = resolutions.flatMap(\.rows)
        return !rows.isEmpty && rows.allSatisfy(\.selected)
    }

    var body: some View {
        Form {
            Section {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        TransactionsSelectionRow(
                            summary: selectionSummary,
                            allSelected: allSelected,
                            onToggleAll: toggleAll(to:)
                        )
                        Divider()
                        ForEach($resolutions) { $resolution in
                            if showsBankInHeader {
                                bankSubheader(for: resolution)
                            }
                            let kind = bankKind(resolution.accountId)
                            ForEach($resolution.rows) { $row in
                                OFXRowView(row: $row, institutionKind: kind)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                Divider()
                            }
                        }
                    }
                }
                // Remove o padding default que o Form coloca em torno da row
                // — assim a LazyVStack encosta nas bordas do card.
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Transações")
            }
        }
        .formStyle(.grouped)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .frame(maxHeight: .infinity)
    }

    private func bankSubheader(for resolution: OFXStatementResolution) -> some View {
        HStack {
            Text(bankName(for: resolution))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
    }

    private func bankName(for resolution: OFXStatementResolution) -> String {
        resolution.ofxBankLabel
    }

    private func toggleAll(to value: Bool) {
        for resIdx in resolutions.indices {
            for rowIdx in resolutions[resIdx].rows.indices {
                resolutions[resIdx].rows[rowIdx].selected = value
            }
        }
    }

    private var selectionSummary: String {
        var parts = ["\(selectedCount) de \(totalRows) selecionadas"]
        if duplicateCount > 0 {
            parts.append("\(duplicateCount) \(duplicateCount == 1 ? "duplicada" : "duplicadas")")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Row

/// Wrapper fino que mapeia `OFXPreviewRow` → `TransactionRow.importPreview`.
private struct OFXRowView: View {
    @Binding var row: OFXPreviewRow
    let institutionKind: InstitutionKind?

    var body: some View {
        // OFX mistura entradas e saídas no mesmo statement (PIX recebido +
        // débito da fatura, p.ex.); colorir por direção ajuda a ler. Sinal
        // do `derived.amount` vem direto do TRNTYPE do OFX.
        TransactionRow(
            selection: $row.selected,
            institutionKind: institutionKind,
            description: primaryDescription,
            memo: nil,
            date: row.derived.occurredAt,
            amount: row.derived.amount,
            amountKind: row.derived.amount < 0 ? .outgoing : .incoming,
            status: row.isDuplicate ? .duplicate : nil
        )
    }

    private var primaryDescription: String {
        // NAME geralmente é a contraparte ("Igor Talisson..."); MEMO traz
        // detalhe técnico ("Pix recebido: Cp :..."). Mostrar NAME — MEMO
        // some pra minimizar ruído visual.
        if let name = row.raw.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty
        {
            return name
        }
        return row.derived.description
    }
}
