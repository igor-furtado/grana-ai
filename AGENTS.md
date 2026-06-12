# AGENTS.md

Norma única do projeto e guia operacional de agentes.

## Antes de alterar código

1. Leia este arquivo.
2. Inspecione `git status --short`; preserve mudanças do usuário. Não reverta, reformate ou inclua arquivos alheios.
3. Consulte `ROADMAP.md` só para contexto de planejamento. Não define regras, limita escopo nem substitui pedido explícito.
4. Confirme implementação atual no código e configurações antes de editar.

`AGENTS.md` é fonte oficial de decisões e convenções. Código, testes, `project.pbxproj`, `.swiftformat` e `.swiftlint.yml` mostram implementação atual. Em divergência, não normalize silenciosamente: corrija lado obsoleto ou sinalize conflito.

## Projeto

- App financeiro pessoal, single-user, exclusivo macOS.
- Ferramenta de análise e organização; não opera banco ou corretora.
- Sem multi-tenancy, onboarding genérico ou abstrações para distribuição pública.
- SwiftUI, Swift 5.9+, Observation (`@Observable`) e Swift Charts.
- Persistência local-first via PowerSync `1.13.1`; sync Supabase futuro.
- Target macOS `26.1`.
- IA via shell-out ao `claude`, usando assinatura local do usuário.
- App Sandbox intencionalmente desativado para permitir `Process`.
- Testes: Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`).

Não adicione dependências nem troque stack sem pedido explícito.

## Estrutura

```text
GranaAi/
├── App/             # entry point, environment e composição da UI
├── Core/            # banco, importação, IA, networking, erros e logging
├── Models/          # modelos de domínio
├── Repositories/    # SQL e mapeamento Row <-> Model
├── Stores/          # estado @Observable e orquestração
├── Features/        # telas por feature
├── Shared/          # componentes e tema reutilizáveis
└── Resources/       # Assets.xcassets
GranaAiTests/        # testes unitários e de integração em memória
```

Fluxo obrigatório:

```text
SwiftUI View -> @Observable Store -> Repository -> PowerSyncDatabase
```

- Views não executam SQL nem instanciam repositories.
- Stores recebem `AppContainer`; coordenam estado e operações.
- Repositories concentram queries, prepared statements, mappers.
- `AppContainer`: composition root, expõe repositories e serviços.
- App sempre lê e escreve no PowerSync local. Supabase direto só para autenticação ou dados deliberadamente fora do sync.
- Use `watch()` para listas reativas; `getAll()` para snapshots e agregações sob demanda.
- Agregue em SQL quando possível. Para dia/fuso local, carregue só colunas necessárias; agregue em Swift com `Calendar`.
- Operações multi-etapa consistentes usam `writeTransaction`.

Detalhes PowerSync imutáveis sem intenção:

- `PowerSyncDatabase(...)` é factory; propriedades usam `any PowerSyncDatabaseProtocol`.
- Use API PowerSync direta e produto estático `PowerSync`. Não migre para `PowerSyncDynamic`, `PowerSyncGRDB` ou camada GRDB.
- Envie parâmetros SQL separados em prepared statements; nunca interpole valores em strings SQL.
- Schema PowerSync não oferece `NOT NULL`; models, inserts e mappers garantem obrigatoriedade.

## Invariantes obrigatórias

1. Toda `Transaction` pertence a `Account` e `Category`.
2. `Transaction.amount` sempre magnitude positiva. Entrada, saída ou transferência vem de `CategoryKind`.
3. Dinheiro: `Decimal` no Swift, `Int64` em centavos no banco. Nunca `Double`. Converta com `Converters`.
4. Datas: ISO8601 UTC no banco. Comparação diária usa janela SQL e `Calendar` local; nunca `SUBSTR(occurred_at, ...)`.
5. Exclua transferências de cards e gráficos de receitas/despesas.
6. IDs de domínio: UUIDs; FKs persistidas como `uuidString`.
7. Moeda padrão: BRL.
8. Target usa isolamento padrão `MainActor`. Mappers e utilitários em closures PowerSync `@Sendable` devem ser `nonisolated`.
9. `accounts` só guarda campos universais. Específicos ficam em `bank_accounts` e `credit_cards`, escritos atomicamente.
10. Toda transação de cartão exige `statement_id`. Crie fatura sob demanda; mudança de conta ou data re-resolve ciclo.
11. `Statement.closingDate` e `dueDate` são snapshots do ciclo; configuração futura do cartão não os altera.
12. `transactions.statement_id`: compra -> fatura; `statement_payments`: transferência -> fatura paga. Escrita recalcula `total_amount_cents` e `paid_at` na mesma transação de banco.
13. Categorias hierárquicas via `parent_id`. Só raízes têm ícone; subcategorias herdam na UI.

## Convenções Swift

- Use `@Observable`; proíba `ObservableObject` e `@Published`.
- Use `async/await`; não introduza Combine.
- Prefira Views pequenas; extraia subviews quando tela acumular responsabilidades.
- Estado só visual em `@State`; dados persistidos ou compartilhados no Store.
- Não adicione `#Preview`. Valide UI rodando app.
- Ícones UI vêm de `AppIcon`; não espalhe strings SF Symbols nas Views.
- Ícones de categoria passam por `CategoryIcon` e mappings.
- Cor nova entra em `Assets.xcassets` com variante dark.
- Erros de domínio: enums `LocalizedError`, mensagens PT-BR.
- Comentários explicam decisões e motivos, não narram código.
- Arquivos com interpolação de `Logger` importam `OSLog`.
- Tipos e arquivos: `PascalCase`; funções e propriedades: `camelCase`; tabelas e colunas: `snake_case`.
- TODOs usam `// TODO(fase-N): ...`.
- Siga `.swiftformat` e `.swiftlint.yml`; não afrouxe regras customizadas para passar mudança.

## Feedback e logs

- Toda mensagem visível passa por `NoticeCenter`.
- Relate erro onde consumido. `catch` que relança ou transforma não gera toast.
- `CancellationError` é esperado; mantenha silencioso.
- Não duplique `log.error` antes de `NoticeCenter.report`; centro já registra notice.
- Use categorias de `Core/Logging/Logger.swift`; não use `print`.
- Nunca registre valores de transações, credenciais ou dados financeiros sensíveis.

## Importação e IA

- `ImportStore.supportedExtensions` define formatos aceitos.
- Formatos atuais: OFX e CSV cartão Inter.
- Importadores aplicam `abs()` antes de persistir valores.
- Deduplicação OFX: `external_id`/FITID. CSV Inter: heurística existente.
- Cada `STMTRS` OFX gera `ImportBatch`; múltiplos extratos persistem em uma única `writeTransaction`.
- `ImportBatch` permanece reversível, sem transações órfãs.
- Categorização IA ocorre antes do commit final.
- Não troque shell-out `claude` por API HTTP paga sem decisão explícita.

## Onde alterar

| Necessidade | Local principal |
|---|---|
| Nova tabela | `GranaAi/Core/Database/AppSchema.swift`, model e repository |
| Mudança incompatível de schema local | `AppSchema.swift` e bump de `AppContainer.schemaVersion` |
| Nova categoria padrão | `GranaAi/Core/Database/CategorySeedData.swift` |
| Novo formato de importação | `GranaAi/Core/Import/`, `ImportStore` e step de revisão |
| Novo repository/serviço | Registro no `AppContainer` |
| Novo ícone de UI | `GranaAi/Shared/Components/AppIcon.swift` |
| Novo ícone de categoria | `GranaAi/Models/Category.swift` e extensions de `CategoryIcon` |
| Feedback ao usuário | `NoticeCenter` |
| Nova categoria de log | `GranaAi/Core/Logging/Logger.swift` |

## Configuração e comandos

Quando necessário, crie configuração local do template:

```bash
cp GranaAi/Config.example.swift GranaAi/Config.swift
```

`Config.swift` contém configuração local; permanece ignorado pelo Git.

Abra `GranaAi.xcodeproj`, selecione `My Mac`, execute com `Cmd+R`.

Validação CLI:

```bash
xcodebuild \
  -project GranaAi.xcodeproj \
  -scheme GranaAi \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/GranaAiDerivedData \
  build

xcodebuild \
  -project GranaAi.xcodeproj \
  -scheme GranaAi \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/GranaAiDerivedData \
  test

swiftformat --lint .
swiftlint
```

SwiftLint também roda como build phase. Primeira build pode resolver e compilar dependências pesadas PowerSync.

## Testes e entrega

- Teste regras de domínio, parsers, conversões, queries e regressões.
- Para repositories, prefira PowerSync em memória com `dbFilename: ":memory:"`.
- Injete `Calendar` para comportamento dependente de dia ou fuso.
- Antes de concluir, rode validação mais estreita que cubra mudança; amplie para build e testes completos se impacto transversal.
- Informe validação não executada.
- Não faça stage, commit, push, mudança destrutiva de banco ou dependências sem pedido explícito.
