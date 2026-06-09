import Foundation
import OSLog
import SwiftUI

/// Inspeção read-only da taxonomia de categorias (raízes + subcategorias).
///
/// Categorias hoje são **seed estático** — usuário não cria nem edita. Esta
/// tela existe pra visibilidade: ver o que foi cadastrado, qual ícone tem
/// cada raiz, e quais subs caem sob ela. Quando o roadmap permitir edição,
/// esta vira a tela de CRUD.
///
/// **Decisão visual:** layout em dois painéis inspirado no app "SF Symbols"
/// da Apple. À esquerda, grid de cards uniformes (ícone destacado + nome) —
/// um item por categoria raiz, seccionados por `CategoryKind`. À direita,
/// inspector exibindo detalhes da categoria selecionada: ícone grande,
/// nome, kind e lista de subcategorias. Cards uniformes mantêm o ritmo
/// visual; subs ficam no inspector pra evitar cards de alturas variáveis.
///
/// Cor da categoria foi propositalmente omitida — decisão pendente sobre
/// como representá-la entra em outra iteração.
struct CategoriesView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var categories: [Category] = []
    @State private var loadError: Error?
    @State private var selectedId: UUID?
    /// Persiste entre sessões — usuário que ocultou o inspector não quer
    /// vê-lo aparecer de novo na próxima vez que abre o app.
    @SceneStorage("CategoriesView.inspector") private var inspectorPresented: Bool = true

    var body: some View {
        Group {
            if let loadError {
                EmptyStateView(
                    "Não foi possível carregar",
                    icon: .warning,
                    description: loadError.localizedDescription
                )
            } else if categories.isEmpty {
                ProgressView()
            } else {
                grid
            }
        }
        .inspector(isPresented: $inspectorPresented) {
            inspector
                .inspectorColumnWidth(min: 220, ideal: 280, max: 360)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    inspectorPresented.toggle()
                } label: {
                    Label("Painel de detalhes", systemImage: AppIcon.inspectorToggle.systemImage)
                }
                .help(inspectorPresented ? "Ocultar painel de detalhes" : "Mostrar painel de detalhes")
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
        .navigationTitle("Categorias")
        .navigationSubtitle(categoriesSubtitle)
        .task { await watch() }
        .onChange(of: rootIds) { _, ids in
            reconcileSelection(rootIds: ids)
        }
    }

    private var categoriesSubtitle: String {
        if categories.isEmpty { return "" }
        let roots = categories.filter { $0.parentId == nil }.count
        return "\(roots) categorias raiz · \(categories.count) totais"
    }

    /// IDs estáveis das raízes pra reconciliação de seleção (`onChange`).
    /// Mapear `category.id` em vez de `category` evita recomputar quando
    /// só um campo muda — só o conjunto de raízes importa pra seleção.
    private var rootIds: [UUID] {
        categories.filter { $0.parentId == nil }.map(\.id)
    }

    @ViewBuilder
    private var grid: some View {
        // Um único pass agrupando por kind, em vez de três `filter` separados.
        let byKind = Dictionary(grouping: categories, by: \.kind)
        let sections: [(CategoryKind, String, Color)] = [
            (.income, "Receitas", .income),
            (.expense, "Despesas", .expense),
            (.transfer, "Transferências", .transfer),
        ]

        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xxxl) {
                ForEach(sections, id: \.0) { kind, title, accent in
                    let groups = makeGroups(from: byKind[kind] ?? [])
                    if !groups.isEmpty {
                        kindSection(title: title, accent: accent, groups: groups)
                    }
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Seção de um kind: cabeçalho com bolinha de cor + título + contagem,
    /// e um `LazyVGrid` adaptativo de cards uniformes.
    private func kindSection(title: String, accent: Color, groups: [CategoryGroup]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(accent)
                    .frame(width: 10, height: 10)
                Text(title)
                    .font(.title2.weight(.semibold))
                Text("(\(groups.count))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Self.gridColumns, alignment: .leading, spacing: Spacing.md) {
                ForEach(groups) { group in
                    CategoryCard(
                        group: group,
                        isSelected: selectedId == group.id,
                        onTap: { selectedId = group.id }
                    )
                }
            }
        }
    }

    private static let gridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 150), spacing: Spacing.md, alignment: .top),
    ]

    @ViewBuilder
    private var inspector: some View {
        if let group = selectedGroup {
            CategoryInspector(group: group)
        } else {
            inspectorPlaceholder
        }
    }

    private var inspectorPlaceholder: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: AppIcon.sidebarCategories.systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Selecione uma categoria")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// `CategoryGroup` referente à seleção atual. Reusa `makeGroups` pra
    /// manter uma única fonte de verdade pra "como se monta um grupo"
    /// (filtragem de raiz + ordenação das subs). Recomputa quando categorias
    /// ou seleção mudam — barato, lista pequena (~30 raízes no seed).
    private var selectedGroup: CategoryGroup? {
        guard let selectedId else { return nil }
        return makeGroups(from: categories).first { $0.id == selectedId }
    }

    /// Achata a hierarquia raiz→subs (já filtradas por kind pelo caller) numa
    /// lista de `CategoryGroup`. Pré-agrupar subs por `parentId` evita O(n²).
    private func makeGroups(from inKind: [Category]) -> [CategoryGroup] {
        let roots = inKind
            .filter { $0.parentId == nil }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }

        let subsByParent = Dictionary(
            grouping: inKind.filter { $0.parentId != nil },
            by: { $0.parentId! }
        )

        return roots.map { root in
            let subs = (subsByParent[root.id] ?? [])
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            return CategoryGroup(root: root, subs: subs)
        }
    }

    /// Mantém uma seleção válida: se nada está selecionado (primeiro load) ou
    /// se a categoria selecionada saiu do conjunto, escolhe a primeira raiz.
    private func reconcileSelection(rootIds: [UUID]) {
        if let selectedId, rootIds.contains(selectedId) {
            return
        }
        selectedId = rootIds.first
    }

    /// Stream reativa do banco. Usa `watch` (não `getAll`) pra refletir
    /// imediatamente quando a Fase futura abrir edição de categoria.
    private func watch() async {
        do {
            for try await rows in try environment.container.categories.watchAll() {
                categories = rows
            }
        } catch is CancellationError {
            // .task cancelado pela SwiftUI — comportamento esperado.
        } catch {
            loadError = error
            NoticeCenter.shared.report(error)
        }
    }
}

/// Raiz + subcategorias dela (já ordenadas alfabeticamente). Encapsula pra
/// evitar consumidores recomputarem/ordenarem subs a cada render.
private struct CategoryGroup: Identifiable {
    let root: Category
    let subs: [Category]

    var id: UUID {
        root.id
    }
}

/// Card uniforme de uma categoria raiz. Altura fixa pra manter ritmo visual
/// da grid — subs vivem no inspector lateral, não no card. Ícone domina
/// (~36pt), nome em peso médio abaixo, centralizado. Sem cor da categoria
/// por ora (decisão pendente). Estado selecionado ganha borda accent.
private struct CategoryCard: View {
    let group: CategoryGroup
    let isSelected: Bool
    let onTap: () -> Void

    private static let cardHeight: CGFloat = 124
    /// Corner radius pareado ao default visual do `GroupBox` no macOS (~8pt
    /// hoje). Mantemos em constante pra que o overlay de seleção case com a
    /// curva da caixa — se a Apple mudar o radius, ajusta aqui.
    private static let selectionCornerRadius: CGFloat = 8

    var body: some View {
        // `Button` em vez de `onTapGesture`: HIG quer área clicável como botão
        // (focus ring nativo, Space/Enter, VoiceOver). `GroupBox` dentro do
        // botão dá o agrupamento visual padrão do sistema; seleção é
        // sinalizada por borda accent overlay (mesmo padrão usado pelo app
        // SF Symbols pra tile selecionada).
        Button(action: onTap) {
            GroupBox {
                VStack(spacing: Spacing.md) {
                    iconView
                        .frame(maxWidth: .infinity)

                    Text(group.root.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Self.cardHeight)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Self.selectionCornerRadius, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group.root.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = group.root.icon {
            Image(systemName: icon.systemImage)
                .font(.system(size: 30, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(icon.color.gradient)
        } else {
            Image(systemName: AppIcon.warning.systemImage)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.tertiary)
        }
    }
}

/// Painel direito de detalhes. Espelha a estrutura do inspector do app SF
/// Symbols: preview grande do ícone no topo, nome, e seções de metadados
/// abaixo — aqui, kind + lista de subcategorias.
private struct CategoryInspector: View {
    let group: CategoryGroup

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                iconHero

                VStack(alignment: .center, spacing: Spacing.xs) {
                    Text(group.root.name)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    kindBadge
                        .frame(maxWidth: .infinity)
                }

                Divider()

                subsSection
            }
            .padding(Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var iconHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )

            if let icon = group.root.icon {
                Image(systemName: icon.systemImage)
                    .font(.system(size: 56, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(icon.color.gradient)
            } else {
                Image(systemName: AppIcon.warning.systemImage)
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var kindBadge: some View {
        let (label, color) = kindMeta
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var kindMeta: (String, Color) {
        switch group.root.kind {
        case .income: ("Receita", .income)
        case .expense: ("Despesa", .expense)
        case .transfer: ("Transferência", .transfer)
        }
    }

    /// Usa `GroupBox` em vez de `RoundedRectangle` manual: dá agrupamento
    /// visual padrão do sistema (label + material backdrop), encaixa bem
    /// dentro do pane do `.inspector()` (que Apple desenhou pra hospedar
    /// exatamente esse tipo de bloco). Mesmo container é usado por
    /// `MetricCard` e pelo `CategoryCard` deste arquivo — sinal do "kind"
    /// migrou de tint de fundo pra accent no ícone.
    private var subsSection: some View {
        GroupBox {
            if group.subs.isEmpty {
                Text("Sem subcategorias cadastradas")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(group.subs) { sub in
                        Text(sub.name)
                            .font(.subheadline)
                            .foregroundStyle(.primary.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Text("Subcategorias")
                Text("(\(group.subs.count))")
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
