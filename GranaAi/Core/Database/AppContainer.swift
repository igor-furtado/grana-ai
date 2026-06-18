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
/// (banco + repositories + serviços), seguindo o padrão Composition Root
/// documentado em `AGENTS.md`.
///
/// Conceito-chave: **modo local-only**.
/// `PowerSyncDatabase` funciona perfeitamente como um SQLite local sem chamar
/// `connect(connector:)`. Isso significa que durante as Fases 0–4 o app já
/// persiste tudo localmente, e na Fase 5 *adicionamos* sync simplesmente
/// chamando `connect()` após o login. Não precisamos reescrever camada de
/// dados pra ativar o sync.
final class AppContainer {
    /// Nome do arquivo SQLite. O PowerSync coloca isso em
    /// `Application Support/databases/<dbFilename>` por padrão (subpasta fixa
    /// do SDK, não derivada do bundleId — `deleteDatabaseFiles()` depende disso).
    static let dbFilename = "grana_ai.sqlite"

    /// Versão do schema **lógico** do app (não confundir com a versão do
    /// SQLite/PowerSync). Toda mudança *incompatível* (remoção de coluna,
    /// renomeação, divisão de tabela) deve bumpar este número junto com a
    /// edição do `appSchema`. No próximo boot, `setup()` detecta a divergência
    /// com a versão salva em `UserDefaults` e **apaga o banco local** antes de
    /// recriar — migração destrutiva, viável enquanto não há sync.
    ///
    /// Histórico:
    /// - v1: schema inicial (Fase 0–4.5).
    /// - v2 (Fase 4.6): `accounts` perde `branch_id`, `account_number`,
    ///   `card_last_four`. Nascem `bank_accounts` e `credit_cards` 1:1.
    /// - v3 (Fase 4.7 revisada): projeção determinística de faturas,
    ///   estornos vinculados, créditos e histórico de configuração.
    static let schemaVersion = 3

    private static let schemaVersionDefaultsKey = "GranaAi.schemaVersion"

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
    lazy var transactions: TransactionRepository = .init(db: db)
    lazy var accounts: AccountRepository = .init(db: db)
    lazy var categories: CategoryRepository = .init(db: db)
    lazy var institutions: InstitutionRepository = .init(db: db)
    lazy var statements: StatementRepository = .init(db: db)
    lazy var importBatches: ImportBatchRepository = .init(db: db)
    lazy var categorizationCache: CategorizationCacheRepository = .init(
        db: db
    )
    lazy var categorizationCorrections: CategorizationCorrectionRepository =
        .init(db: db)

    /// Cliente HTTP da categorização assistida online.
    lazy var categorizationAPIClient: CategorizationAPIClient = .init()

    /// Pipeline de categorização automática. Preserva cache e correções
    /// locais do app enquanto a inferência é executada pelo backend online.
    lazy var categorization: CategorizationService = .init(
        client: categorizationAPIClient,
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
        wipeDatabaseIfSchemaChanged()

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

    /// Compara a versão de schema esperada (em `schemaVersion`) com a salva no
    /// `UserDefaults`. Se divergir (ou se não existir), apaga o arquivo do
    /// banco antes de o PowerSync abrir — força um boot limpo com o schema
    /// novo. Salva a versão nova depois pra próxima vez não disparar.
    ///
    /// **Por que destrutivo:** estamos pré-Fase 5 (sem sync), e mudanças
    /// estruturais como divisão de tabelas (`accounts` → `accounts` +
    /// `bank_accounts` + `credit_cards`) não casam com a abordagem do PowerSync
    /// (views sobre tabelas internas; remover/renomear coluna deixa dados
    /// órfãos). Re-importar é o caminho aceito — confirmado na decisão da
    /// Fase 4.6.
    private static func wipeDatabaseIfSchemaChanged() {
        let stored = UserDefaults.standard.integer(forKey: schemaVersionDefaultsKey)
        // Default `0` quando a chave nunca existiu (first install). Como
        // `schemaVersion` começou em `1` e bumpou pra `2`, qualquer instalação
        // pré-versionamento (que carrega dados do schema antigo) cai aqui e
        // toma o wipe. Single-user app, aceitável.
        guard stored != schemaVersion else { return }

        log.database.notice(
            "Schema mudou (\(stored) → \(schemaVersion)). Apagando banco local."
        )
        deleteDatabaseFiles()
        UserDefaults.standard.set(schemaVersion, forKey: schemaVersionDefaultsKey)
    }

    /// Apaga o `.sqlite` e seus side-files (`-wal`, `-shm`). PowerSync coloca
    /// tudo dentro de `Application Support/databases/` (subpasta fixa do SDK,
    /// não derivada do bundleId). Se o diretório não existir (primeira
    /// execução), os removes são no-op.
    private static func deleteDatabaseFiles() {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            log.database.error("Não foi possível resolver diretório do banco pra wipe.")
            return
        }

        let dir = appSupport.appendingPathComponent("databases", isDirectory: true)
        for suffix in ["", "-wal", "-shm"] {
            let url = dir.appendingPathComponent(dbFilename + suffix)
            try? fm.removeItem(at: url)
        }
    }

    /// Apaga o banco local do disco por solicitação explícita do usuário (ação
    /// "Apagar banco de dados" em Ajustes → Avançado). Espelha o que o
    /// `wipeDatabaseIfSchemaChanged` faz no boot, mas em runtime e disparado
    /// pela UI.
    ///
    /// **Caller obrigatoriamente encerra o app em seguida** (`NSApp.terminate`)
    /// — o PowerSync mantém handles abertos enquanto o processo vive, então
    /// apagar com a app rodando deixa o estado em memória inconsistente. O OS
    /// libera os handles no exit, e o próximo boot recria do zero pelo
    /// `Seed.runIfNeeded`.
    static func wipeLocalDatabase() {
        log.database.notice("Apagando banco local por solicitação do usuário.")
        deleteDatabaseFiles()
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
