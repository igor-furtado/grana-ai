# Domain Docs

Como os skills de engenharia devem consumir a documentação de domínio deste repositório ao explorar o código.

## Antes de explorar

- Leia o `CONTEXT.md` na raiz do repositório.
- Leia em `docs/adr/` os ADRs relacionados à área que será alterada.

Se esses arquivos não existirem, prossiga silenciosamente. Não sinalize sua ausência nem sugira criá-los antecipadamente. O skill produtor (`/grill-with-docs`) os cria sob demanda quando termos ou decisões forem definidos.

## Estrutura

Este é um repositório single-context:

```text
/
├── CONTEXT.md
├── docs/adr/
└── GranaAi/
```

## Use o vocabulário do glossário

Quando uma saída nomear um conceito de domínio, como em um título de issue, proposta de refatoração, hipótese ou nome de teste, use o termo definido em `CONTEXT.md`. Não substitua termos por sinônimos que o glossário evite explicitamente.

Se o conceito necessário não estiver no glossário, reavalie se o termo realmente pertence ao projeto. Caso seja uma lacuna legítima, registre-a para `/grill-with-docs`.

## Sinalize conflitos com ADRs

Se uma saída contradisser um ADR existente, indique o conflito explicitamente em vez de sobrescrever a decisão silenciosamente.
