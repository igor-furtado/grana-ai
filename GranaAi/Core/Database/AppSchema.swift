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
    Table(
        name: "transactions",
        columns: [
            .text("account_id"),
            .text("category_id"),
            .text("subcategory_id"), // nullable
            .integer("amount_cents"), // valor em centavos (ver §4 PROJECT.md)
            .text("occurred_at"), // ISO8601, hora local
            .text("description"),
            .text("notes"), // nullable
            // Fase 3: link pro batch que originou a transaction (NULL = entrada
            // manual). Permite o "desfazer batch" via DELETE WHERE import_batch_id = ?.
            .text("import_batch_id"), // nullable
            // ID externo da instituição (ex: FITID do OFX). Usado pra detectar
            // duplicata exata em re-imports do mesmo extrato.
            .text("external_id"), // nullable
            // Fase 4.5: contraparte quando a categoria da transação tem
            // `kind = transfer`. O cálculo de saldo soma o `amount` nesta
            // conta de destino e subtrai da `account_id`. NULL pra qualquer
            // transação que não é transferência.
            .text("destination_account_id"),
            // Fase 4.7: vínculo "esta compra entrou nesta fatura". Só
            // preenchido pra transações em conta-cartão (invariante do
            // TransactionRepository — PowerSync não tem NOT NULL). Distinto
            // de `statement_payments` (transferência → fatura paga).
            .text("statement_id"), // nullable
            .text("created_at"),
            .text("updated_at"),
        ]
    ),

    // `accounts` é o **primitivo financeiro** — só carrega o que é universal
    // entre todos os tipos. A partir da Fase 4.6, campos específicos por tipo
    // vivem em tabelas-irmãs 1:1 (`bank_accounts` pra `checking`, `credit_cards`
    // pra `creditCard`), evitando que esta tabela vire god class à medida que
    // novos tipos forem introduzidos (poupança, corretora, etc.).
    Table(
        name: "accounts",
        columns: [
            .text("type"), // enum AccountType serializado
            .integer("initial_balance_cents"),
            .integer("archived"), // 0/1
            // Fase 3: vínculo com `institutions`. Tecnicamente nullable no
            // schema (PowerSync não tem NOT NULL — ver §invariantes do
            // CLAUDE.md), mas a partir da Fase 4.5 vira **invariante de
            // aplicação**: o display name depende dela, e o `AccountFormView`
            // bloqueia o save sem instituição. Mappers leem como opcional
            // só pra tolerar contas legadas pré-Fase 4.5.
            .text("institution_id"),
            .text("currency"), // ISO 4217 (default "BRL" preenchido pelo Repository)
            .text("created_at"),
            .text("updated_at"),
        ]
    ),

    // Fase 4.6: detalhes específicos de conta bancária (1:1 com `accounts`
    // onde `type = checking`). `account_id` é a chave estrangeira **e** chave
    // primária lógica — só pode existir uma linha por Account. Habilita o
    // auto-detect de OFX via tripla `institution_id + branch_id + account_number`.
    Table(
        name: "bank_accounts",
        columns: [
            .text("account_id"),
            .text("branch_id"), // nullable — agência (alguns OFX não trazem)
            .text("account_number"), // número da conta no banco
            .text("created_at"),
            .text("updated_at"),
        ]
    ),

    // Fase 4.6: detalhes específicos de cartão de crédito (1:1 com `accounts`
    // onde `type = creditCard`). `account_id` é a chave estrangeira lógica.
    // `card_last_four` segue convenção PCI — nunca o PAN completo.
    // `statement_closing_day` (1-31) e `payment_due_day` (1-31) alimentam o
    // resolver de janela de Fatura na Fase 4.7.
    Table(
        name: "credit_cards",
        columns: [
            .text("account_id"),
            .text("card_last_four"), // 4 dígitos
            .integer("credit_limit_cents"), // nullable — usuário pode não saber/quer
            .integer("statement_closing_day"), // 1-31
            .integer("payment_due_day"), // 1-31
            .text("created_at"),
            .text("updated_at"),
        ]
    ),

    // Fase 4.7: Fatura (Statement) de cartão. Uma linha por ciclo de
    // fechamento de uma conta-cartão. Criada **lazy** pelo
    // TransactionRepository quando uma transação de cartão entra e ainda
    // não há Statement cobrindo sua data. `closing_date`/`due_date` são
    // snapshot imutável — não mudam se o usuário editar
    // `statement_closing_day` na `credit_cards` depois. `paid_at` é cache
    // denormalizado, setado quando `SUM(statement_payments.applied_amount_cents) >= total_amount_cents`.
    Table(
        name: "statements",
        columns: [
            .text("account_id"), // FK pra `accounts` (type=creditCard)
            .text("closing_date"), // ISO8601 — dia que a fatura fecha
            .text("due_date"), // ISO8601 — dia que vence
            .integer("total_amount_cents"), // recalculado a cada write em transactions
            .text("paid_at"), // nullable — cache; setado quando saldo é coberto
            .text("source_filename"), // nullable — preenchido em CSV import
            .text("created_at"),
            .text("updated_at"),
        ]
    ),

    // Fase 4.7: junction N:N entre Statements e transferências que pagam
    // elas. Cobre 2 casos: (a) múltiplas transferências pagando a mesma
    // fatura (adiantamento); (b) 1 transferência fatiada entre Faturas
    // (split). Toda escrita aqui recalcula `statements.paid_at` da fatura
    // afetada na mesma writeTransaction.
    Table(
        name: "statement_payments",
        columns: [
            .text("statement_id"), // FK pra `statements`
            .text("transaction_id"), // FK pra `transactions` (a transferência)
            .integer("applied_amount_cents"), // quanto desta transferência foi aplicado
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
            .text("code"), // FEBRABAN/COMPE (ex: "077")
            .text("name"), // "Banco Inter"
            .text("kind"), // raw value de InstitutionKind
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
            .text("parent_id"), // nullable — null = raiz
            .text("name"),
            .text("kind"), // expense | income | transfer
            .text("slug"), // nullable — só categorias raiz têm slug; mapping slug→ícone vive em CategoryIcon+Slug.swift
            .text("created_at"),
        ]
    ),

    // Fase 3: import_batches (origem de cada transaction importada via OFX).
    // Permite undo atômico de um import inteiro via DELETE em cascata.
    Table(
        name: "import_batches",
        columns: [
            .text("source_filename"),
            .text("account_id"),
            .integer("row_count"),
            .text("imported_at"), // ISO8601
            .text("created_at"),
            .text("updated_at"),
        ]
    ),

    // Fase 4: cache de categorização e correções do usuário.
    //
    // `categorization_cache` é a porta lookup-by-description-hash que evita
    // chamar a IA pra descrições idênticas — chave é SHA256 da descrição
    // normalizada (lowercase + trim + sem acentos + sem sequências de dígitos
    // longos como FITID/CPF). Cada hit economiza uma chamada à API.
    //
    // `model` é guardado pra invalidação ao trocar de modelo: se mudarmos pra
    // Sonnet, a query do service filtra por `model = configAtual` e cache
    // antigo vira inerte automaticamente — sem precisar de migration.
    //
    // PowerSync não tem NOT NULL no schema (CLAUDE.md invariante 5) — todas
    // as colunas são nullable por baixo. A obrigatoriedade vive nas structs
    // Swift e na lógica de insert dos Repositories.
    Table(
        name: "categorization_cache",
        columns: [
            .text("description_hash"), // SHA256 hex da descrição normalizada
            .text("normalized_description"), // pra debug + invalidação por correção
            .text("category_id"),
            .text("subcategory_id"), // nullable
            .real("confidence"), // 0.0–1.0
            .text("model"), // ex: "claude-haiku-4-5-20251001"
            .text("created_at"),
            .text("updated_at"),
        ]
    ),

    // Correções explícitas do usuário viram exemplos few-shot do prompt das
    // próximas categorizações. `ORDER BY created_at DESC LIMIT N` na seleção
    // pega as N mais recentes — usuário corrige um padrão errado e o
    // aprendizado é imediato. Mantém histórico completo (não-destrutivo).
    Table(
        name: "categorization_corrections",
        columns: [
            .text("description_hash"),
            .text("normalized_description"),
            .text("original_category_id"), // nullable — o que a IA sugeriu
            .text("original_subcategory_id"), // nullable
            .text("corrected_category_id"),
            .text("corrected_subcategory_id"), // nullable
            .text("transaction_id"), // rastreabilidade pra auditoria
            .text("created_at"),
        ]
    ),

    // Fase 6: assets, holdings, quotes
])
