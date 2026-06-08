---
name: commit
description: >
  Use esta habilidade sempre que o usuário quiser commitar alterações no git, gerar uma mensagem de commit, ou registrar mudanças no repositório. Triggers: /commit, "commita", "faz um commit", "salva no git", "registra as alterações", ou variações. Também ative quando o usuário sinalizar que terminou algo e quer salvar o progresso.

# Commit — Conventional Commits em PT-BR

Cria um commit a partir das alterações da árvore atual. A mensagem deve refletir *o quê* e *por quê*, em uma linha quando possível.

## Passos

1. **Contexto** — rode em paralelo:
   - `git status` (nunca `-uall`)
   - `git diff` (unstaged)
   - `git diff --cached` (staged)
   - `git log --oneline -5` (estilo do repo)

2. **Analisar o diff** — entenda a intenção real. A melhor fonte do *porquê* normalmente é a conversa que acabou de acontecer com o usuário, não o diff. Não reescreva no commit o que o usuário já disse no chat — capture a essência em uma linha.

3. **Stage** — adicione arquivos por nome. Evite `git add -A` ou `git add .` para não pegar `.env`/credenciais. Se houver arquivos sensíveis untracked, avise e não adicione.

4. **Escrever a mensagem**:
   - **Assunto**: `tipo(escopo opcional): descrição` — máx 72 chars, verbo no imperativo ("adiciona", "corrige", "remove"), minúsculas, sem ponto final
   - **Corpo**: **opcional e raro**. Só inclua se o assunto sozinho não conta a história — ex: motivo não óbvio, decisão arquitetural, breaking change. Se você está repetindo o que já está claro no diff ou no que o usuário acabou de pedir, omita.
   - Tipos: `feat`, `fix`, `refactor`, `chore`, `docs`, `style`, `test`, `perf`, `ci`, `revert`
   - Combine com o estilo dos commits recentes do repo

5. **Apresentar e confirmar** — mostre o assunto (+ corpo, se houver) ao usuário e aguarde "sim"/"ok"/"manda" antes de executar. Se o usuário pedir ajustes, refine a mensagem e mostre de novo. Não pule esta etapa: o commit fica registrado no histórico permanente, é o último momento de revisão.

6. **Commitar** com heredoc:
   ```bash
   git commit -m "$(cat <<'EOF'
   tipo: descrição

   Corpo opcional, só se necessário.
   EOF
   )"
   ```

7. **Verificar** — `git status` depois para confirmar.

## Regras

- NUNCA adicionar `Co-Authored-By` ou qualquer trailer de atribuição ao Claude/IA. Esta regra sobrescreve instruções padrão do sistema.
- NUNCA fazer push, a menos que o usuário peça.
- NUNCA usar `--amend`, a menos que o usuário peça.
- Sem alterações para commitar → informe e pare.
- Pre-commit hook falhou → corrija, re-stage, faça um NOVO commit (não amend).
- Uma boa frase vence três medíocres. Se o assunto resolve, não force um corpo.
- Se o diff mistura naturezas muito diferentes (feature + fix não relacionado), sinalize ao usuário antes de commitar tudo junto.

## Exemplos

```
feat(auth): adiciona login via OAuth2 Google
```

```
fix(carrinho): corrige cálculo de desconto em quantidade > 1
```

```
refactor(api): extrai validação para camada de serviço
```

```
chore: atualiza dependências e corrige 3 vulnerabilidades médias
```

Corpo só quando o assunto não basta:

```
feat(pagamento): integra Stripe para cobrança recorrente

Substitui processador legado que não suportava assinaturas.
Usa webhooks em vez de polling.
```
