# GranaAI

GranaAI é o classificador local usado pelo GranaApp para sugerir categorias e subcategorias para transações financeiras sem enviar dados transacionais a provedores externos de IA.

Neste estágio, a integração com o GranaApp acontece por processo local: o GranaApp executa o binário `grana-ai`, envia um JSON no `stdin` e lê a resposta JSON no `stdout`.

## Build

Para desenvolvimento:

```bash
swift build -c debug
```

Binário gerado:

```text
.build/debug/grana-ai
```

Para uma build mais próxima de uso real:

```bash
swift build -c release
```

Binário gerado:

```text
.build/release/grana-ai
```

## Testes

```bash
swift test
```

Os testes cobrem o núcleo `GranaAICore` e o executável real `grana-ai`.

## Integração Com o GranaApp

O GranaApp não importa este pacote Swift diretamente neste marco. Ele deve chamar o executável local via `Process`.

Durante o desenvolvimento, o caminho pode apontar para:

```text
/Users/furtadino/Developer/projects/pessoais/grana_ai/.build/debug/grana-ai
```

Em empacotamento futuro, o binário deve ser incluído no bundle do GranaApp e resolvido a partir de `Bundle.main`.

O client do GranaApp deve:

1. executar o binário `grana-ai`;
2. escrever um `ClassificationRequest` JSON no `stdin`;
3. fechar o `stdin`;
4. ler um `ClassificationResponse` JSON no `stdout`;
5. aplicar timeout e cancelamento;
6. tratar erros estruturados sem depender de texto livre.

Para registrar classificações confirmadas pelo usuário, o GranaApp deve executar:

```bash
grana-ai learn
```

Esse comando também lê JSON pelo `stdin`, mas não escreve resposta no `stdout` quando conclui com sucesso. O comando sem argumentos continua sendo o caminho de classificação.

A memória local padrão fica em:

```text
~/Library/Application Support/GranaAI/memory.v1.json
```

Durante desenvolvimento e testes, o caminho pode ser sobrescrito com:

```bash
GRANA_AI_MEMORY_PATH=/tmp/grana-ai-memory.v1.json .build/debug/grana-ai
```

## Contrato Atual

Versão atual:

```text
classification.v1
```

Request mínimo:

```json
{
  "version": "classification.v1",
  "transactions": [
    {
      "id": "tx-padaria",
      "description": "PADARIA CENTRAL",
      "amountInMinorUnits": -1890,
      "currencyCode": "BRL"
    }
  ],
  "taxonomy": {
    "categories": [
      {
        "id": "alimentacao",
        "name": "Alimentação",
        "subcategories": [
          {
            "id": "padarias",
            "name": "Padarias"
          }
        ]
      }
    ]
  },
  "context": {
    "locale": "pt-BR"
  }
}
```

Response classificada:

```json
{
  "version": "classification.v1",
  "results": [
    {
      "transactionId": "tx-padaria",
      "outcome": "classified",
      "categoryId": "alimentacao",
      "subcategoryId": "padarias"
    }
  ]
}
```

Quando a classificação vier da memória local, o resultado inclui `source`:

```json
{
  "version": "classification.v1",
  "results": [
    {
      "transactionId": "tx-steam",
      "outcome": "classified",
      "categoryId": "streaming-e-apps",
      "subcategoryId": "jogos",
      "source": "memory"
    }
  ]
}
```

Response fallback:

```json
{
  "version": "classification.v1",
  "results": [
    {
      "transactionId": "tx-unknown",
      "outcome": "fallback",
      "fallbackReason": "unknown"
    }
  ]
}
```

Erro estruturado:

```json
{
  "code": "invalid_json",
  "message": "Invalid JSON payload."
}
```

Request de aprendizado:

```json
{
  "version": "classification.v1",
  "taxonomy": {
    "categories": [
      {
        "id": "streaming-e-apps",
        "name": "Streaming e apps",
        "subcategories": [
          {
            "id": "jogos",
            "name": "Jogos"
          }
        ]
      }
    ]
  },
  "confirmedClassifications": [
    {
      "description": "PAG Steam Sao Paulo BRA",
      "categoryId": "streaming-e-apps",
      "subcategoryId": "jogos"
    }
  ]
}
```

## Guardrails

- A taxonomia sempre vem do GranaApp.
- O GranaAI só pode sugerir categoria/subcategoria presentes na taxonomia recebida.
- O GranaAI não acessa Supabase.
- O GranaAI não faz commit de transações.
- O GranaAI não chama provedores externos de IA.
- Logs não devem registrar descrições completas, valores, credenciais ou payloads financeiros crus.
- A memória local guarda apenas descrições normalizadas e destinos confirmados pelo usuário.
- A memória nunca recria categoria/subcategoria ausente na taxonomia recebida.
