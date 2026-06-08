# ROADMAP.md — Fases de desenvolvimento

> Cada fase entrega algo **funcional e visível**. Não pular fases. Concluir uma antes de iniciar a próxima.

---

## Fase 0 — Fundação (setup do projeto) ✅


## Fase 1 — Schema PowerSync e CRUD de transações (manual, local-only) ✅


## Fase 2 — Dashboard básico ✅


## Fase 3 — Importação de planilhas (XLSX e CSV) e extratos OFX ✅


## Fase 4 — Integração Claude API: categorização automática ✅

## Fase 4.5 — Cartões de Crédito ✅


## Fase 4.6 — Refator estrutural de `Account`

**Objetivo:** `Account` vira primitivo financeiro puro. Campos específicos por tipo (banco, cartão) viram tabelas-irmãs 1:1 — evita `Account` virar god class à medida que tipos novos entram (poupança, corretora). Pré-requisito da Fase 4.7 (Faturas), que precisa adicionar `statementClosingDay`/`paymentDueDay` ao cartão sem inflar `Account`.

**Decisões fixas:**
- `accounts.type` continua sendo `checking | creditCard`. Cada cartão segue sendo 1 row em `accounts` (não vira filho de outra conta). O "1:N de cartões por instituição" já existe via `institution_id` compartilhado — não precisa mudar nada pra isso.
- Cartão **não é** filho de conta corrente no schema. Vinculo de "fonte de pagamento" emerge naturalmente da transferência categorizada (Fase 4.7), não de FK.

**Entregáveis:**
- Nova tabela `bank_accounts(account_id PK/FK, branch_id, account_number)`. 1:1 com `accounts` onde `type = checking`. `branch_id` e `account_number` saem de `accounts`.
- Nova tabela `credit_cards(account_id PK/FK, card_last_four, credit_limit_cents, statement_closing_day, payment_due_day)`. 1:1 com `accounts` onde `type = creditCard`. `card_last_four` sai de `accounts`. `credit_limit_cents`, `statement_closing_day`, `payment_due_day` entram novos.
- `accounts` final: `id`, `type`, `institution_id`, `initial_balance`, `archived`, `currency`, `created_at`, `updated_at`.
- `AccountRepository`: novos métodos `bankDetails(for accountId:)` e `creditCardDetails(for accountId:)`. CRUD de Account passa a aceitar opcionalmente os details e escreve as 2 linhas em `writeTransaction` atômico.
- `AccountStore.displayName(for:)` reescrito pra receber `accounts + institutions + creditCardDetails` (mantém formato `Inter Cartão · ••••1234`).
- **`AccountFormView` reaproveitado com seções condicionais por tipo:**
  - Seção comum sempre visível: instituição, tipo (picker `checking | creditCard`), saldo inicial, moeda.
  - Quando `type = checking`: campos de agência + número da conta.
  - Quando `type = creditCard`: últimos 4 dígitos, limite, dia de fechamento (1–31), dia de vencimento (1–31).
  - Submit escreve `accounts` + (`bank_accounts` ou `credit_cards`) numa única `writeTransaction` atômica.
  - `AccountsView` sidebar/toolbar mantém um único botão "Nova conta" que abre o form.
- OFX auto-detect: o triple `institution + branch + account_number` passa a fazer JOIN com `bank_accounts` em vez de ler de `accounts`.
- **Migração destrutiva local** (sem sync ainda): script de migração apaga `accounts`/`transactions`/`import_batches` e recria com schema novo. Usuário re-importa OFXs e os 2 CSVs do Inter do zero — aceitável porque a Fase 4.7 já planejava re-import dos CSVs.

**Sem isto, não avança:** ver `Account` sem campos opcionais específicos por tipo; cadastrar dia de fechamento/vencimento de um cartão; ter form dedicado pra cartão.

---

## Fase 4.7 — Faturas (Statements) de cartão

**Objetivo:** modelar `Statement` (Fatura) como entidade própria, criada lazy quando uma transação de cartão entra. Cada compra fica vinculada à Fatura do ciclo que a contém. Pagamento da fatura via extrato bancário marca a Statement como paga apontando pra transferência específica.

**Pré-requisito:** Fase 4.6 (campos `statement_closing_day` e `payment_due_day` na `credit_cards`).

**Entregáveis:**
- Nova tabela `statements(id, account_id FK, closing_date, due_date, total_amount_cents, paid_at?, source_filename?, created_at, updated_at)`. `account_id` aponta sempre pra `accounts` com `type = creditCard`. `closing_date`/`due_date` são **snapshot imutável** do ciclo — não mudam mesmo se o usuário editar `statement_closing_day` na `credit_cards` depois. `paid_at` é cache denormalizado, populado quando `SUM(applied_amount_cents) >= total_amount_cents` daquela Statement.
- Nova tabela junction `statement_payments(id, statement_id FK, transaction_id FK, applied_amount_cents, created_at, updated_at)`. Modela N:N entre Statements e transferências de pagamento. Cobre 2 casos: (a) múltiplas transferências pagando a mesma Statement (adiantamento — caso comum); (b) 1 transferência fatiada entre Statements (raro, mas suportado).
- Nova coluna `transactions.statement_id` (nullable). Obrigatória só pra transações em conta-cartão — invariante validada no `TransactionRepository`, não no schema (PowerSync não tem NOT NULL). É a vinculação **compra → fatura do ciclo**, distinta da vinculação **transferência → fatura paga** (que vive em `statement_payments`).
- **Resolver de janela:** função `StatementWindow.resolve(for accountId:, on date:)` que lê `credit_cards.statement_closing_day` + `payment_due_day` e devolve `(closingDate, dueDate)` do ciclo que cobre aquela data. Lógica: se `date.day <= closing_day` então a fatura fecha em `(date.year, date.month, closing_day)`; senão na do mês seguinte. `due_date` é `closingDate` + offset baseado em `payment_due_day` (rola pro mês seguinte se necessário).
- **Lazy creation hook** no `TransactionRepository`: na inserção/edição de transação em conta-cartão, resolve a janela → busca Statement existente por `(account_id, closing_date)` → cria se não existir → seta `statement_id` na transação. Re-resolve no edit se `occurred_at` mudar.
- **CSV import** (Inter) passa pelo mesmo hook automaticamente. Re-import dos 2 CSVs históricos gera Statements correspondentes.
- **Recálculo automático:** toda escrita em `transactions` (insert/update/delete) que toca uma transação em cartão → recalcula `statements.total_amount_cents` da Statement afetada. Toda escrita em `statement_payments` → recalcula `statements.paid_at` (set se `SUM(applied_amount_cents) >= total`, clear caso contrário). Tudo dentro da mesma `writeTransaction` que disparou a mudança.
- **Picker de pagamento (UX padrão):** ao categorizar transação de extrato como `transferencias / Transferência entre Contas` apontando pra conta-cartão de destino, abre sheet listando Statements daquela conta com `paid_at IS NULL`. Cada item mostra `total_amount_cents - SUM(applied)` ("Faltam R$ X de R$ Y"). Sugere por default a Statement cujo saldo restante mais se aproxima do valor da transferência. Confirmar cria 1 `statement_payment` com `applied_amount_cents = transação.amount_cents`.
- **Pagamento parcial / split (UX avançada):** mesmo picker tem um modo "Aplicar em mais de uma fatura" que permite distribuir o valor da transferência entre N Statements (input de valor por Statement, com validação `SUM <= transação.amount_cents`). Default fechado — só aparece se o usuário clicar pra expandir.
- **Cancelar/re-categorizar:** se a transferência for editada (categoria muda, destino muda, transação deletada), todas as `statement_payments` daquela transaction são removidas. Cada Statement afetada recalcula `paid_at`.
- **Dashboard:** novo card "Próxima fatura" (Statement em aberto cujo `closing_date` está mais próximo da data atual). Mostra total + valor já pago + saldo restante.
- **Detalhe de transação de cartão:** exibe a Statement à qual pertence (closing/due/status pago).
- **Detalhe de Statement:** lista compras vinculadas + lista de pagamentos aplicados (data, transação, valor).

**Sem isto, não avança:** importar fatura → ver entidade Statement com fechamento/vencimento/total; adiantar parte do pagamento → ver Statement com saldo restante decrescendo; quitar com pagamento final → ver Statement marcada como paga; dashboard mostrando "Próxima fatura" com progresso.

**TODOs / melhorias futuras (não bloqueiam a fase):**
- Auto-match silencioso quando valor da transferência == saldo restante exato de exatamente 1 Statement em aberto.
- Tela "Histórico de faturas" da conta-cartão (lista cronológica com status pago/aberto, link pras compras e pagamentos de cada).
- Warning quando editar `occurred_at` de uma transação fizer ela mudar de Statement (efeito colateral em saldos passados).
- Tratamento de overpayment (transferência > saldo da Statement): hoje o excesso fica sem destino. Futuro: oferecer aplicar excesso na próxima Statement do ciclo seguinte.

---

## Fase 5 — Sync via PowerSync + Supabase

**Objetivo:** dados ficam num backend remoto (Postgres via Supabase) com sync bidirecional, garantindo backup off-machine e abrindo caminho pra outros clientes no futuro se o roadmap mudar.

**Entregáveis:**
- Schema Supabase (Postgres) espelhando schema PowerSync (script SQL versionado)
- Row Level Security (RLS) configurado no Supabase
- Sync Streams configuradas no PowerSync Dashboard pra o usuário só ver seus dados
- `SupabaseConnector` implementando `PowerSyncBackendConnectorProtocol`:
  - `fetchCredentials()` → token JWT do Supabase
  - `uploadData()` → aplica writes da queue local no Postgres via Supabase client
- `AuthService` com magic link Supabase
- Tela de login (mostrada quando não autenticado)
- Chamada `db.connect(connector:)` após login
- Indicador visual de status de sync na UI (sync rodando / pendente / erro / offline)
- Tratamento gracioso: app continua funcionando offline, sync retoma sozinho

**Sem isto, não avança:** desligar a máquina, voltar depois e ter os dados intactos vindos do Supabase; reinstalar o app e recuperar tudo via sync.

---

## Fase 6 — Investimentos: Holdings e Quotes

**Objetivo:** registrar carteira de investimentos e ver patrimônio.

**Entregáveis:**
- Tabelas e models: `assets`, `holdings`, `quotes`
- Cadastro manual de operações de compra/venda
- Cálculo de preço médio
- Integração BRAPI: buscar cotações sob demanda (URLSession)
- Card "Patrimônio investido" no dashboard
- Gráfico de evolução do patrimônio (Swift Charts line)
- Tela "Carteira" listando holdings com valor atual e variação

**Sem isto, não avança:** ver patrimônio total atualizado e variação do dia.

---

## Fase 7 — Claude Chat sobre suas finanças

**Objetivo:** conversar com IA sobre seus dados financeiros.

**Entregáveis:**
- Tela de chat (Mac)
- Tool use: IA tem ferramentas pra consultar o banco (`getTransactions`, `getCategoryTotal`, `getHoldings`)
- Sistema de prompt com contexto do usuário (período corrente, taxonomia, padrões)
- Histórico de conversas salvo (tabela `chat_messages` — sincronizada via PowerSync também)
- Streaming de resposta
- Citação de transações específicas nas respostas (clicáveis)

**Sem isto, não avança:** perguntar "quanto gastei com restaurante esse mês comparado ao anterior?" e receber resposta correta com transações citadas.

---

## Fase 8+ — Features avançadas (a decidir conforme uso)

Possibilidades, sem ordem definida:
- Atalhos Siri pra adicionar gasto por voz
- Open Finance (quando viável tecnicamente)
- **Menu "Patrimônio"** — tela dedicada agregando net worth (saldos + investimentos da Fase 6 + ativos manuais tipo imóvel/veículo). Conteúdo: gráfico de linha de evolução do patrimônio líquido (rolling 12 meses / YTD / desde início), composição por classe, variação mês a mês.
- **Metas e orçamentos** — orçamento por categoria com gráfico de barra de progresso "gastei X de Y", alerta quando >80%, suporte a metas de poupança (ex: "guardar R$ 10k pra viagem até dez/2026").
- Relatórios fiscais (informe de rendimentos, ganho de capital)
- Notificações push (gasto incomum, vencimento)
- Backup/export pra planilha
- Multi-moeda
- Modo "preview de futuro" (projeções)

---

## Gráficos diferenciadores mapeados (a decidir)

Catálogo de visualizações vistas em apps concorrentes (Mint, YNAB, Monarch, Copilot, Empower) que ficaram **fora do MVP do dashboard**. Decidir caso a caso se valem implementar — ordem é por relação esforço/impacto, do mais barato pro mais caro.

- **Sparklines embutidas nos 4 cards** — mini-gráficos de 30/90 dias dentro de cada card. Reaproveita queries existentes, alto ganho visual, esforço baixo (LineMark sem eixos, frame pequeno). Estilo Copilot/Monarch.
- **Spending pace** — duas linhas no mesmo plano: ritmo de gasto ideal acumulado (pontilhada) vs. ritmo real (sólida). Resposta direta pra "estou no ritmo do mês?". Visual assinatura do Copilot Money.
- **Comparação YoY sobreposta** — duas linhas no mesmo eixo "mês do ano", uma do ano corrente outra do anterior. Empower e Copilot usam. Precisa de 13+ meses de histórico pra fazer sentido.
- **Burn-down do orçamento mensal** — linha do saldo restante do orçamento descendo até o fim do mês. Pareia bem com a feature "Metas e orçamentos" do Fase 8+.
- **Heatmap calendário (estilo GitHub contributions)** — grid dia × semana com cor = intensidade do gasto. Identifica padrão semanal (ex: "sextas custam o dobro"). Médio esforço em Swift Charts via `RectangleMark`.
- **Treemap de categorias** — retângulos aninhados, peso = total gasto. Útil quando taxonomia cresce (subcategorias com peso). Sem `TreemapMark` nativo — exige layout manual via `GeometryReader`.
- **Sankey de fluxo de caixa** — fluxo "fontes de renda → categorias de gasto + poupança". Feature "hero" do Monarch Money, gera marketing instagramável. Caro em Swift Charts (sem `SankeyMark`; precisa Canvas customizado), mas é o gráfico mais diferenciador do catálogo.

---

## Polimento HIG (pós-MVP)

Itens de conformidade com Apple Human Interface Guidelines mapeados durante o desenvolvimento mas não bloqueantes pro MVP single-user. Implementar conforme o app for ganhando tração e o atrito justificar o investimento.

- **Atalhos de teclado no menu bar** — hoje `⌘1..⌘9` funcionam globalmente via `.keyboardShortcut(_:)` nos `SidebarRow` Buttons (ver `ContentView.swift`), mas não aparecem no menu "View" porque `selection` é `@State` local da `ContentView`. Pra exibi-los em "View → Switch to Dashboard ⌘1" (padrão Apple), refatorar `selection` pra um `@Observable` compartilhado (ex: `NavigationCoordinator`) e adicionar `Commands { CommandMenu("View") { ... } }` em `GranaAiApp.swift`. Ganho: descobribilidade (Help → Search anuncia os atalhos), uniformidade com apps nativos. Custo: lift de estado + 1 enum scene com 9 botões.
- **Sidebar nativa via `List(selection:)`** — sidebar custom (ver `ContentView.sidebar`) usa `Button + onMoveCommand` em vez de `List` por causa do override visual de seleção (que vinha do `AccentColor` global). VoiceOver perde "row N of M" e drag-to-reorder gratuito. Vale revisitar quando o AccentColor virar pasta separada de "accent de seleção da sidebar" (`SidebarSelectionColor` no asset catalog) — aí dá pra voltar pro `List` nativo sem comprometer o look.
- **Atalhos extras** — `⌘N` (nova transação), `⌘F` (busca em transações), `⌘⇧I` (importar), `⌘,` (preferências/Avançado). Pareados com o item de menu bar acima.

---

## Como trabalhar com Claude Code em cada fase

1. Abrir nova sessão do Claude Code na pasta do projeto.
2. Pedir ao Claude (chat) o **prompt da Fase N**.
3. Colar o prompt no Claude Code.
4. Claude Code lê PROJECT.md + ROADMAP.md, executa a fase.
5. Você revisa o código gerado, **lê de fato**, faz perguntas sobre partes que não entendeu.
6. Roda, testa, anota issues.
7. Quando a fase está sólida, faz commit com tag `fase-N-completa`.
8. Atualiza este ROADMAP marcando a fase como ✅.
9. Próxima fase.

**Nunca pular fases.** Tentar fazer Fase 5 (sync) sem Fase 1 (CRUD local) é receita pra desastre arquitetural.
