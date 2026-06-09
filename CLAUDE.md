# CLAUDE.md

> Guia carregado automaticamente pelo Claude Code em toda sessão neste repositório. Resume **o essencial pra não re-perguntar**. Detalhes longos vão em [PROJECT.md](./PROJECT.md) e [ROADMAP.md](./ROADMAP.md) — leia esses dois quando começar uma feature nova.

---

## O que é

App financeiro pessoal **single-user** macOS. SwiftUI + PowerSync (SQLite local-first) + Supabase (entra na Fase 5).

**Status:** Fases 0–4.7 ✅ (fundação, CRUD, dashboard, importação OFX+CSV Inter, categorização IA, cartões + faturas, refator de Account em primitivo + tabelas-irmãs). Fase 5+ no [ROADMAP.md](./ROADMAP.md).

## Stack travada

- Swift 5.9+ / SwiftUI / `@Observable` (`ObservableObject` é bloqueado pelo SwiftLint)
- PowerSync Swift SDK `1.13.1` exact — produto `PowerSync` estático (não `PowerSyncDynamic` nem `PowerSyncGRDB`)
- Swift Charts, URLSession
- **IA via shell-out** pro `claude` CLI (Claude Code) usando a assinatura do usuário — NÃO `api.anthropic.com` paga. Por isso `ENABLE_APP_SANDBOX = NO` no `project.pbxproj` (sandbox bloqueia `Process` de executar binários fora do bundle). Single-user, local-first, sem distribuição → trade-off aceito.
- Supabase via `supabase-swift` (auth) — entra na Fase 5
- Target: macOS 26.1+

## Arquitetura num parágrafo

`SwiftUI View → @Observable Store (MainActor) → Repository (any PowerSyncDatabaseProtocol) → PowerSyncDatabase`. Reatividade via `watch()` que devolve `AsyncThrowingStream`. Operações multi-passo críticas (import batch, seed, OFX multi-account) via `writeTransaction` pra atomicidade. Os Repositories ficam expostos em `AppContainer` (Composition Root da camada de dados) — `container.transactions`, `container.accounts`, etc. Stores recebem o `AppContainer` no init. Visão completa das camadas em [ARCHITECTURE.md](./ARCHITECTURE.md).

## Invariantes que NÃO podem quebrar

> Os itens 2 e 3 abaixo têm validação mecânica em [.swiftlint.yml](./.swiftlint.yml) (`no_double_for_money`, `no_substr_occurred_at`). Os demais dependem de revisão humana.

1. **Sinal do `amount` é sempre magnitude positiva.** O sinal (entrada/saída) vem do `CategoryKind` da categoria. Importadores normalizam via `abs()` antes de inserir. Quebrar isso quebra todas as agregações do dashboard.
2. **Dinheiro em `Decimal`** no Swift, **`Int64` centavos** no banco. NUNCA `Double`. Conversões via `Converters.decimalToCents`/`centsToDecimal`.
3. **Datas em ISO8601 UTC** no banco (`Converters.iso8601` com `.withFractionalSeconds`). Comparação por "dia" usa **`Calendar` local + janela em SQL**, nunca `SUBSTR(occurred_at, 1, 10)` (quebra perto da meia-noite por causa do UTC).
4. **Views nunca tocam SQL** — só Repositories.
5. **Schema do PowerSync não tem NOT NULL.** Obrigatoriedade vive no model Swift (propriedade não-opcional) + lógica de insert. Mappers usam `getString(name:)` (lança em null) vs `getStringOptional(name:)`.
6. **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** está ativo. Mappers `static` dos Repositories, `Converters`, `CategorySeedData` precisam de `nonisolated` pra serem `@Sendable`-compatíveis nos closures do PowerSync.
7. **Transferências (`kind = .transfer`) ficam de fora** dos cards e gráficos do dashboard (PIX enviado + recebido idealmente zeram).

## Convenções de código

> Estilo mecânico (indentação, imports, naming, `Double` pra dinheiro, `ObservableObject`, `TODO` sem fase etc.) é codificado em [.swiftformat](./.swiftformat) + [.swiftlint.yml](./.swiftlint.yml). SwiftLint roda como build phase do Xcode — violações aparecem direto no build. Rode `/format` quando quiser normalizar layout. Esta seção só lista o que **não** dá pra deixar pra ferramenta.

- Views pequenas (~150 linhas é o alvo). `@State` local pra estado puramente de visualização; `@Observable` Store pra dados do banco. Tabelas/colunas SQL em `snake_case`.
- `async/await` exclusivamente (Combine só pra código legado, que não tem aqui).
- **Não usar `#Preview`.** O stack pesado (PowerSync + Supabase + Crypto + GRDB, ~35 módulos pra JIT-linkar) faz o canvas do Xcode estourar timeout, enquanto o app real builda e abre em <5s. Iterar UI via `Cmd+R` no app, não no canvas.
- Erros com `enum` por domínio (`DatabaseError`, `ImportError`, etc.) + `LocalizedError` em PT-BR.
- Comentários explicam **por quê**, nunca **o quê**.
- Cada arquivo que usa `log.<categoria>.info(...)` precisa `import OSLog` explícito (interpolation da Apple só fica visível no módulo importado).

## Sub-decisões PowerSync (fáceis de quebrar sem saber)

- `PowerSyncDatabase(...)` é **função factory**, não classe. Propriedades declaram tipo `any PowerSyncDatabaseProtocol`.
- `parameters: [(any Sendable)?]` em `db.execute` — prepared statements internos, SQL injection é impossível.
- `watch` re-emite a cada `INSERT`/`UPDATE`/`DELETE` na tabela tocada. Usar pra listas reativas. Usar `getAll` pra snapshots (dashboards, agregações com filtro de período).
- Agregar em SQL (`SUM`, `GROUP BY`) sempre que possível. Exceção: lógica que depende de fuso local (dia da semana, dia local) — `strftime` opera em UTC. Traga colunas mínimas e agregue em Swift com `Calendar`.

## Importação

- **OFX (extrato bancário) + CSV (fatura Inter).** XLSX continua fora. Extensões aceitas em `ImportStore.supportedExtensions` — é o single source of truth pro `loadFile` e pro drag & drop.
- **Wizard**: `ImportView` é um shell modal que roteia `Phase` → step view. Cada step vive em `Features/Import/Steps/` (OFX review, CSV review, Categorizing, Failed). A tela "Importações" (`ImportHistoryView`) também aceita drag & drop — arrasta arquivo, abre wizard com `initialFile` pré-carregado.
- **OFX**: reader unificado SGML 1.x + XML 2.x, charset CP1252 ou UTF-8. Cada `<STMTRS>` vira um batch independente. Auto-detect de Institution (FEBRABAN code) e Account (tripla institution+branch+number). A partir da Fase 4.5 o import **não cria contas** — o usuário escolhe uma existente quando o auto-detect não acha. Multi-statement num arquivo → todos os inserts (N batches, N×M transactions) numa única `writeTransaction` via `commitImport`.
- **CSV Inter (fatura de cartão)**: parser dedicado em `InterCreditCardCSVReader`. Filtra linhas com valor negativo (pagamentos da fatura anterior + estornos) — o pagamento real é registrado como transferência no extrato OFX do checking. Não tem auto-detect: o usuário escolhe a conta-cartão de destino no preview.
- **Dedup OFX**: exata por FITID (`external_id`), batched via `Set<String>` por conta. CSV Inter: heurística por (data + descrição + valor) contra `categorization_cache` da conta.
- **Categorização inicial**: heurística por TRNTYPE/MEMO/NAME (OFX). A categorização via IA (Fase 4) roda **antes do commit** entre os steps `*Review` e `confirming` — a tela de revisão é parte do wizard, não um post-step. Cancelar descarta tudo.

## Onde mexer pra cada coisa

| Pra... | Edite |
|---|---|
| Reportar erro/sucesso/info pro toast global | `NoticeCenter.shared.report(error)`, `.success(title:...)`, `.info(title:...)` (MainActor) ou `NoticeCenter.capture(error)` (nonisolated) — ver seção "Feedback ao usuário (toasts)" |
| Adicionar tabela nova | `GranaAi/Core/Database/AppSchema.swift` + novo Repository + model |
| Adicionar campo a Account por tipo | `bank_accounts` (checking) ou `credit_cards` (cartão) em `AppSchema.swift`. `accounts` é primitivo desde a Fase 4.6 — campos específicos vivem em tabelas-irmãs 1:1, escritos junto via `writeTransaction` no `AccountRepository` |
| Adicionar formato de importação novo | `GranaAi/Core/Import/<Formato>Reader.swift` + ramo em `ImportStore.loadFile` + extensão em `ImportStore.supportedExtensions` + novo `*ReviewStepView` em `Features/Import/Steps/` |
| Adicionar categoria/subcategoria padrão | `GranaAi/Core/Database/CategorySeedData.swift` |
| Adicionar ícone novo de categoria | `GranaAi/Models/Category.swift` (enum `CategoryIcon`) + `GranaAi/Shared/Components/CategoryIcon+Color.swift` |
| Adicionar ícone de UI (toolbar, empty state, ação) | `GranaAi/Shared/Components/AppIcon.swift` (enum `AppIcon`) — nunca usar string literal de SF Symbol direto na View |
| Adicionar instituição "rica" (logo + auto-detect) | `GranaAi/Models/Institution.swift` (enum `InstitutionKind`) + `GranaAi/Core/Database/Seed.swift` (seed) |
| Adicionar cor do tema | `GranaAi/Resources/Assets.xcassets/<Nome>.colorset/` (variante dark obrigatória) — Xcode gera o `Color.<nome>` automático |
| Adicionar categoria de log nova | `GranaAi/Core/Logging/Logger.swift` (struct `Log`). Categorias atuais: `database`, `sync`, `network`, `ui`, `ai`, `import` |
| Mudar filtros de período | `GranaAi/Models/PeriodFilter.swift` |
| Mudar layout do dashboard | `GranaAi/Features/Dashboard/DashboardView.swift` + `Charts/` |

## Feedback ao usuário (toasts)

Sistema centralizado em `GranaAi/Core/ErrorHandling/NoticeCenter.swift`. **Toda comunicação visível pro usuário passa pelo `NoticeCenter`** — fila de toasts no canto superior-direito da janela, plugada uma única vez em `ContentView` via `.noticeOverlay()`.

Três categorias com timeout e cor distintos:

| Kind | Cor | Timeout (sem ações) | Timeout (com ações) | Quando usar |
|---|---|---|---|---|
| `error` | vermelho | 6s | 6s | Falhas visíveis pro usuário. |
| `success` | verde | 4s | 10s | Confirmação de operação concluída (ex: import). |
| `info` | neutro | 5s | 10s | Avisos não-críticos (ex: input ajustado, comportamento inesperado mas não-falha). |

**Como reportar:**

```swift
// Erros
NoticeCenter.shared.report(error)                          // título derivado do tipo
NoticeCenter.shared.report(error, title: "Falha ao X")     // título custom
NoticeCenter.shared.report(title: "Aviso", message: "...") // sem Error tipado

// Sucesso (toast verde, opcionalmente com ações)
NoticeCenter.shared.success(title: "Importação concluída", message: "12 transações em 1 lote.")
NoticeCenter.shared.success(title: "...", actions: [
    .init(title: "Desfazer", role: .destructive) { /* … */ }
])

// Info (toast neutro)
NoticeCenter.shared.info(title: "Vários arquivos", message: "Importando só o primeiro.")

// Contexto não-MainActor (services Sendable, callbacks de SDK):
NoticeCenter.capture(error, title: "Falha ao X")           // faz hop pro main internamente
```

**Ações inline** (`NoticeCenter.Action`): botões clicáveis dentro do card, role `.default` (azul) ou `.destructive` (vermelho). Clicar dispara o handler e dispensa a notice. Usar pra "Desfazer" pós-import, etc. Notices **com** ações **não** deduplicam — disparos repetidos viram cards separados.

**Regra de ouro por tipo de `catch`:**

| Padrão do catch | O que fazer |
|---|---|
| Relança/transforma erro (`throw OutroError(...)`) | **Não** reporta. O pai cuida. |
| Engole erro pra continuar fluxo (fallback) | **Reporta** antes de continuar. |
| Reage a erro já reportado por outro lugar | `log.X.notice(...)` (não `.error`) pra evitar toast duplicado. |
| `catch is CancellationError` | Silencioso. `.task` cancelado = comportamento esperado. |

**O `NoticeCenter` cuida sozinho de:**
- Filtrar `CancellationError` (não vira toast).
- Dedup de notices iguais em janela <1s (só pra notices **sem** ações — evita spam quando stream falha em loop).
- Auto-dismiss com timeout por kind.
- Logar tudo em `log.ui` (`.error` pra `Kind.error`, `.info` pros demais), com mensagem em `privacy: .private` — **não duplicar `log.X.error` antes de reportar**.

**O que NÃO dá pra capturar:** logs do CFNetwork/AppKit/sandbox que aparecem no Console (`networkd_settings`, `nw_resolver`, `Task <…> HTTP load failed`, `layoutSubtreeIfNeeded`). Não são `Error` Swift — são `os_log` direto do sistema. O `URLError` real correspondente chega como exceção e esse sim é reportado.

**Criar um erro novo:** estenda os enums por domínio em `Core/{Database,Import,Networking}/<Domain>Error.swift`. Todos conformam a `LocalizedError` com mensagens em PT-BR. Opcionalmente conformar a `UserFacingError` (em `Core/ErrorHandling/AppError.swift`) se quiser controlar o título do toast (default: nome legível do tipo, ex: "Erro no banco", "Erro na importação").

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
