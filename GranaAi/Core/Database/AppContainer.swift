import Foundation
import OSLog
import PowerSync

/// Composition Root da camada de dados. Concentra a instância do banco
/// (`PowerSyncDatabase`), os Repositories e os serviços que dependem do banco.
/// As Views nunca tocam SQL — elas falam com Stores `@Observable`, que falam
/// com Repositories expostos aqui.
///
/// Por que "Container" e não "Database": esta classe **não é** o banco. O banco
/// é a propriedade `db`. O Container é o lugar único onde tudo é amarrado
/// (banco + repositories + serviços), seguindo o padrão Composition Root. Veja
/// `ARCHITECTURE.md` na raiz pra uma visão completa das camadas.
///
/// Conceito-chave: **modo local-only**.
/// `PowerSyncDatabase` funciona perfeitamente como um SQLite local sem chamar
/// `connect(connector:)`. Isso significa que durante as Fases 0–4 o app já
/// persiste tudo localmente, e na Fase 5 *adicionamos* sync simplesmente
/// chamando `connect()` após o login. Não precisamos reescrever camada de
/// dados pra ativar o sync.
final class AppContainer {
  /// Nome do arquivo SQLite. O PowerSync coloca isso em
  /// `Application Support/<bundleId>/<dbFilename>` por padrão.
  static let dbFilename = "grana_ai.sqlite"

  /// Acesso interno (Repositories). Mantido `internal` (default) — Views
  /// não devem importar isso.
  ///
  /// Detalhe do SDK: `PowerSyncDatabase` é uma **função factory** (não
  /// uma classe), que retorna um valor que adota `PowerSyncDatabaseProtocol`.
  /// Por isso a propriedade declara o protocolo, mas `setup()` abaixo
  /// chama `PowerSyncDatabase(...)` como função.
  let db: any PowerSyncDatabaseProtocol

  // Repositories como `lazy var`: só são instanciados na primeira leitura.
  // Decisão consciente: vivem dentro do AppContainer enquanto a superfície é
  // pequena. Quando crescer (ou se precisarmos trocar a implementação por
  // mocks em testes), separar em protocols + implementações por feature.
  lazy var transactions: TransactionRepository = TransactionRepository(db: db)
  lazy var accounts: AccountRepository = AccountRepository(db: db)
  lazy var categories: CategoryRepository = CategoryRepository(db: db)
  lazy var institutions: InstitutionRepository = InstitutionRepository(db: db)
  lazy var importBatches: ImportBatchRepository = ImportBatchRepository(db: db)
  lazy var categorizationCache: CategorizationCacheRepository = CategorizationCacheRepository(
    db: db)
  lazy var categorizationCorrections: CategorizationCorrectionRepository =
    CategorizationCorrectionRepository(db: db)

  /// Shell-out pro `claude` CLI usando a assinatura Claude do usuário.
  /// Compartilhado pelo `CategorizationService` (Fase 4) e, futuramente,
  /// pelo chat IA (Fase 7).
  lazy var claudeCLIClient: ClaudeCLIClient = ClaudeCLIClient(
    executablePath: Config.claudeCLIPath,
    model: Config.claudeCLIModel
  )

  /// Pipeline de categorização automática (Fase 4). Usa cache + correções
  /// + Claude CLI com `--json-schema` pra output estruturado. Disparado em
  /// background pelos importadores após `writeTransaction`.
  lazy var categorization: CategorizationService = CategorizationService(
    client: claudeCLIClient,
    transactions: transactions,
    categories: categories,
    accounts: accounts,
    institutions: institutions,
    cache: categorizationCache,
    corrections: categorizationCorrections
  )

  private init(db: any PowerSyncDatabaseProtocol) {
    self.db = db
  }

  /// Cria a instância e registra o schema. O PowerSync aplica o schema
  /// criando *views SQLite em runtime* sobre tabelas internas — não é
  /// migration tradicional. Mudar o schema entre versões é seguro: o
  /// PowerSync recria as views, sem perda de dados locais (desde que
  /// colunas removidas não sejam o que o app procura).
  static func setup() -> AppContainer {
    let database = PowerSyncDatabase(
      schema: appSchema,
      dbFilename: dbFilename,
      logger: log.powerSyncLogger
    )

    // NOTA: NÃO chamamos `database.connect(connector:)` aqui.
    // Isso é o que define o "modo local-only" — sem sync com Supabase.
    // A chamada de `connect` virá no `AuthService` da Fase 5, depois
    // do login bem-sucedido — aí esse método volta a ser `throws` e o
    // `AppEnvironment.failed(error:)` volta a ser usado.

    log.database.info("PowerSyncDatabase inicializado em modo local-only (\(dbFilename))")
    return AppContainer(db: database)
  }

  /// Usado apenas pelo fallback de `AppEnvironment` quando o setup real
  /// falha. Cria uma instância "vazia" pra manter o app compilável; qualquer
  /// query lança erro porque não há banco real por trás.
  static func placeholder() -> AppContainer {
    let database = PowerSyncDatabase(
      schema: appSchema,
      dbFilename: "placeholder.sqlite",
      logger: log.powerSyncLogger
    )
    return AppContainer(db: database)
  }
}
