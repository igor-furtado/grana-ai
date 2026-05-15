# CLAUDE.md

> Guia carregado automaticamente pelo Claude Code em toda sessão neste repositório. Resume **o essencial pra não re-perguntar**. Detalhes longos vão em [PROJECT.md](./PROJECT.md) e [ROADMAP.md](./ROADMAP.md) — leia esses dois quando começar uma feature nova.

---

## O que é

App financeiro pessoal **single-user** macOS. SwiftUI + PowerSync (SQLite local-first) + Supabase (entra na Fase 5).

**Status:** Fases 0–3 ✅ (fundação, CRUD, dashboard, importação CSV/XLSX/OFX). Fases 4+ no [ROADMAP.md](./ROADMAP.md).

## Stack travada

- Swift 5.9+ / SwiftUI / `@Observable` (NUNCA `ObservableObject`)
- PowerSync Swift SDK `1.13.1` exact — produto `PowerSync` estático (não `PowerSyncDynamic` nem `PowerSyncGRDB`)
- CoreXLSX, Swift Charts, URLSession
- Anthropic via HTTP direto (sem SDK); Supabase via `supabase-swift` (auth) — ambos entram em fases futuras
- Target: macOS 26.1+

## Arquitetura num parágrafo

`SwiftUI View → @Observable Store (MainActor) → Repository (any PowerSyncDatabaseProtocol) → PowerSyncDatabase`. Reatividade via `watch()` que devolve `AsyncThrowingStream`. Operações multi-passo críticas (import batch, seed, OFX multi-account) via `writeTransaction` pra atomicidade. Repositories vivem dentro do `AppDatabase` (`database.transactions`, `database.accounts`, ...) — refatorar pra container separado só quando Fase 6 entrar.

## Invariantes que NÃO podem quebrar

1. **Sinal do `amount` é sempre magnitude positiva.** O sinal (entrada/saída) vem do `CategoryKind` da categoria. Importadores normalizam via `abs()` antes de inserir. Quebrar isso quebra todas as agregações do dashboard.
2. **Dinheiro em `Decimal`** no Swift, **`Int64` centavos** no banco. NUNCA `Double`. Conversões via `Converters.decimalToCents`/`centsToDecimal`.
3. **Datas em ISO8601 UTC** no banco (`Converters.iso8601` com `.withFractionalSeconds`). Comparação por "dia" usa **`Calendar` local + janela em SQL**, nunca `SUBSTR(occurred_at, 1, 10)` (quebra perto da meia-noite por causa do UTC).
4. **Views nunca tocam SQL** — só Repositories.
5. **Schema do PowerSync não tem NOT NULL.** Obrigatoriedade vive no model Swift (propriedade não-opcional) + lógica de insert. Mappers usam `getString(name:)` (lança em null) vs `getStringOptional(name:)`.
6. **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** está ativo. Mappers `static` dos Repositories, `Converters`, `CategorySeedData` precisam de `nonisolated` pra serem `@Sendable`-compatíveis nos closures do PowerSync.
7. **Transferências (`kind = .transfer`) ficam de fora** dos cards e gráficos do dashboard (PIX enviado + recebido idealmente zeram).

## Convenções de código

- Tipos `PascalCase`, funções `camelCase`, tabelas/colunas `snake_case`.
- Views pequenas (~150 linhas máx). `@State` local pra estado puramente de visualização; `@Observable` Store pra dados do banco.
- `async/await` exclusivamente (Combine só pra código legado, que não tem aqui).
- `#Preview` macro em toda View nova.
- Erros com `enum` por domínio (`DatabaseError`, `ImportError`, etc.) + `LocalizedError` em PT-BR.
- Comentários explicam **por quê**, nunca **o quê**. TODOs com fase: `// TODO(fase-5): ...`.
- Cada arquivo que usa `log.<categoria>.info(...)` precisa `import OSLog` explícito (interpolation da Apple só fica visível no módulo importado).

## Sub-decisões PowerSync (fáceis de quebrar sem saber)

- `PowerSyncDatabase(...)` é **função factory**, não classe. Propriedades declaram tipo `any PowerSyncDatabaseProtocol`.
- `parameters: [(any Sendable)?]` em `db.execute` — prepared statements internos, SQL injection é impossível.
- `watch` re-emite a cada `INSERT`/`UPDATE`/`DELETE` na tabela tocada. Usar pra listas reativas. Usar `getAll` pra snapshots (dashboards, agregações com filtro de período).
- Agregar em SQL (`SUM`, `GROUP BY`) sempre que possível. Exceção: lógica que depende de fuso local (dia da semana, dia local) — `strftime` opera em UTC. Traga colunas mínimas e agregue em Swift com `Calendar`.

## Importação (Fase 3 — entregue)

- **CSV/XLSX**: parser → preview com status por linha → user mapeia colunas → salva template opcional → `writeTransaction` insere batch.
- **OFX**: reader unificado SGML 1.x + XML 2.x, charset CP1252 ou UTF-8. Cada `<STMTRS>` vira um batch independente. Auto-detect de Institution (FEBRABAN code) e Account (tripla institution+branch+number). Multi-account num arquivo → todos os inserts (Institutions novas, Accounts novas, N batches, N×M transactions) numa única `writeTransaction`.
- **Dedup OFX**: exata por FITID (`external_id`), batched via `Set<String>` por conta.
- **Dedup CSV/XLSX**: heurística (dia local + valor centavos + descrição lower).
- **Categorização inicial**: `OFXCategoryHeuristic` por TRNTYPE/MEMO/NAME. Fase 4 (IA) vai refinar.

## Onde mexer pra cada coisa

| Pra... | Edite |
|---|---|
| Adicionar tabela nova | `GranaAi/Core/Database/AppSchema.swift` + novo Repository + model |
| Adicionar categoria/subcategoria padrão | `GranaAi/Core/Database/CategorySeedData.swift` |
| Adicionar ícone novo de categoria | `GranaAi/Models/Category.swift` (enum `CategoryIcon`) + `GranaAi/Shared/Components/CategoryIcon+Color.swift` |
| Adicionar ícone de UI (toolbar, empty state, ação) | `GranaAi/Shared/Components/AppIcon.swift` (enum `AppIcon`) — nunca usar string literal de SF Symbol direto na View |
| Adicionar instituição "rica" (logo + auto-detect) | `GranaAi/Models/Institution.swift` (enum `InstitutionKind`) + `GranaAi/Core/Database/Seed.swift` (seed) |
| Adicionar cor do tema | `GranaAi/Resources/Assets.xcassets/<Nome>.colorset/` (variante dark obrigatória) — Xcode gera o `Color.<nome>` automático |
| Mudar filtros de período | `GranaAi/Models/PeriodFilter.swift` |
| Mudar layout do dashboard | `GranaAi/Features/Dashboard/DashboardView.swift` + `Charts/` |

## Antes de codar (checklist)

1. Feature está no [ROADMAP.md](./ROADMAP.md) ou foi aprovada explicitamente?
2. Modelo de domínio já existe? Se não, atualize a seção 4 de `PROJECT.md` ANTES.
3. Dependência nova? Justifique e atualize a seção 2 de `PROJECT.md`.
4. Respeita o padrão local-first via PowerSync (escrita = `execute`/`writeTransaction`, reativo = `watch`)?

Se qualquer resposta for "não" ou "incerto": **pare e pergunte**.

## Segurança

- Chaves vão em `Config.swift` (gitignorado). Template em `Config.example.swift`.
- Nunca logar valores de transações nem dados sensíveis.
- Banco local não criptografado (FileVault cobre no Mac).
- Supabase com RLS desde o dia 1 (Fase 5).
