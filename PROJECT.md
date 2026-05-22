# PROJECT.md — Aplicação Financeira Pessoal

> Este documento é a **constituição** do projeto. O Claude Code deve ler este arquivo no início de toda sessão de trabalho e respeitar todas as decisões aqui registradas. Quando uma decisão precisar mudar, atualize este documento ANTES de escrever código novo.

---

## 1. Visão e escopo

### O que é
Aplicação financeira pessoal **macOS** para gerenciar gastos mensais, investimentos, e visualizar a saúde financeira do usuário através de dashboards e gráficos.

### Quem usa
**Apenas o desenvolvedor** (single-user app). Sem multi-tenancy, sem onboarding genérico, sem suporte. Decisões podem ser opinativas e personalizadas.

### Modelo mental
Análise profunda, importação de planilhas, configuração, dashboards completos, conversa com IA sobre finanças — tudo desktop. App nasceu pra rodar no Mac do dev e ficar lá.

### Não-objetivos (o que este app NÃO é)
- Não é app de banco/corretora — não executa transações reais.
- Não é multiusuário — não suporta família, conjunto, casal.
- Não é orçamento prescritivo — não dá conselhos automáticos sobre quanto gastar.
- Não é replacement de planilha — é evolução dela com automação e visualização melhor.

---

## 2. Stack técnica (decisões fixas)

| Camada | Escolha | Razão |
|---|---|---|
| UI | SwiftUI | Nativo macOS, ecossistema Apple, integração com sistema |
| Linguagem | Swift 5.9+ | Padrão Apple, type-safe, async/await maduro |
| Persistência local + sync | **PowerSync Swift SDK** | SQLite local-first com sync bidirecional automático |
| Backend de dados | **Supabase** (Postgres) | Source of truth remoto, integração nativa com PowerSync |
| Auth | Supabase Auth (magic link) | Simples, sem senha pra gerenciar |
| Estado | `@Observable` (Swift 5.9 macro) | Substitui ObservableObject, mais simples |
| Reatividade DB→UI | `PowerSyncDatabase.watch` (AsyncThrowingStream) | Streams nativas, integra com SwiftUI |
| Navegação | NavigationSplitView | Idiomático no macOS pra apps com sidebar |
| Charts | Swift Charts (nativo) | Performance + integração visual |
| HTTP (APIs externas) | URLSession + async/await | Sem dependência externa |
| IA | Anthropic API (HTTP direto) | Categorização e chat sobre finanças |
| Importação XLSX | CoreXLSX | Leitura de planilhas |
| Importação CSV | Parsing manual com Foundation | Sem dependência |
| Tooling | Xcode 15+, Swift Package Manager | Padrão Apple |

### Dependências externas (Swift Package Manager)
- `powersync-swift` `1.13.1` (`github.com/powersync-ja/powersync-swift`, **Exact Version**) — banco local + sync
- `supabase-swift` `2.46.0+` (Up to Next Major) — auth e operações server-side
- `CoreXLSX` `0.14.2+` (Up to Next Major) — leitura de planilhas
- (Anthropic API: chamada HTTP direta, sem SDK por enquanto)

**Produto do PowerSync a vincular:** `PowerSync` (estático). **NUNCA** vincular `PowerSyncDynamic` (wrapper dinâmico que tem bugs de link em Xcode 26) nem `PowerSyncGRDB` (alpha — ver sub-decisão abaixo).

**Deployment target:** macOS `26.1`. Mais alto que o mínimo necessário pra `@Observable` (macOS 14) porque é app single-user na máquina do dev, que fica sempre atualizada — assim ganhamos APIs modernas sem `#available`.

### Sub-decisão: PowerSync API direta vs GRDB integration
Usaremos a **API direta do PowerSync** (`PowerSyncDatabase.get`, `getAll`, `watch`, `execute`). A integração GRDB do PowerSync existe mas está em alpha — não vamos depender dela. Se mais tarde sentirmos falta de query builder tipado, reavaliamos.

### Sub-decisão: `PowerSyncDatabase` é função factory, não classe
No SDK do PowerSync Swift, `PowerSyncDatabase` é uma **função factory** que retorna um valor que adota `PowerSyncDatabaseProtocol`. Por isso:

- **Instanciar:** `PowerSyncDatabase(schema: ..., dbFilename: ..., logger: ...)` (chamada de função)
- **Tipo de propriedade:** `any PowerSyncDatabaseProtocol` (não `PowerSyncDatabase`)

Repositories e qualquer outra camada que segure referência ao banco devem declarar o tipo como `any PowerSyncDatabaseProtocol`.

### Sub-decisão: `Schema` aceita array vazio
`Schema(tables: [Table], rawTables: [RawTable] = [])` aceita array vazio — útil pra Fase 0 antes de declarar tabelas. Tabelas reais entram na Fase 1.

### Sub-decisão: nullability não existe no schema do PowerSync
O `Column` do SDK Swift (`.text(name)`, `.integer(name)`, `.real(name)`) **não tem flag `isOptional`/`notNull`**. Todas as colunas declaradas no `Schema` são nullable no SQLite por debaixo — o PowerSync precisa disso pra suportar sync parcial e conflict resolution. Consequências práticas:

- **Obrigatoriedade vira responsabilidade do model Swift** (propriedade não-opcional na struct) + da lógica de insert no Repository.
- **Mappers validam explicitamente** com `getString(name:)` (lança em null) vs `getStringOptional(name:)` (retorna `nil`).
- Não tente declarar `NOT NULL` via SQL puro — o PowerSync gerencia o schema das tabelas internas; nosso `Schema(...)` só declara views.

### Logging
Cada arquivo que chama `log.<categoria>.info/error(...)` precisa de `import OSLog` (e/ou `import os`) explícito. A macro de string interpolation do `Logger` da Apple só fica visível nos arquivos que importam o módulo — não basta importar uma vez no `Logger.swift`.

### Sub-decisão: isolamento de actor por padrão (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)
O target tem essa build setting ativa (vem do template do Xcode 26). Consequência: **todo tipo/função sem anotação explícita fica `@MainActor` por padrão**. Isso elimina a maioria dos bugs de "modifying state on background thread" em SwiftUI, mas exige cuidado em pontos específicos:

- Closures passados pro PowerSync (`mapper:` em `watch`/`getAll`, callback de `writeTransaction`) precisam ser `@Sendable`. Métodos `static` MainActor-isolated não podem ser convertidos pra `@Sendable` sem perder o ator — vira erro em Swift 6.
- **Solução:** marcar com `nonisolated`. Aplicar em:
  - Mappers `private static` dos Repositories (`mapTransaction`, `mapAccount`, `mapCategory`).
  - Tipos utilitários estáticos chamados de closures off-main: `Converters`, `CategorySeedData`.
- Stores ficam MainActor (já é o que queremos pra UI). Repositories ficam MainActor por padrão; só os mappers são `nonisolated`.

---

## 3. Arquitetura

### Padrão: Local-first com PowerSync

```
┌─────────────────────────────────────────────┐
│              SwiftUI Views                   │
│  (observam Stores via @Observable)          │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│              Stores (@Observable)            │
│   TransactionStore, AssetStore, etc.        │
│   - Expõem dados pro UI                     │
│   - Consomem watch streams dos Repositories │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│              Repositories                    │
│  Encapsulam queries SQL específicas         │
│  Retornam AsyncThrowingStream via watch()   │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│         PowerSyncDatabase                    │
│  - SQLite local (gerenciado pelo PowerSync) │
│  - Sync bidirecional automático             │
│  - Conflict resolution                      │
│  - Upload queue offline                     │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│      SupabaseConnector (PowerSync)          │
│  - fetchCredentials() → token Supabase      │
│  - uploadData() → escreve no Postgres       │
└─────────────────────────────────────────────┘
```

**Princípios:**
- App lê e escreve sempre no PowerSync local. Nunca toca o Supabase diretamente pra dados sincronizados.
- Operações Supabase diretas (via `supabase-swift`) só pra: login/auth, e operações que ficam fora do escopo de sync (futuro).
- UI reativa via `watch()` queries — quando dados mudam (local ou via sync), a stream emite e a View re-renderiza.
- **Repositories ficam expostos em `AppContainer`** (`container.transactions`, `container.accounts`, etc.) — Composition Root da camada de dados. Stores recebem o `AppContainer` no init. Quando crescer (provavelmente Fase 6 com holdings/quotes/assets) ou se precisarmos trocar a implementação por mocks em testes, refatorar pra protocols + implementações separadas por feature. Detalhes em [ARCHITECTURE.md](./ARCHITECTURE.md).

### Estados do app por conexão
- **Online + autenticado:** sync rodando, mudanças propagam em tempo real.
- **Offline + autenticado:** app funciona normalmente, mudanças vão pra upload queue do PowerSync, sincronizam quando voltar.
- **Não autenticado:** modo local-only (PowerSync sem `connect()`). Útil pra dev e pras Fases 0-4 antes do sync entrar.

### Camadas de pasta

```
GranaAi/
├── App/                    # Entry point, configuração
│   ├── GranaAiApp.swift
│   ├── ContentView.swift
│   └── AppEnvironment.swift
├── Core/                   # Infra que não muda com features
│   ├── Database/           # PowerSync setup, schema, AppContainer (Composition Root), Converters, Seed
│   ├── Import/             # CSVReader, XLSXReader, OFXReader, ImportParser, OFXCategoryHeuristic
│   ├── Sync/               # SupabaseConnector (stub até Fase 5)
│   ├── Auth/               # AuthService (entra na Fase 5)
│   ├── Networking/         # HTTP client base (entra na Fase 4)
│   └── Logging/            # Log centralizado (OSLog)
├── Models/                 # Structs de domínio (Codable)
├── Repositories/           # Acesso a dados (uma por entidade)
├── Stores/                 # Estado observável (@Observable, MainActor)
├── Features/               # UI organizada por feature
│   ├── Dashboard/          # DashboardView + Charts/
│   ├── Transactions/       # TransactionsView, TransactionFormView, TransactionRow
│   ├── Accounts/           # AccountsView, AccountFormView
│   ├── Import/             # ImportView (wizard), ImportHistoryView
│   ├── Settings/           # SettingsView (tema)
│   ├── Investments/        # entra na Fase 6
│   └── AIChat/             # entra na Fase 7
├── Shared/                 # Components SwiftUI reusáveis
│   ├── Components/         # CategoryBadge, CategoryIcon+Color, CurrencyField, MetricCard
│   └── Theme/              # Theme.swift (aliases ShapeStyle: .success, .danger)
└── Resources/              # Assets.xcassets, Info.plist
```

---

## 4. Modelo de domínio (glossário)

Termos canônicos do projeto. Não invente sinônimos.

| Termo | Definição |
|---|---|
| **Transaction** | Um movimento financeiro (gasto, receita, transferência). Tem valor, data, categoria, conta. |
| **Account** | Conta onde dinheiro reside: corrente, poupança, carteira, conta corretora. Vínculo opcional com `Institution`. |
| **Institution** | Banco ou corretora. Várias Accounts podem compartilhar a mesma (ex: corrente + poupança no mesmo banco). `code` é o FEBRABAN/COMPE, `kind` é o enum `InstitutionKind` (Inter + `other`). Auto-detect via FID do OFX usa o `code`. |
| **Category** | Classificação de transação. Hierárquica via **self-FK `parent_id`** (`null = raiz`, preenchido = subcategoria) em vez de dois campos planos. Permite editar nomes e adicionar subcategorias sem migration. Ícone visual (SF Symbol) **só na raiz**; subcategoria herda na UI via `TransactionStore.icon(for:)`. Taxonomia padrão definida em `CategorySeedData.swift`. |
| **Asset** | Ativo financeiro específico: ação (PETR4), FII (HGLG11), tesouro, fundo. |
| **Holding** | Posição atual em um Asset: quantidade, preço médio, conta corretora. |
| **Quote** | Cotação de um Asset em um momento. |
| **ImportBatch** | Conjunto de transações importadas juntas (uma planilha ou um `STMTRS` do OFX). Permite desfazer via cascade DELETE atômico. |
| **ImportTemplate** | Mapeamento de colunas reutilizável (CSV/XLSX). `mapping_json` serializado pra evoluir o formato sem migration. |
| **Tag** | Marcação livre adicional em transação (ex: "viagem-tokyo-2025"). |

### Regras de negócio fixas
- Toda Transaction pertence a exatamente uma Account.
- Toda Transaction tem exatamente uma Category (subcategoria opcional).
- Valores monetários são `Decimal` no Swift (NUNCA `Double`) e armazenados como INTEGER de centavos no SQLite (PowerSync só tem `text`, `integer`, `real` — usar integer pra precisão).
- **Convenção de sinal (CRÍTICA):** `Transaction.amount` é sempre **magnitude positiva**. O sinal (entrada vs saída) vem do `CategoryKind` da categoria associada (`income` vs `expense` vs `transfer`). Importadores (OFX devolve valor com sinal; parser CSV/XLSX devolve débito negativo + crédito positivo) **normalizam via `abs()` no insert**. Sem isso, agregações `SUM(amount_cents)` por kind misturariam magnitudes com valores sinalizados e dariam errado.
- Datas armazenadas como ISO8601 string (text) em UTC. Timezone local convertido na leitura.
- **Comparação por "dia" usa Calendar local, não SUBSTR UTC:** o `Converters.iso8601` serializa em UTC ("Z"). Comparar `SUBSTR(occurred_at, 1, 10)` quebra perto da meia-noite (transação 22h local Brasil vira dia seguinte em UTC). Padrão usado: janela `[startOfDay−1d, startOfDay+2d)` em SQL + filtro `Calendar.isDate(_:inSameDayAs:)` em Swift. Funções com lógica de "dia" aceitam `calendar: Calendar = .current` injetável pra testes determinísticos.
- Moeda padrão: BRL. Multi-moeda fica fora do MVP.
- IDs são UUIDs. PowerSync gera o `id text` automaticamente em INSERTs sem id explícito (via `uuid()` no SQL). Pra FKs em código Swift: `UUID().uuidString`.

---

## 5. Convenções de código

### Naming
- Tipos: `PascalCase` (Transaction, AccountStore)
- Funções/variáveis: `camelCase` (fetchTransactions, totalBalance)
- Constantes globais: `camelCase` dentro de enum namespace (ex: `Constants.maxImportSize`)
- Arquivos: nome do tipo principal (Transaction.swift, TransactionRow.swift)
- Tabelas PowerSync: `snake_case` plural (transactions, accounts, categories)
- Colunas PowerSync: `snake_case` (created_at, account_id)

### SwiftUI
- Views são `struct` pequenas. Se passar de ~150 linhas, quebrar em sub-views.
- Estado local: `@State`. Estado compartilhado: `@Observable` class injetada via `@Environment`.
- NUNCA usar `ObservableObject` / `@Published` (legado). Usar macro `@Observable` do Swift 5.9.
- Previews obrigatórios em toda View. Usar `#Preview` macro.

### Async/Concurrency
- Usar `async/await` exclusivamente. Nada de Combine pra trabalho novo.
- Stores marcadas `@MainActor` por padrão.
- Watch streams consumidas em `.task` modifier das Views ou em métodos `start()` dos Stores.
- PowerSync já roda I/O em background — não precisa empurrar pra outras filas.

### PowerSync — boas práticas
- **Repositories** encapsulam SQL. Views nunca escrevem SQL.
- **Mappers** explícitos: cada Repository tem um mapper `(SqlCursor) throws -> Model`. Mappers de **agregados** (com `SUM`/`GROUP BY` ou JOIN) são funções separadas dos mappers de "row completa" — formatos de coluna diferentes.
- **Watch para listas reativas, getAll para snapshots one-shot.** Stores que alimentam dashboards (agregações) usam `getAll` e recalculam on-demand quando um filtro muda (via `didSet` → `refresh()`). Watch re-emite a cada `INSERT`/`UPDATE`/`DELETE` na tabela tocada, então usá-lo pra agregações faria o dashboard recomputar tudo a cada keystroke de qualquer formulário.
- **Transactions** (`writeTransaction`) pra operações multi-passo que precisam ser atômicas (ex: importar batch, seed inicial).
- **Agregar em SQL, não em Swift**, quando possível. `SUM`/`GROUP BY`/`COUNT` no SQLite é ordem de magnitude mais rápido que materializar N rows e somar em código. Exceção: agregações que precisam do **fuso local** (ex: dia da semana) — `strftime` opera em UTC e dá errado pra transações próximas da meia-noite. Nesses casos, traga colunas mínimas via SQL e agrupe em Swift com `Calendar`.

### Estado de UI vs. estado de dados
- **Stores** (`@Observable`) carregam só dados que vêm do banco (transactions, agregações, lista de últimas 5, etc.).
- **`@State` local na View** carrega estado **puro de visualização** (ex: modo "Ambos/Receitas/Despesas" do `IncomeVsExpenseChart`, sheet de formulário aberto, busca, expansão de seção). Não persiste entre sessões — reabrir o app volta ao default. Mover esse estado pro Store complicaria sem benefício.

### Erros
- Definir `enum AppError: Error` por domínio (DatabaseError, SyncError, ImportError).
- Erros que aparecem pro usuário devem ter `LocalizedError` com mensagem em PT-BR.

### Comentários
- Código deve ser legível sem comentários. Comentar só o **porquê**, nunca o **o quê**.
- TODOs com responsável e fase: `// TODO(fase-3): implementar conflict resolution custom`.

---

## 6. Decisões de produto fixas

- **Categorização:** começa com taxonomia padrão fixa (lista no Apêndice A). Usuário pode editar nomes mas estrutura é fixa no MVP.
- **Períodos de análise:** 4 presets — **mês atual**, **mês anterior**, **últimos 6 meses**, **últimos 12 meses**. `custom(from, to)` existe no enum `PeriodFilter` mas não é exposto na UI ainda (entra quando precisarmos de date-range picker). "Últimos N meses" inclui o mês corrente parcial (definição usada por Mint/Monarch/YNAB).
- **Dashboard — dois "modos" implícitos** ditados pelo `PeriodFilter.scope`:
  - **Mês único** (`currentMonth`/`previousMonth`/`custom`): bar horizontal de gastos por categoria + barras por dia da semana.
  - **Multi-mês** (`last6Months`/`last12Months`): bar horizontal de gastos acumulados no período + receita vs. despesa por mês com Picker de modo (`Ambos`/`Receitas`/`Despesas`).
  - A View bifurca pelo `scope`; o `DashboardStore.refresh()` também — só dispara as queries que serão renderizadas. Estado do modo oposto fica vazio (evita stale ao trocar de filtro).
- **Dashboard principal:** 4 cards no topo (saldo total lifetime, gastos no período, receitas no período, patrimônio investido placeholder até Fase 6) + gráficos full-width empilhados verticalmente. Sem grid 2-colunas — barras horizontais precisam de largura pra comparar magnitudes.
- **Transferências (`kind = .transfer`) NÃO entram em cards/gráficos do dashboard:** são neutras de saldo (PIX enviado + PIX recebido idealmente zeram), e como não modelamos o par ainda, contá-las distorceria os totais. Continuam sendo registradas como transactions normais; só ficam de fora das agregações.
- **Importação:** XLSX, CSV e OFX (1.x SGML + 2.x XML).
  - **CSV/XLSX:** mapping de colunas interativo na primeira importação; salva como template (`mapping_json`) pra reuso.
  - **OFX:** auto-detect de instituição (`<FI><FID>` ou `<BANKID>` → enum `InstitutionKind` via `fromCode`) e de conta (tripla `institution_id` + `branch_id` + `account_number`). Múltiplos `STMTRS` no mesmo arquivo viram batches independentes — todos os inserts (Institutions novas + Accounts novas + N batches + N×M transactions) acontecem numa única `writeTransaction` pra "tudo ou nada".
  - Dedup OFX exata via FITID (`external_id`), batched via `externalIds(forAccount:)` que devolve um `Set<String>` — match O(1) em vez de N queries.
  - Dedup CSV/XLSX heurística: mesmo dia local + mesmo valor + mesma descrição case-insensitive.
- **Tema:** preferência `system`/`light`/`dark` em `ThemeView` (sob "Configurações > Tema" na sidebar), persistida em `UserDefaults` via `@AppStorage("appColorScheme")` e aplicada no root via `.preferredColorScheme`. Mesma chave é lida pelo `ContentView` — sincronização automática.

---

## 7. Segurança e privacidade

- Banco local NÃO criptografado no MVP (FileVault do Mac já protege).
- Chaves em `Config.swift` que NÃO vai pro git. Versão exemplo `Config.example.swift` versionada.
  - Supabase URL
  - Supabase anon key
  - PowerSync instance URL
  - Anthropic API key
- Nunca logar valores de transações ou dados sensíveis.
- Supabase com Row Level Security (RLS) ativo desde o dia 1.
- PowerSync Sync Streams configuradas pra que cada usuário veja só seus dados (na prática só nós, mas é boa higiene).

---

## 8. O que perguntar antes de codar

Quando recebido um prompt de feature, antes de gerar código o Claude Code deve verificar:

1. A feature está no ROADMAP.md ou foi aprovada explicitamente?
2. Existe modelo de domínio pra ela ou precisa criar? Se criar, atualizar seção 4.
3. Há dependência nova? Justificar e atualizar seção 2.
4. A arquitetura proposta respeita o padrão local-first via PowerSync?
5. Operações de escrita usam `execute` ou `writeTransaction`? Operações reativas usam `watch`?

Se a resposta a qualquer uma for "não" ou "incerto", **pare e pergunte** antes de codar.

---

## Apêndice A — Taxonomia de categorias padrão

**Fonte da verdade:** [`GranaAi/Core/Database/CategorySeedData.swift`](GranaAi/Core/Database/CategorySeedData.swift). Mudanças na taxonomia editam **lá**, não aqui — este apêndice é só o resumo legível.

**Estrutura:** 15 raízes, cada uma com seu ícone (`CategoryIcon` → SF Symbol) e ~6-17 subcategorias. Subcategorias não têm ícone próprio (herdam do pai na UI). IDs são UUIDs gerados em runtime.

### Receitas (1 raiz)
- **Renda e Pagamentos** (`dollarSign`) — Salário, Freelance, Aposentadoria, Auxílio e Benefícios, Pensão, 13º Salário, Férias, PLR, Comissões, Juros de Investimentos, Dividendos, Aluguel Recebido, Vendas, Restituição de IR, Cashback.

### Despesas (13 raízes)
- **Compras Pessoais** (`shoppingBag`) — Roupas, Eletrônicos, Cosméticos, Móveis, Decoração, Livros, Presentes, etc.
- **Transporte e Viagem** (`car`) — Uber/99, Combustível, Passagens (aéreas/ônibus/trem), Hospedagem, Manutenção, IPVA, Pedágio, etc.
- **Entretenimento e Lazer** (`monitor`) — Netflix, Spotify, Academia, Cinema, Shows, Cursos Online, Software, etc.
- **Alimentação e Supermercado** (`utensils`) — Supermercados, Restaurantes, iFood/Uber Eats/Rappi, Cafeterias, Bares, Hortifrúti, etc.
- **Contas e Serviços** (`zap`) — Energia, Água, Internet, Celular, Gás, TV, Condomínio, Limpeza, etc.
- **Créditos e Empréstimos** (`creditCard`) — Cartão de Crédito, Empréstimos, Financiamentos (imobiliário/veicular), Consórcios, Cheque Especial, etc.
- **Saúde e Medicina** (`heart`) — Plano de Saúde, Consultas, Medicamentos, Exames, Cirurgias, Óculos, Suplementos, etc.
- **Seguros** (`shield`) — Vida, Automóvel, Residencial, Saúde, Viagem, Celular, etc.
- **Investimentos e Poupança** (`trendingUp`) — Poupança, CDB, Tesouro, LCI/LCA, Fundos, Ações, FIIs, ETFs, Cripto, etc.
- **Impostos e Taxas** (`fileText`) — IR, IPVA, IPTU, ITBI, Licenciamento, Multas, IOF, INSS, etc.
- **Saques e ATM** (`banknote`) — Saque ATM próprio/terceiros, Saque em Agência, Internacional, Taxa de Saque.
- **Não Classificado** (`helpCircle`) — Transação Desconhecida, Requer Análise Manual, Categoria Indefinida (fallback usado pela IA na Fase 4).
- **Jogos e Apostas** (`dice`) — Steam, Epic Games, Battle.net, Mega Sena, etc.

### Transferências (1 raiz)
- **Transferências** (`arrowRightLeft`) — PIX enviado/recebido, TED, DOC, Transferência entre Contas/Internacional, Remessa Familiar, Depósito.

> Nota: alguns nomes aparecem em mais de uma árvore quando o significado difere por contexto (ex: **IPVA** está em "Transporte e Viagem" e em "Impostos e Taxas" — UUIDs distintos, sem conflito de schema).
