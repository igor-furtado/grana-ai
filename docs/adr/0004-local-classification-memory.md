# Memória local de classificações confirmadas

O GranaApp precisa reaproveitar classificações confirmadas pelo usuário sem mover a fonte de verdade financeira para o GranaAI. A memória local deve melhorar a classificação automática, mas não pode persistir transações completas, valores, datas, contas ou cartões.

## Decisão

- Adicionar o contrato explícito `grana-ai learn` via `stdin/stdout`.
- Manter `grana-ai` sem argumentos como comando de classificação existente.
- Persistir sinais por descrição normalizada inteira, em texto claro.
- Não persistir valor, data, conta, cartão ou payload financeiro completo.
- Usar memória antes das regras determinísticas.
- Validar todo destino contra a taxonomia recebida antes de aprender ou classificar.
- Se um destino salvo não existir na taxonomia do request, ignorar a memória e continuar para regras determinísticas e fallback.
- Sobrescrever o sinal anterior quando uma nova confirmação chega para a mesma descrição normalizada.
- Usar memória global neste Mac, com override por `GRANA_AI_MEMORY_PATH` para desenvolvimento e testes.
- Retornar `source: "memory"` apenas quando uma classificação vier da memória.

## Consequências

- A integração de classificação do GranaApp não quebra, porque o comando sem argumentos permanece igual.
- O GranaApp precisa chamar `grana-ai learn` após confirmações do usuário que devem virar sinais locais.
- A memória melhora casos recorrentes sem virar fonte de verdade financeira.
- Mudanças futuras de taxonomia não forçam migração imediata da memória, porque destinos ausentes são ignorados no uso.
