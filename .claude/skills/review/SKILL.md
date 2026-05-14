---
name: review
description: >
  Faz uma revisão completa do código alterado no repositório git atual (staged + unstaged).
  Use esta skill sempre que o usuário pedir: /review, "revisa o código", "faz um code review", "o que mudei está ok?",
  "revisa minhas alterações", "me dá um review das mudanças", "analisa o diff", "tem algum problema no que mudei?",
  ou qualquer variação. Também ative quando o usuário terminar uma funcionalidade e quiser checar antes de commitar,
  ou mencionar que quer feedback sobre o código recente. A skill analisa qualidade, bugs, segurança e performance,
  e retorna uma lista priorizada de issues com sugestões de correção em código.
---

# Code Review das Mudanças Git

## O que fazer

Quando esta skill for ativada, revise todas as alterações pendentes no repositório git — staged e unstaged — e produza um relatório de issues priorizadas com sugestões de correção.

## Passo 1: Carregar contexto do projeto (se disponível)

Antes de olhar o código, verifique se existe um arquivo `CLAUDE.md` na raiz do repositório:

```bash
cat CLAUDE.md 2>/dev/null
```

Se existir, leia-o inteiro. Ele provavelmente descreve convenções do projeto, arquitetura, padrões adotados, decisões intencionais e restrições específicas. Guarde esse contexto — ele vai calibrar toda a análise:

- **Evitar falsos positivos:** se o projeto documenta que usa um padrão específico (ex: "usamos `any` intencionalmente em adapters"), não sinalize isso como problema.
- **Reforçar convenções:** se o projeto define regras (ex: "toda função async deve ter try/catch", "nomes de variáveis em camelCase"), sinalize desvios como issues.

Se não houver `CLAUDE.md`, continue normalmente com boas práticas gerais — sem avisar o usuário sobre a ausência.

## Passo 2: Coletar o diff

Execute os seguintes comandos para obter as mudanças:

```bash
# Alterações staged (adicionadas com git add)
git diff --cached

# Alterações unstaged (modificadas mas não adicionadas)
git diff

# Contexto adicional: quais arquivos mudaram
git status --short

# Se o diff for muito grande, liste os arquivos e mostre um por vez
git diff --cached --name-only
git diff --name-only
```

Se não houver nenhuma mudança (diff vazio e status limpo), informe o usuário e encerre.

Se o diff for extenso (mais de ~500 linhas), priorize os arquivos com mais mudanças e mencione que a revisão foca nos arquivos principais.

## Passo 3: Analisar o código

(Use o contexto do `CLAUDE.md` lido no Passo 1 para calibrar os itens abaixo.)

Examine o diff nas quatro dimensões abaixo. Para cada problema encontrado, anote:

- **Severidade**: 🔴 Crítico / 🟡 Médio / 🟢 Baixo
- **Categoria**: Qualidade | Bug | Segurança | Performance
- **Localização**: arquivo e, se possível, linha ou trecho
- **Problema**: o que está errado e por quê importa
- **Sugestão**: como corrigir, com snippet de código quando ajudar

### Qualidade e boas práticas

- Funções muito longas ou com muita responsabilidade (faça uma coisa só)
- Nomes de variáveis, funções ou classes que não comunicam a intenção
- Duplicação de lógica que poderia ser extraída
- Comentários desnecessários ou que explicam _o quê_ em vez do _porquê_
- Código morto (funções não usadas, imports não usados, variáveis nunca lidas)
- Tratamento de erros ausente ou genérico demais
- Over-engineering: abstrações, padrões ou camadas de indireção que adicionam complexidade sem benefício claro para o problema atual (YAGNI — "You Aren't Gonna Need It")

### Bugs e lógica

- Condições de borda não tratadas (arrays vazios, null/undefined, zero)
- Lógica invertida ou comparações incorretas
- Estado mutável compartilhado de forma perigosa
- Operações assíncronas sem tratamento de erro (promises sem catch, async sem try/catch)
- Off-by-one errors em loops ou índices
- Tipagem incorreta ou coerção implícita problemática

### Segurança

- Credenciais, tokens ou chaves hardcoded no código
- Dados de entrada do usuário usados diretamente sem sanitização (SQL injection, XSS, command injection)
- Informações sensíveis em logs ou mensagens de erro
- Endpoints sem autenticação ou autorização
- Dependências importadas de forma insegura

### Performance

- N+1 queries (consultas dentro de loops)
- Operações custosas dentro de loops que poderiam ser feitas uma vez só
- Re-renders ou recálculos desnecessários
- Falta de paginação em queries que podem retornar muitos registros
- Criação desnecessária de objetos ou alocações em hot paths

## Passo 4: Montar o relatório

O relatório é organizado **por arquivo**, não por severidade. Cada arquivo vira uma seção, e dentro dela os problemas aparecem em ordem de severidade com o emoji inline. Sem cabeçalho de arquivos revisados, sem seção de pontos positivos, sem conclusão, sem recomendações finais. Só os problemas por arquivo e a tabela de resumo no final.

Use este formato exato:

---

## 🔍 Code Review

### `caminho/do/arquivo1.ext`

🔴 [Categoria] — Título curto e direto
Explicação clara em texto do que está errado e por que importa. Mencione o impacto concreto.
**Sugestão:** Como corrigir, em texto. Sem snippet de código.

🟡 [Categoria] — Título curto
Explicação.
**Sugestão:** Como corrigir.

🟢 [Categoria] — Título curto
Explicação.
**Sugestão:** Como corrigir.

---

### `caminho/do/arquivo2.ext`

🔴 [Categoria] — Título curto
Explicação.
**Sugestão:** Como corrigir.

---

### 📋 Resumo

| Prioridade | Arquivo       | Problema        |
| ---------- | ------------- | --------------- |
| 🔴 Crítico | `arquivo.ext` | Descrição curta |
| 🟡 Médio   | `arquivo.ext` | Descrição curta |
| 🟢 Baixo   | `arquivo.ext` | Descrição curta |

---

## Passo 5: Encerrar

Após o relatório, siga estas regras:

**Se não houver nenhum problema:** diga isso claramente em uma frase. Ex: "O código está limpo — nenhum problema encontrado."

**Se houver problemas:** finalize sempre com a pergunta:

> "Quer que eu aplique as correções?"

Se o usuário aprovar, aplique as correções você mesmo diretamente nos arquivos usando as ferramentas de edição disponíveis. **Não delegue as correções a subagentes.** Edite cada arquivo afetado, uma issue de cada vez, e confirme ao usuário o que foi alterado.

---

## Dicas de comportamento

- **Agrupe por arquivo, não por severidade.** Cada arquivo é uma seção `###`. Os itens dentro de cada seção ficam ordenados do mais crítico ao menos crítico.
- **Só problemas.** Sem seção de pontos positivos, resumo executivo, recomendações finais nem conclusão.
- **Sem código.** Nem o trecho problemático, nem a sugestão corrigida. Texto puro.
- **Sem números de linha.** Arquivo é suficiente para localizar.
- **Seja específico.** "Variável com nome confuso" é fraco. "A variável `d` não comunica o que armazena" é útil.
- **Explique o impacto.** O usuário decide o que priorizar quando sabe o que pode dar errado na prática.
- **Não invente issues.** Um relatório com 3 problemas reais vale mais que um com 10 forçados.
- **Adapte ao contexto.** Migration de banco → foque em reversibilidade. Arquivo de teste → critérios de testabilidade.
- **Português.** Salvo nomes técnicos que ficam melhor no original (widget, setState, dispose, etc.).
