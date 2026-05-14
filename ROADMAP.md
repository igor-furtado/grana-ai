# ROADMAP.md — Fases de desenvolvimento

> Cada fase entrega algo **funcional e visível**. Não pular fases. Concluir uma antes de iniciar a próxima.

---

## Fase 0 — Fundação (setup do projeto) ✅


## Fase 1 — Schema PowerSync e CRUD de transações (manual, local-only) ✅


## Fase 2 — Dashboard básico ✅


## Fase 3 — Importação de planilhas (XLSX e CSV) e extratos OFX ✅

**Objetivo:** importar histórico de transações de planilhas existentes e extratos bancários.

**Entregue:**
- Tela "Importar" no Mac com wizard de fase (`idle → loading → mapping/ofxReview → preview → confirming → done`)
- **CSV** (parser manual, autodetect `,` vs `;`, BOM UTF-8, CRLF, aspas escapadas)
- **XLSX** (CoreXLSX, shared strings, colunas esparsas)
- **OFX 1.x SGML + OFX 2.x XML** (não estava no escopo original — bônus): parser SGML lenient unificado, suporte a CHARSET 1252/Windows-1252 dos extratos brasileiros
- Mapeamento interativo de colunas (CSV/XLSX) — exclusividade entre `amount` unificado e `débito`/`crédito` separados
- Templates salvos por nome com `mapping_json` reutilizável
- `ImportBatch` + cascade delete pra "desfazer lote" atômico (writeTransaction)
- Preview com status por linha (`valid`/`duplicate`/`invalidDate`/`invalidAmount`/`missingFields`)
- Detecção de duplicata CSV/XLSX por (dia local + valor + descrição) — calendário injetável pra testes
- Detecção de duplicata OFX exata via FITID (batched: um Set por conta, evita N+1)
- **Multi-account no OFX**: cada `STMTRS` vira batch independente; auto-detect de instituição via FEBRABAN code; auto-create de Account + Institution se inéditas, tudo na mesma `writeTransaction`
- `OFXCategoryHeuristic` — chute educado por `TRNTYPE` + MEMO/NAME (PIX/TED → Transferências; CREDIT → Renda; resto → Não Classificado)
- Convenção de sinal padronizada: valor sempre magnitude positiva; sinal vem do `kind` da categoria (normalizado via `abs()` no insert OFX/CSV)
- Telas: `ImportView` (wizard), `ImportHistoryView` (lista de batches com desfazer)

**Adicionado fora do escopo da fase:**
- **Tela Configurações** (`SettingsView`): tema `system`/`light`/`dark` persistido em `UserDefaults` via `@AppStorage("appColorScheme")`. Aplicado no root via `.preferredColorScheme`.

---

## Fase 4 — Integração Claude API: categorização automática

**Objetivo:** transações importadas são categorizadas automaticamente pela IA.

**Entregáveis:**
- `AnthropicClient` (HTTP wrapper com URLSession)
- Pipeline: após import, transações sem categoria vão pra fila de classificação
- Prompt engineering: enviar descrição + valor + categorias disponíveis, receber categoria + confiança
- Tela de revisão: mostrar sugestões da IA, usuário confirma ou corrige
- Aprendizado: correções do usuário viram exemplos few-shot no prompt das próximas
- Cache: mesma descrição não consulta IA duas vezes (tabela `categorization_cache`)

**Sem isto, não avança:** importar planilha → IA categoriza 80%+ corretamente → você revisa rápido.

---

## Fase 5 — Sync via PowerSync + Supabase

**Objetivo:** dados sincronizam entre Mac e iPhone via PowerSync.

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

**Sem isto, não avança:** logar no Mac, adicionar transação, abrir app no iPhone (logado mesma conta), ver transação aparecer.

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
- Widget iOS de saldo na home/lock screen
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
