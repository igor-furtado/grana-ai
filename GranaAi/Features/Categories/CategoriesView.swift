import Foundation
import OSLog
import SwiftUI

/// Inspeção read-only da taxonomia de categorias (raízes + subcategorias).
///
/// Categorias hoje são **seed estático** — usuário não cria nem edita. Esta
/// tela existe pra visibilidade: ver o que foi cadastrado, qual ícone/cor
/// tem cada raiz, e quais subs caem sob ela. Quando o roadmap permitir
/// edição, esta vira a tela de CRUD.
///
/// **Decisão visual:** uma seção/tabela por `CategoryKind` (Receitas,
/// Despesas, Transferências). Separar por tipo é mais útil pro usuário do
/// que uma tabela única — financeiro mentaliza "o que gasto" separado de
/// "o que recebo". Cor do header espelha o token usado em transações
/// (`.income` / `.expense` / `.transfer`), mantendo coerência cromática
/// com o Dashboard e a lista de transactions.
struct CategoriesView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var categories: [Category] = []
    @State private var loadError: Error?

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView {
                    Label("Erro ao carregar categorias", systemImage: AppIcon.warning.systemImage)
                } description: {
                    Text(loadError.localizedDescription)
                }
            } else if categories.isEmpty {
                ProgressView()
            } else {
                grouped
            }
        }
        .navigationTitle("Categorias")
        .task { await watch() }
    }

    @ViewBuilder
    private var grouped: some View {
        // Um único pass sobre `categories` agrupando por kind, em vez de
        // três `filter` separados nas 3 chamadas de buildRows. Vale pouco
        // pra ~163 categorias do seed, mas evita degradação se o roadmap
        // permitir o usuário criar categorias custom.
        let byKind = Dictionary(grouping: categories, by: \.kind)
        let income   = makeBucket(from: byKind[.income]   ?? [])
        let expense  = makeBucket(from: byKind[.expense]  ?? [])
        let transfer = makeBucket(from: byKind[.transfer] ?? [])

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                kindBlock("Receitas",       bucket: income,   color: .income)
                kindBlock("Despesas",       bucket: expense,  color: .expense)
                kindBlock("Transferências", bucket: transfer, color: .transfer)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Bloco "header + tabela" pra um kind. Construído com `VStack` de
    /// `HStack`s em vez de `Table` nativa: `Table` é virtualizada e não
    /// declara intrinsic height — embedded num `ScrollView` ela só renderiza
    /// se receber `.frame(height:)` explícita, o que exigia estimar altura
    /// linha por linha (frágil; sobrava placeholder cinza). `VStack` tem
    /// intrinsic size real, shrink-wrappa sozinho.
    ///
    /// Trade-off: perdemos resize de coluna e header clicável que `Table`
    /// dá de graça. Pra uma tela read-only de inspeção isso não custa nada.
    @ViewBuilder
    private func kindBlock(_ title: String, bucket: KindBucket, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // `bucket.rootCount` é calculado uma vez em `makeBucket`,
            // não recomputado a cada render.
            kindHeader(title, count: bucket.rootCount, color: color)

            VStack(spacing: 0) {
                tableHeader
                Divider()
                ForEach(Array(bucket.rows.enumerated()), id: \.element.id) { index, row in
                    tableRow(row, striped: !index.isMultiple(of: 2))
                }
            }
            .background(Color.brandPrimary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("Ícone")
                .frame(width: Self.iconColumnWidth, alignment: .leading)
            Text("Categoria")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Cor")
                .frame(width: Self.colorColumnWidth, alignment: .leading)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, Self.rowHorizontalPadding)
        .padding(.vertical, 8)
    }

    private func tableRow(_ row: CategoryRow, striped: Bool) -> some View {
        HStack(spacing: 0) {
            IconCell(row: row)
                .frame(width: Self.iconColumnWidth, alignment: .leading)

            NameCell(row: row)
                .frame(maxWidth: .infinity, alignment: .leading)

            ColorSwatch(row: row)
                .frame(width: Self.colorColumnWidth, alignment: .leading)
        }
        .padding(.horizontal, Self.rowHorizontalPadding)
        .padding(.vertical, 4)
        .background(striped ? Color.primary.opacity(0.03) : Color.clear)
    }

    private func kindHeader(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(title)
                .font(.title2.weight(.semibold))
            Text("(\(count))")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private static let iconColumnWidth: CGFloat      = 56
    private static let colorColumnWidth: CGFloat     = 80
    private static let rowHorizontalPadding: CGFloat = 12

    /// Achata a hierarquia raiz→subs (já filtradas por kind pelo caller)
    /// numa lista linear: cada raiz vem seguida das próprias subs
    /// alfabéticas. Devolve `KindBucket` pra entregar a `rootCount`
    /// já calculada — evita o consumidor refazer o filter.
    private func makeBucket(from inKind: [Category]) -> KindBucket {
        let roots = inKind
            .filter { $0.parentId == nil }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }

        // Agrupar subs por parentId pra evitar O(n²) ao montar a lista.
        let subsByParent = Dictionary(
            grouping: inKind.filter { $0.parentId != nil },
            by: { $0.parentId! }
        )

        var out: [CategoryRow] = []
        for root in roots {
            let subs = (subsByParent[root.id] ?? [])
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            out.append(CategoryRow(category: root, parent: nil, subCount: subs.count))
            for sub in subs {
                out.append(CategoryRow(category: sub, parent: root))
            }
        }
        return KindBucket(rows: out, rootCount: roots.count)
    }

    /// Stream reativa do banco. Usa `watch` (não `getAll`) pra refletir
    /// imediatamente quando a Fase futura abrir edição de categoria.
    private func watch() async {
        do {
            for try await rows in try environment.container.categories.watchAll() {
                self.categories = rows
            }
        } catch is CancellationError {
            // .task cancelado pela SwiftUI — comportamento esperado.
        } catch {
            self.loadError = error
            ErrorCenter.shared.report(error)
        }
    }
}

/// Tudo que `kindBlock`/`kindSection` precisam pra renderizar uma seção
/// de kind: a lista achatada de rows + a quantidade de raízes (mostrada no
/// header como "Despesas (14)"). Empacotar evita o consumidor recontar
/// raízes a cada render.
private struct KindBucket {
    let rows: [CategoryRow]
    let rootCount: Int
}

/// Linha achatada: a categoria + seu pai resolvido (nil pra raiz). Manter
/// o `parent` no row evita um lookup `categories.first { $0.id == ... }`
/// pra cada célula renderizada.
///
/// `subCount` só é preenchido pras raízes (sub sempre = 0). Calculado em
/// `buildRows` no mesmo loop que monta a lista — evita um segundo pass na
/// hora de renderizar a `NameCell`.
private struct CategoryRow: Identifiable {
    let category: Category
    let parent: Category?
    let subCount: Int

    init(category: Category, parent: Category?, subCount: Int = 0) {
        self.category = category
        self.parent = parent
        self.subCount = subCount
    }

    var id: UUID { category.id }
    var isRoot: Bool { parent == nil }

    /// Ícone "efetivo": se for raiz, usa o próprio; se for sub, herda do pai.
    var effectiveIcon: CategoryIcon? {
        category.icon ?? parent?.icon
    }
}

/// Ícone tingido pela cor da categoria. Sub fica com opacity reduzida pra
/// indicar visualmente que herda do pai (sem precisar de indentação).
private struct IconCell: View {
    let row: CategoryRow

    var body: some View {
        if let icon = row.effectiveIcon {
            Image(systemName: icon.systemImage)
                .foregroundStyle(icon.color.opacity(row.isRoot ? 1.0 : 0.55))
                .font(.title3)
        } else {
            Color.clear
                .frame(width: 22, height: 22)
        }
    }
}

/// Nome da categoria. Raiz em destaque (title3 + semibold), sub em estilo
/// mais discreto. Raiz com subs ganha `(N)` discreto à direita pra dar
/// noção rápida de quão "grande" é o grupo.
private struct NameCell: View {
    let row: CategoryRow

    var body: some View {
        HStack(spacing: 6) {
            Text(row.category.name)
                .font(row.isRoot ? .title3 : .body)
                .fontWeight(row.isRoot ? .semibold : .regular)
                .foregroundStyle(.primary.opacity(row.isRoot ? 1.0 : 0.75))
                .lineLimit(1)

            if row.isRoot && row.subCount > 0 {
                Text("(\(row.subCount))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Badge retangular preenchido com a cor da categoria, com borda fina pra
/// separar visualmente do fundo da row (importante em tons claros como o
/// amarelo da paleta). Sub aparece com a mesma cor mas opacity reduzida,
/// pareando o tratamento do `IconCell`.
private struct ColorSwatch: View {
    let row: CategoryRow

    private static let cornerRadius: CGFloat = 4

    var body: some View {
        if let icon = row.effectiveIcon {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(icon.color.opacity(row.isRoot ? 1.0 : 0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .stroke(Color.primary.opacity(0.25), lineWidth: 0.5)
                )
                .frame(width: 44, height: 18)
        } else {
            Color.clear
                .frame(width: 44, height: 18)
        }
    }
}

#Preview {
    NavigationStack {
        CategoriesView()
            .environment(AppEnvironment())
    }
    .frame(width: 760, height: 700)
}
