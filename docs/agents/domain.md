# Documentação de Domínio

Como as skills de engenharia devem consumir a documentação de domínio deste repo ao explorar o codebase.

## Antes de explorar, leia

- **`CONTEXT.md`** na raiz do repo, ou
- **`CONTEXT-MAP.md`** na raiz do repo, se existir - ele aponta para um `CONTEXT.md` por contexto. Leia cada contexto relevante para o assunto.
- **`docs/adr/`** - leia ADRs que toquem a área em que você vai trabalhar. Em repos multi-contexto, verifique também `src/<context>/docs/adr/` para decisões específicas daquele contexto.

Se algum desses arquivos não existir, **prossiga em silêncio**. Não destaque a ausência e não sugira criar esses arquivos antecipadamente. A skill `/domain-modeling` (usada por `/grill-with-docs` e `/improve-codebase-architecture`) cria os arquivos sob demanda quando termos ou decisões realmente se cristalizam.

## Estrutura de arquivos

Repo de contexto único (a maioria dos repos):

```text
/
|-- CONTEXT.md
|-- docs/adr/
|   |-- 0001-event-sourced-orders.md
|   `-- 0002-postgres-for-write-model.md
`-- src/
```

Repo multi-contexto (presença de `CONTEXT-MAP.md` na raiz):

```text
/
|-- CONTEXT-MAP.md
|-- docs/adr/                          <- decisões sistêmicas
`-- src/
    |-- ordering/
    |   |-- CONTEXT.md
    |   `-- docs/adr/                  <- decisões específicas do contexto
    `-- billing/
        |-- CONTEXT.md
        `-- docs/adr/
```

## Use o vocabulário do glossário

Quando sua saída nomear um conceito de domínio (em título de issue, proposta de refatoração, hipótese, nome de teste), use o termo definido em `CONTEXT.md`. Evite sinônimos que o glossário marca explicitamente como termos a evitar.

Se o conceito necessário ainda não estiver no glossário, isso é um sinal: talvez você esteja inventando uma linguagem que o projeto não usa, ou talvez exista uma lacuna real. Em caso de lacuna, registre para `/domain-modeling`.

## Sinalize conflitos com ADRs

Se sua saída contradisser uma ADR existente, sinalize isso explicitamente em vez de sobrescrever a decisão em silêncio:

> _Contradiz ADR-0007 (event-sourced orders) - mas vale reabrir porque..._
