import Foundation
import OSLog
import PowerSync

/// Wrapper sobre `PowerSyncDatabase`. Os Repositories acessam o banco através
/// daqui — Views nunca tocam SQL diretamente.
///
/// Conceito-chave: **modo local-only**.
/// `PowerSyncDatabase` funciona perfeitamente como um SQLite local sem chamar
/// `connect(connector:)`. Isso significa que durante as Fases 0–4 o app já
/// persiste tudo localmente, e na Fase 5 *adicionamos* sync simplesmente
/// chamando `connect()` após o login. Não precisamos reescrever camada de
/// dados pra ativar o sync.
final class AppDatabase {
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
    // Decisão consciente: vivem dentro do AppDatabase enquanto a superfície é
    // pequena. Quando crescer, separar em `RepositoryContainer`.
    lazy var transactions: TransactionRepository = TransactionRepository(db: db)
    lazy var accounts: AccountRepository = AccountRepository(db: db)
    lazy var categories: CategoryRepository = CategoryRepository(db: db)
    lazy var institutions: InstitutionRepository = InstitutionRepository(db: db)
    lazy var importBatches: ImportBatchRepository = ImportBatchRepository(db: db)
    lazy var importTemplates: ImportTemplateRepository = ImportTemplateRepository(db: db)

    private init(db: any PowerSyncDatabaseProtocol) {
        self.db = db
    }

    /// Cria a instância e registra o schema. O PowerSync aplica o schema
    /// criando *views SQLite em runtime* sobre tabelas internas — não é
    /// migration tradicional. Mudar o schema entre versões é seguro: o
    /// PowerSync recria as views, sem perda de dados locais (desde que
    /// colunas removidas não sejam o que o app procura).
    static func setup() -> AppDatabase {
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
        return AppDatabase(db: database)
    }

    /// Usado apenas pelo fallback de `AppEnvironment` quando o setup real
    /// falha. Cria uma instância "vazia" pra manter o app compilável; qualquer
    /// query lança erro porque não há banco real por trás.
    static func placeholder() -> AppDatabase {
        let database = PowerSyncDatabase(
            schema: appSchema,
            dbFilename: "placeholder.sqlite",
            logger: log.powerSyncLogger
        )
        return AppDatabase(db: database)
    }
}
