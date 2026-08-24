# Issue tracker: GitHub

Issues e specs deste repo vivem no GitHub Issues. Use o CLI `gh` para todas as operações.

## Convenções

- **Criar issue**: `gh issue create --title "..." --body "..."`. Use heredoc para bodies multilinha.
- **Ler issue**: `gh issue view <number> --comments`, filtrando comentários com `jq` e buscando labels também.
- **Listar issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` com filtros adequados de `--label` e `--state`.
- **Comentar em issue**: `gh issue comment <number> --body "..."`
- **Aplicar / remover labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Fechar**: `gh issue close <number> --comment "..."`

Infira o repo a partir de `git remote -v` - o `gh` faz isso automaticamente quando executado dentro de um clone.

## Pull requests como superfície de triagem

**PRs como superfície de request: no.** _(Altere para `yes` se este repo tratar PRs externos como requests de feature; `/triage` lê esta flag.)_

Quando definido como `yes`, PRs passam pelas mesmas labels e estados das issues, usando equivalentes de `gh pr`:

- **Ler PR**: `gh pr view <number> --comments` e `gh pr diff <number>` para o diff.
- **Listar PRs externos para triagem**: `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments` e então manter apenas `authorAssociation` de `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR` ou `NONE` (remova `OWNER`/`MEMBER`/`COLLABORATOR`).
- **Comentar / rotular / fechar**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

GitHub compartilha a mesma numeração entre issues e PRs, então um `#42` pode ser qualquer um dos dois - resolva com `gh pr view 42` e, se falhar, use `gh issue view 42`.

## Quando uma skill disser "publish to the issue tracker"

Crie uma issue no GitHub.

## Quando uma skill disser "fetch the relevant ticket"

Execute `gh issue view <number> --comments`.

## Operações de wayfinding

Usadas por `/wayfinder`. O **mapa** é uma issue única com issues **filhas** como tickets.

- **Mapa**: uma issue única com label `wayfinder:map`, contendo Notes / Decisions-so-far / Fog no body. `gh issue create --label wayfinder:map`.
- **Ticket filho**: uma issue ligada ao mapa como sub-issue do GitHub (`gh api` no endpoint de sub-issues). Onde sub-issues não estiverem habilitadas, adicione o filho a uma task list no body do mapa e coloque `Part of #<map>` no topo do body do filho. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Uma vez assumido, o ticket é atribuído ao dev condutor.
- **Bloqueio**: dependências nativas de issue do GitHub - a representação canônica e visível na UI. Adicione uma aresta com `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, em que `<blocker-db-id>` é o **database id** numérico do bloqueador (`gh api repos/<owner>/<repo>/issues/<n> --jq .id`, não o `#number` nem o `node_id`). GitHub informa `issue_dependencies_summary.blocked_by` (apenas bloqueadores abertos - o gate vivo). Onde dependências não estiverem disponíveis, use uma linha `Blocked by: #<n>, #<n>` no topo do body do filho. Um ticket fica desbloqueado quando todos os bloqueadores estão fechados.
- **Consulta de fronteira**: liste os filhos abertos do mapa (`gh issue list --state open`, escopado às sub-issues / task list do mapa), remova qualquer ticket com bloqueador aberto (`issue_dependencies_summary.blocked_by > 0`, ou uma issue aberta na linha `Blocked by`) ou assignee; o primeiro na ordem do mapa vence.
- **Assumir**: `gh issue edit <n> --add-assignee @me` - a primeira escrita da sessão.
- **Resolver**: `gh issue comment <n> --body "<answer>"`, depois `gh issue close <n>`, depois anexe um ponteiro de contexto (gist + link) às Decisions-so-far do mapa.
