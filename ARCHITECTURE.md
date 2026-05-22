# ARCHITECTURE.md — Arquitetura do Grana AI

> Visão técnica das camadas, fluxo de dados e responsabilidades. Para visão de produto/escopo veja [PROJECT.md](./PROJECT.md); para fases de desenvolvimento, [ROADMAP.md](./ROADMAP.md); para guia rápido por sessão, [CLAUDE.md](./CLAUDE.md).

---

## Visão geral

O Grana AI é um app SwiftUI **macOS** single-user com persistência **local-first** via PowerSync (SQLite). A arquitetura é uma simplificação pragmática de Clean / MVVM adaptada ao tamanho do projeto: poucas camadas, sem abstrações antecipadas, mas com pontos de extensão claros pra quando crescer.

**Princípio orientador:** evitar abstrações que não pagam o custo agora. Cada camada existe porque resolve um problema concreto, não porque "a arquitetura clássica pede".

---

## As camadas

```
┌───────────────────────────────────────────────────────────────┐
│  View (SwiftUI)              UI declarativa, sem lógica       │
│  ↓                           de domínio nem SQL               │
├───────────────────────────────────────────────────────────────┤
│  Store (@Observable, MainActor)                               │
│  ↓                           Estado observável da feature     │
│                              + orquestração de chamadas       │
├───────────────────────────────────────────────────────────────┤
│  Repository                  Queries SQL + mapping            │
│  ↓                           Domain → Row e vice-versa        │
├───────────────────────────────────────────────────────────────┤
│  PowerSyncDatabase           Banco SQLite local + (futuro)    │
│                              sync com Supabase                │
└───────────────────────────────────────────────────────────────┘

           ┌──────────────────────────────┐
           │  AppContainer                │
           │  (Composition Root)          │
           │                              │
           │  Instancia o banco e expõe   │
           │  Repositories + serviços.    │
           │  É o "service locator" da    │
           │  camada de dados.            │
           └──────────────────────────────┘
```

### View
**Arquivos:** `GranaAi/Features/<Feature>/<Feature>View.swift`

SwiftUI puro. Observa um `Store` (via `@State` ou injetado), renderiza, despacha ações. **Nunca toca SQL nem instancia `Repository` diretamente.**

Convenções:
- Views pequenas (~150 linhas máx) — se crescer, quebrar em subviews.
- `@State` local pra estado puramente de visualização (mostrar/esconder modal, valor de campo).
- `#Preview` macro em toda View nova.

### Store (`@Observable`, `@MainActor`)
**Arquivos:** `GranaAi/Stores/<Feature>Store.swift`

Estado observável da feature + orquestração de chamadas ao Repository. Recebe `AppContainer` no init e usa `container.transactions`, `container.accounts`, etc. Roda na main thread (anotado com `@MainActor`).

**Por que `@Observable` e não `ObservableObject`:** a macro do Swift 5.9 gera tracking por propriedade. A UI re-renderiza só quando o campo lido muda, sem precisar marcar tudo com `@Published`. Mais performático e menos verboso.

**Pattern típico:**
```swift
@MainActor
@Observable
final class TransactionStore {
    private let container: AppContainer
    private(set) var transactions: [Transaction] = []

    init(container: AppContainer) {
        self.container = container
    }

    func start() async {
        for try await rows in try container.transactions.watchAll() {
            self.transactions = rows
        }
    }
}
```

### Repository
**Arquivos:** `GranaAi/Core/Database/<Entity>Repository.swift`

Concentra **todas** as queries SQL daquela tabela + mapping `Row ↔ Model`. Cada Repository recebe o `db` (`any PowerSyncDatabaseProtocol`) no init e nunca conhece outras camadas (Views, Stores).

Operações típicas:
- `getAll()` — snapshot, leitura única.
- `watchAll()` — `AsyncThrowingStream` que reemite a cada `INSERT`/`UPDATE`/`DELETE` na tabela.
- `insert/update/delete` — escritas pontuais.
- Agregações (`sum`, `totalsByCategory`, ...) — SQL puro com `SUM`/`GROUP BY` quando possível.

**Mappers são `static nonisolated`** pra serem `@Sendable`-compatíveis nos closures do PowerSync (o projeto tem `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).

### PowerSyncDatabase
**Lib externa.** O banco SQLite local. Hoje roda em **modo local-only** (sem `connect(connector:)`) — passa a sincronizar com Supabase na Fase 5 sem mudar a camada de dados.

Pontos a saber:
- `PowerSyncDatabase(...)` é uma **função factory** (não classe). Por isso o `AppContainer.db` declara o tipo `any PowerSyncDatabaseProtocol`.
- `execute` aceita prepared statements (`parameters: [(any Sendable)?]`) — SQL injection impossível.
- `writeTransaction` garante atomicidade pra operações multi-passo (seed, import OFX multi-account).

---

## AppContainer — o Composition Root

**Arquivo:** [`GranaAi/Core/Database/AppContainer.swift`](./GranaAi/Core/Database/AppContainer.swift)

Esta classe é onde tudo é amarrado:

```swift
final class AppContainer {
    let db: any PowerSyncDatabaseProtocol

    lazy var transactions = TransactionRepository(db: db)
    lazy var accounts = AccountRepository(db: db)
    lazy var categories = CategoryRepository(db: db)
    // ...
    lazy var categorization = CategorizationService(...)
}
```

### Por que se chama "Container", não "Database"

Ela **não é o banco** — o banco é a propriedade `db`. O `AppContainer` é um **Composition Root** (termo do Mark Seemann, "Dependency Injection Principles"): o ponto único onde dependências são criadas e amarradas.

Vindo de Flutter com Clean Architecture + GetIt, o paralelo é direto:

```dart
// Flutter / GetIt
void setupLocator() {
  getIt.registerSingleton<Database>(PowerSyncDatabase(...));
  getIt.registerLazySingleton<TransactionRepository>(
    () => TransactionRepository(db: getIt()),
  );
}
```

O `AppContainer` faz exatamente isso, mas sem container externo: as `lazy var` substituem `registerLazySingleton`. A direção da dependência continua a mesma da Clean clássica — **Repository depende do banco**, nunca o contrário. O Container apenas materializa essa amarração.

### Por que `lazy var`

Duas razões:

1. **Técnica:** propriedades não-lazy com inicializadores em-linha não podem referenciar `self`. Como `TransactionRepository(db: db)` precisa do `db` (que é outra propriedade da mesma instância), `lazy` adia a inicialização pra depois do `init` rodar.
2. **Performance:** se nada usa, por exemplo, `categorization`, ele nunca é instanciado. Economiza trabalho no boot.

### Injeção via AppEnvironment

O `AppContainer` é instanciado uma única vez no `AppEnvironment`, que é injetado na árvore SwiftUI via `.environment(...)`:

```swift
@Observable
final class AppEnvironment {
    let container: AppContainer
    init() { self.container = AppContainer.setup() }
}

// Em GranaAiApp.swift
WindowGroup {
    ContentView()
        .environment(environment)
}

// Em qualquer View
@Environment(AppEnvironment.self) private var environment

// Pra criar um Store
TransactionStore(container: environment.container)
```

---

## Fluxo de dados de ponta a ponta

### Leitura reativa (lista de transações)

```
1. View aparece                  → .task { await store.start() }
2. Store.start()                 → container.transactions.watchAll()
3. Repository.watchAll()         → db.watch("SELECT * FROM transactions ...")
4. PowerSync emite snapshot      → AsyncThrowingStream yields [Row]
5. Repository mapeia rows        → [Transaction] (domain)
6. Store atualiza self.transactions
7. @Observable notifica View     → SwiftUI re-renderiza
```

Inserção em outra tela dispara o passo 4 de novo automaticamente.

### Escrita simples (criar transação)

```
1. View → store.add(...)
2. Store monta o Transaction     → container.transactions.insert(tx)
3. Repository.insert()           → db.execute("INSERT INTO ...", parameters)
4. PowerSync persiste            → emite na watch stream
5. Stores que observam a tabela  → recebem o novo snapshot
6. UI re-renderiza
```

### Escrita atômica (import OFX multi-account)

Operações que tocam múltiplas tabelas usam `writeTransaction` pra atomicidade:

```swift
try await container.db.writeTransaction { tx in
    try tx.execute("INSERT INTO institutions ...", ...)
    try tx.execute("INSERT INTO accounts ...", ...)
    try tx.execute("INSERT INTO import_batches ...", ...)
    for transaction in transactions {
        try tx.execute("INSERT INTO transactions ...", ...)
    }
    // qualquer throw aqui → rollback automático
}
```

---

## Onde a Clean "tradicional" reapareceria

A arquitetura atual **achata** uma separação típica da Clean: hoje `TransactionRepository` é uma classe concreta que já fala SQL diretamente — não há protocol no domain + impl no data.

Isso é uma escolha consciente pra um app pequeno e single-user. Quando crescer (ou se precisarmos mockar Repositories em testes), a refatoração natural é:

```swift
// Domain
protocol TransactionRepository {
    func fetchAll() async throws -> [Transaction]
    func insert(_ tx: Transaction) async throws
}

// Data
final class PowerSyncTransactionRepository: TransactionRepository {
    private let db: any PowerSyncDatabaseProtocol
    // ...
}

// AppContainer escolhe a impl
lazy var transactions: any TransactionRepository =
    PowerSyncTransactionRepository(db: db)
```

Stores então dependem só do protocol. **Mesma direção de dependência, só com indireção a mais.**

---

## Invariantes da camada de dados

Estas regras valem em todo Repository / Store / View. Quebrar uma costuma cascatear bugs sutis:

1. **Sinal do `amount` é sempre magnitude positiva.** O sinal (entrada/saída) vem do `CategoryKind` da categoria associada. Importadores normalizam com `abs()` antes de inserir.
2. **Dinheiro em `Decimal` no Swift, `Int64` centavos no banco.** Nunca `Double`. Conversão via `Converters.decimalToCents`/`centsToDecimal`.
3. **Datas em ISO8601 UTC no banco** (`Converters.iso8601` com `.withFractionalSeconds`). Comparações por "dia" usam `Calendar` local + janela em SQL — nunca `SUBSTR(occurred_at, 1, 10)` (quebra perto da meia-noite por causa do UTC).
4. **Views nunca tocam SQL.** Só Repositories.
5. **Schema do PowerSync não tem NOT NULL.** Obrigatoriedade vive no model Swift (propriedade não-opcional) + lógica de insert. Mappers usam `getString(name:)` (lança em null) vs `getStringOptional(name:)`.
6. **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** está ativo. Mappers `static` de Repositories, `Converters`, `CategorySeedData` precisam de `nonisolated` pra serem `@Sendable`-compatíveis nos closures do PowerSync.
7. **Transferências (`kind = .transfer`) ficam fora** dos cards e gráficos do dashboard.

---

## Tratamento de erros

Sistema centralizado em `GranaAi/Core/ErrorHandling/`. Toda falha visível pro usuário passa pelo `ErrorCenter`, que mantém uma fila de toasts renderizada no canto superior-direito via `.errorToastOverlay()` (plugado uma única vez em `ContentView`).

Detalhes operacionais (quando reportar, quando engolir, criação de erros novos) estão em [CLAUDE.md](./CLAUDE.md#tratamento-de-erros).

---

## Diretórios

```
GranaAi/
├── App/                    # Entry point, AppEnvironment
├── Core/
│   ├── Database/           # AppContainer, schema, Repositories, Seed, Converters
│   ├── Import/             # OFXReader, ImportParser, OFXCategoryHeuristic
│   ├── AI/                 # ClaudeCLIClient, CategorizationService, prompts
│   ├── Sync/               # SupabaseConnector (stub até Fase 5)
│   ├── Auth/               # AuthService (entra na Fase 5)
│   ├── Networking/         # HTTP client base
│   ├── ErrorHandling/      # ErrorCenter, UserFacingError, toast overlay
│   └── Logging/            # Log centralizado (OSLog)
├── Models/                 # Structs de domínio (Codable)
├── Stores/                 # @Observable stores por feature
├── Features/               # Views por feature (Dashboard, Transactions, ...)
├── Shared/                 # Componentes reutilizáveis (AppIcon, CategoryIcon)
└── Resources/              # Assets.xcassets, Info.plist, Config
```

---

## Decisões a revisitar quando crescer

Estas escolhas são pragmáticas pro tamanho atual. Não são erros — só não escalam pra sempre.

| Decisão atual | Quando revisitar |
|---|---|
| Repositories concretos (sem protocol no domain) | Quando precisar mockar em testes ou trocar a impl |
| `AppContainer` instancia tudo direto | Quando passar de ~10 repositories ou tiver múltiplos backends |
| Stores conhecem `AppContainer` inteiro | Quando algum Store precisar só de 1-2 deps (passar individuais) |
| Sem use cases (Stores chamam Repository direto) | Quando uma operação envolver 3+ Repositories e ganhar lógica de domínio |

Enquanto a base for pequena, abstração antecipada custa mais do que entrega. Cresce, abstrai.
