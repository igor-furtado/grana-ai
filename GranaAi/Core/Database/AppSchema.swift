import PowerSync

/// Schema declarativo do PowerSync.
///
/// Diferença em relação a migrations tradicionais (Core Data, Room, etc.):
/// - Não escrevemos `CREATE TABLE` nem versionamos passos de upgrade.
/// - Declaramos as tabelas como código Swift e o PowerSync materializa elas
///   em runtime como **views SQLite** sobre suas tabelas internas
///   (`ps_data__<nome>`, `ps_oplog`, etc.). Isso permite que o sync engine
///   versione cada linha individualmente pra resolver conflitos.
/// - Para evoluir o schema, basta editar este arquivo. Na próxima execução
///   as views são recriadas. Dados locais persistem; só mudam as views.
///
/// **Nota sobre IDs e nullability:**
/// - PowerSync injeta automaticamente um `id text` em toda tabela (não declaramos).
///   Em `INSERT` sem `id`, usar `uuid()` (função SQL do PowerSync) — em código
///   Swift onde precisamos do id antes do insert, gerar com `UUID().uuidString`.
/// - Colunas declaradas aqui são **todas nullable** no SQLite — o PowerSync não
///   tem flag de NOT NULL no schema. Constraint de obrigatoriedade fica no
///   model Swift (propriedade não-opcional) + na lógica de insert.
let appSchema = Schema(tables: [
    // Fase 1: transactions, accounts, categories
    Table(
        name: "transactions",
        columns: [
            .text("account_id"),
            .text("category_id"),
            .text("subcategory_id"),     // nullable
            .integer("amount_cents"),    // valor em centavos (ver §4 PROJECT.md)
            .text("occurred_at"),        // ISO8601, hora local
            .text("description"),
            .text("notes"),              // nullable
            // Fase 3: link pro batch que originou a transaction (NULL = entrada
            // manual). Permite o "desfazer batch" via DELETE WHERE import_batch_id = ?.
            .text("import_batch_id"),    // nullable
            // ID externo da instituição (ex: FITID do OFX). Usado pra detectar
            // duplicata exata em re-imports do mesmo extrato.
            .text("external_id"),        // nullable
            .text("created_at"),
            .text("updated_at"),
        ]
    ),

    Table(
        name: "accounts",
        columns: [
            .text("name"),
            .text("type"),                  // enum AccountType serializado
            .integer("initial_balance_cents"),
            .integer("archived"),           // 0/1
            // Fase 3: vínculo opcional com `institutions`. NULL pra contas que
            // não são de banco (ex: "Carteira").
            .text("institution_id"),        // nullable
            .text("branch_id"),             // nullable — agência
            .text("account_number"),        // nullable — número da conta no banco
            .text("currency"),              // ISO 4217 (default "BRL" preenchido pelo Repository)
            .text("created_at"),
            .text("updated_at"),
        ]
    ),

    // Fase 3: instituições financeiras. Tabela própria pra que várias accounts
    // possam compartilhar a mesma instituição (ex: conta corrente + poupança
    // no mesmo banco). `kind` é o enum `InstitutionKind` — auto-detect via FID
    // do OFX usa ele pra resolver ícone/logo.
    Table(
        name: "institutions",
        columns: [
            .text("code"),                  // FEBRABAN/COMPE (ex: "077")
            .text("name"),                  // "Banco Inter"
            .text("kind"),                  // raw value de InstitutionKind
            .text("created_at"),
            .text("updated_at"),
        ]
    ),

    // Categorias hierárquicas via self-FK (`parent_id`). Preferido sobre dois
    // campos planos `category`/`subcategory` na transaction porque permite
    // editar nomes e adicionar subcategorias sem migração.
    Table(
        name: "categories",
        columns: [
            .text("parent_id"),    // nullable — null = raiz
            .text("name"),
            .text("kind"),         // expense | income | transfer
            .text("icon"),         // nullable — só categorias raiz têm ícone (CategoryIcon rawValue)
            .text("created_at"),
        ]
    ),

    // Fase 3: import_batches, import_templates
    Table(
        name: "import_batches",
        columns: [
            .text("source_filename"),
            .text("source_kind"),        // "xlsx" | "csv"
            .text("template_id"),        // nullable — quando salvou template novo, vira FK
            .text("account_id"),
            .integer("row_count"),
            .text("imported_at"),        // ISO8601
            .text("created_at"),
            .text("updated_at"),
        ]
    ),

    Table(
        name: "import_templates",
        columns: [
            .text("name"),
            .text("source_kind"),
            .text("mapping_json"),       // ColumnMapping serializado
            .text("date_format"),        // ex: "dd/MM/yyyy"
            .text("decimal_separator"),  // "," ou "."
            .text("default_account_id"), // nullable
            .text("created_at"),
            .text("updated_at"),
        ]
    ),

    // Fase 6: assets, holdings, quotes
    // Fase 7: chat_messages, categorization_cache
])
