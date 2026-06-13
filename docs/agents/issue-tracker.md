# Issue tracker: GitHub

Issues e PRDs deste repositório ficam no GitHub Issues. Use a CLI `gh` para todas as operações.

## Convenções

- **Criar uma issue**: `gh issue create --title "..." --body "..."`. Use heredoc para corpos com múltiplas linhas.
- **Ler uma issue**: `gh issue view <number> --comments`, filtrando comentários com `jq` e incluindo os rótulos.
- **Listar issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'`, com filtros `--label` e `--state` apropriados.
- **Comentar em uma issue**: `gh issue comment <number> --body "..."`
- **Aplicar ou remover rótulos**: `gh issue edit <number> --add-label "..."` ou `gh issue edit <number> --remove-label "..."`
- **Fechar uma issue**: `gh issue close <number> --comment "..."`

Infira o repositório por `git remote -v`. A CLI `gh` faz isso automaticamente quando executada dentro do clone.

## Quando um skill disser "publish to the issue tracker"

Crie uma issue no GitHub.

## Quando um skill disser "fetch the relevant ticket"

Execute `gh issue view <number> --comments`.
