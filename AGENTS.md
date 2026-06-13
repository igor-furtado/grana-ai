# AGENTS.md

Guia operacional e técnico para agentes neste repositório.

## Antes de alterar código

1. Leia este arquivo e `CONTEXT.md`. Consulte ADRs relacionados em `docs/adr/`, quando existirem.
2. Inspecione `git status --short` e preserve mudanças do usuário. Não reverta, reformate nem inclua arquivos alheios.
3. Use `ROADMAP.md` apenas como contexto de planejamento; ele não define regras nem limita pedidos explícitos.
4. Confirme a implementação atual no código, testes, `project.pbxproj`, `.swiftformat` e `.swiftlint.yml`.

`CONTEXT.md` define o vocabulário de domínio. Este arquivo define convenções de implementação. Código e configurações
mostram o estado atual. Em divergências, não normalize silenciosamente: corrija a fonte obsoleta ou sinalize o conflito.

## Stack e escopo técnico

- App exclusivo para macOS, com SwiftUI, Observation (`@Observable`) e Swift Charts.
- Target macOS `26.1`, isolamento padrão `MainActor`.
- Persistência local-first via produto estático `PowerSync`, versão mínima `1.13.1`.
- Testes com Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`).
- IA via shell-out ao `claude`, usando a assinatura local do usuário.
- App Sandbox permanece desativado para permitir `Process`.
- Não adicione dependências nem troque a stack sem pedido explícito.

## Arquitetura

Fluxo obrigatório:

```text
SwiftUI View -> @Observable Store -> Repository -> PowerSyncDatabase
```

- Views não executam SQL nem instanciam repositories.
- Stores recebem `AppContainer`; coordenam estado e operações.
- Repositories concentram queries, prepared statements e mapeamento entre rows e models.
- `AppContainer` é o composition root e expõe repositories e serviços.
- O app sempre lê e escreve no PowerSync local. Supabase direto só para autenticação ou dados deliberadamente fora do sync.
- Use `watch()` para listas reativas; `getAll()` para snapshots e agregações sob demanda.
- Agregue em SQL quando possível. Para dia e fuso local, carregue apenas as colunas necessárias e agregue em Swift com
  `Calendar`.
- Operações consistentes com múltiplas etapas usam `writeTransaction`.

## Invariantes de implementação

- Toda transação referencia exatamente uma conta e uma categoria; subcategoria é opcional.
- Dinheiro usa `Decimal` no Swift e `Int64` em centavos no banco. Nunca use `Double`; converta com `Converters`.
- `Transaction.amount` é sempre magnitude positiva; `CategoryKind` determina receita, despesa ou transferência.
- Datas são ISO8601 UTC no banco. Comparações diárias usam janela SQL e `Calendar` local; nunca
  `SUBSTR(occurred_at, ...)`.
- Transferências não entram em cards nem gráficos de receitas e despesas.
- IDs de domínio são UUIDs; FKs são persistidas como `uuidString`.
- Moeda padrão: BRL.
- `accounts` contém apenas campos universais. Dados específicos ficam em `bank_accounts` e `credit_cards`, escritos
  atomicamente.
- Toda transação de cartão exige fatura. Mudança de conta ou data re-resolve o ciclo.
- Datas de fechamento e vencimento de uma fatura são snapshots; mudanças futuras no cartão não as alteram.
- Compra se vincula à fatura por `transactions.statement_id`; pagamento se vincula por `statement_payments`.
- Escritas que afetam compras ou pagamentos recalculam total e status da fatura na mesma transação de banco.
- Categorias são hierárquicas. Apenas raízes têm ícone; subcategorias herdam o ícone na UI.
- O schema PowerSync não oferece `NOT NULL`; models, inserts e mappers garantem obrigatoriedade.

Detalhes PowerSync:

- `PowerSyncDatabase(...)` é factory; propriedades usam `any PowerSyncDatabaseProtocol`.
- Use a API direta e o produto `PowerSync`. Não migre para `PowerSyncDynamic`, `PowerSyncGRDB` nem camada GRDB.
- Passe valores separadamente em prepared statements; nunca interpole parâmetros em SQL.
- Mappers e utilitários usados em closures PowerSync `@Sendable` devem ser `nonisolated`.

## Convenções Swift e UI

- Use `@Observable`; não introduza `ObservableObject`, `@Published` nem Combine.
- Use `async/await`.
- Estado apenas visual fica em `@State`; dados persistidos ou compartilhados ficam no Store.
- Mantenha Views pequenas e extraia subviews quando acumularem responsabilidades.
- Não adicione `#Preview`; valide UI executando o app.
- Ícones de UI vêm de `AppIcon`; ícones de categoria passam por `CategoryIcon` e seus mappings.
- Cores novas entram em `Assets.xcassets` com variante dark.
- Erros de domínio são enums `LocalizedError`, com mensagens em PT-BR.
- Comentários explicam decisões e motivos, não narram o código.
- Arquivos com interpolação de `Logger` importam `OSLog`.
- Tipos e arquivos usam `PascalCase`; funções e propriedades, `camelCase`; tabelas e colunas, `snake_case`.
- TODOs usam `// TODO(fase-N): ...`.
- Siga `.swiftformat` e `.swiftlint.yml`; não afrouxe regras customizadas para acomodar uma mudança.

## Feedback e logs

- Toda mensagem visível passa por `NoticeCenter`.
- Relate erros onde forem consumidos. `catch` que relança ou transforma não gera toast.
- `CancellationError` é esperado e permanece silencioso.
- Não faça `log.error` antes de `NoticeCenter.report`; o centro já registra o notice.
- Use as categorias de `Core/Logging/Logger.swift`; não use `print`.
- Nunca registre valores de transações, credenciais ou dados financeiros sensíveis.

## Importação e IA

- `ImportStore.supportedExtensions` é a fonte dos formatos aceitos.
- Importadores aplicam `abs()` antes de persistir valores.
- Preserve as regras existentes de deduplicação por formato.
- Cada `STMTRS` OFX gera um `ImportBatch`; múltiplos extratos são persistidos em uma única `writeTransaction`.
- `ImportBatch` permanece reversível, sem transações órfãs.
- A categorização assistida ocorre antes do commit final.
- Não substitua o shell-out `claude` por API HTTP paga sem decisão explícita.

## Onde alterar

| Necessidade | Local principal |
|---|---|
| Nova tabela | `GranaAi/Core/Database/AppSchema.swift`, model e repository |
| Mudança incompatível de schema local | `AppSchema.swift` e bump de `AppContainer.schemaVersion` |
| Nova categoria padrão | `GranaAi/Core/Database/CategorySeedData.swift` |
| Novo formato de importação | `GranaAi/Core/Import/`, `ImportStore` e step de revisão |
| Novo repository ou serviço | Registro no `AppContainer` |
| Novo ícone de UI | `GranaAi/Shared/Components/AppIcon.swift` |
| Novo ícone de categoria | `GranaAi/Models/Category.swift` e extensions de `CategoryIcon` |
| Feedback ao usuário | `NoticeCenter` |
| Nova categoria de log | `GranaAi/Core/Logging/Logger.swift` |

## Configuração e validação

Quando necessário, crie a configuração local a partir do template:

```bash
cp GranaAi/Config.example.swift GranaAi/Config.swift
```

`Config.swift` permanece ignorado pelo Git.

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

- Rode primeiro a validação mais estreita que cobre a mudança; amplie para build e testes completos quando o impacto for
  transversal.
- Teste regras de domínio, parsers, conversões, queries e regressões.
- Para repositories, prefira PowerSync em memória com `dbFilename: ":memory:"`.
- Injete `Calendar` em comportamento dependente de dia ou fuso.
- Informe validações não executadas.
- Não faça stage, commit, push, mudanças destrutivas de banco nem alterações de dependências sem pedido explícito.

## Agent skills

### Issue tracker

Issues e PRDs são rastreados no GitHub Issues via `gh`. Veja `docs/agents/issue-tracker.md`.

### Triage labels

Usa os cinco rótulos canônicos sem renomeações. Veja `docs/agents/triage-labels.md`.

### Domain docs

Layout single-context. Veja `docs/agents/domain.md`.
