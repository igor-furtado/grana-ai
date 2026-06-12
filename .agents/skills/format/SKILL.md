---
name: format
description: >
  Roda SwiftFormat sobre as alterações pendentes do repositório para normalizar layout (indentação,
  imports, quebras de linha, `self.`, vírgulas etc.) conforme as regras de [.swiftformat]. Use esta
  skill sempre que o usuário pedir: /format, "formata o código", "passa o swiftformat",
  "checa formatação", "normaliza o estilo", "deixa o código bonito", ou qualquer variação.
  Skill independente, pode ser rodada a qualquer momento — não precisa estar antes ou depois de
  nenhuma outra skill. SwiftLint não faz parte desta skill: ele roda como build phase do Xcode.
---

# Format — SwiftFormat

Roda SwiftFormat sobre o working tree, conserta layout automaticamente e reporta o resultado.

## Por que existe

Padronizar layout (indentação, ordem de imports, quebras de linha em listas, `self.` em init, vírgulas, espaços) é repetitivo e ruidoso. SwiftFormat resolve isso em segundos, lendo as regras de [.swiftformat](.swiftformat). Qualidade de código e invariantes do projeto (`Double` pra dinheiro, `ObservableObject`, etc.) ficam por conta do SwiftLint, que roda como build phase do Xcode — não nesta skill.

## Pré-requisito

```bash
command -v swiftformat >/dev/null 2>&1 || echo "swiftformat ausente — instalar: brew install swiftformat"
```

Se faltar, interrompa o fluxo e oriente o usuário a instalar.

## Fluxo de execução

### 1. Confirmar o escopo

```bash
git status --short
```

Se não houver alterações, informe o usuário — não há sentido em rodar formatação sobre um repo limpo (rodar mexeria potencialmente em arquivos que estão fora de padrão por outras razões, gerando ruído no diff).

### 2. Preview — o que mudaria

```bash
swiftformat --lint .
```

Lista os arquivos que seriam modificados sem escrever. Se a saída for vazia, o código já está formatado — informe e encerre.

### 3. Aplicar

Pergunte se o usuário quer aplicar. Se sim:

```bash
swiftformat .
```

Mostre `git diff --stat` depois pra dimensionar o que mudou.

### 4. Sinalizar quando o diff "estoura"

Se o SwiftFormat tocou em muitos arquivos além dos que o usuário estava editando (porque já estavam fora de padrão antes), avise: pode fazer sentido commitar a formatação separado da feature em curso (`style: aplica swiftformat`) pra manter o diff da feature limpo.

### 5. Relatório final

```
🧹 SwiftFormat

<N arquivos formatados | nada a fazer>

<lista resumida dos arquivos tocados, se houver>
```

## Decisões intencionais

- **Não auto-stagear**: a skill nunca chama `git add`. Você decide o que entra em qual commit.
- **Não toca SwiftLint**: SwiftLint roda como build phase do Xcode, então violações aparecem no build inline — sem duplicação de execução nesta skill.
- **Roda no repo inteiro**: SwiftFormat opera no diretório atual via `.swiftformat` — não tenta limitar a "só arquivos do diff" porque isso pode deixar inconsistências entre arquivos relacionados.
