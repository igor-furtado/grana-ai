# GranaAI

GranaAI é o projeto local de inteligência de classificação para macOS usado pelo GranaApp. Ele existe para classificar transações financeiras sem enviar dados transacionais a provedores externos de IA, mantendo o Supabase como fonte de verdade financeira.

## Linguagem

**GranaAI**:
Projeto local separado para macOS que é dono da inteligência de classificação usada pelo GranaApp.
_Evite_: módulo de IA do GranaApp, backend remoto de IA, Edge Function de categorização

**GranaApp**:
Aplicativo financeiro principal, dono da interface, fluxo de importação, revisão manual, persistência no Supabase e commit final das transações.
_Evite_: cliente do GranaAI como nome de produto, dono da classificação

**Inteligência de Classificação**:
Capacidade do produto que propõe categorias e subcategorias válidas para transações financeiras.
_Evite_: IA remota, backend de categorização, categorização no Supabase

**Contrato de Classificação**:
Fronteira versionada entre GranaApp e GranaAI para requests de classificação, responses, erros de validação e resultados por transação.
_Evite_: formato de prompt, payload de API, schema interno de modelo

**Request de Classificação**:
Pedido do GranaApp para que o GranaAI classifique uma ou mais transações contra a taxonomia atual.
_Evite_: lote de importação, sincronização com Supabase, dados de treino

**Response de Classificação**:
Resultado por transação que o GranaAI devolve ao GranaApp, incluindo sugestões bem-sucedidas e resultados de fallback.
_Evite_: transações commitadas, classificações persistidas

**Transação**:
Candidata a transação financeira enviada pelo GranaApp para classificação antes de o GranaApp fazer commit na fonte de verdade financeira.
_Evite_: categoria, lançamento contábil, linha do Supabase

**Taxonomia**:
Conjunto de categorias e subcategorias fornecido pelo GranaApp em um request de classificação. O GranaAI só sugere valores presentes nessa taxonomia recebida.
_Evite_: taxonomia do GranaAI, árvore local de categorias, categorias geradas

**Classificação Fallback**:
Response válido quando o GranaAI não consegue classificar uma transação com confiança ou alinhamento válido à taxonomia. O GranaApp mapeia isso para Não Classificado ou revisão manual.
_Evite_: categoria inventada, request falho, descarte silencioso

**Revisão Manual**:
Fluxo sob responsabilidade do GranaApp em que o usuário resolve transações que o GranaAI não consegue classificar automaticamente.
_Evite_: UI de correção do GranaAI, etapa de treinamento do modelo

**Memória Global**:
Capacidade futura do GranaAI que pode persistir sinais locais de classificação entre requests. Ela não é a fonte de verdade financeira.
_Evite_: réplica do Supabase, store de transações, livro financeiro do usuário

**Regra Determinística**:
Estratégia local explícita que classifica uma transação por padrões previsíveis na descrição e pela taxonomia recebida. Ela só pode sugerir categoria/subcategoria existentes na taxonomia do request.
_Evite_: heurística remota, prompt, modelo treinado

**Fonte de Verdade Financeira**:
O Supabase, sob responsabilidade do GranaApp, continua sendo o store autoritativo para dados financeiros e estado commitado das transações.
_Evite_: banco de dados do GranaAI, memória local, cache do classificador

**Provedor Externo de IA**:
Serviço público ou de terceiro que recebe dados para inferência. A fronteira atual do produto GranaAI exclui esses provedores.
_Evite_: classificador local, LLM local, inferência on-device
