## Contexto do projeto

Antes de qualquer trabalho de produto, arquitetura ou implementação, leia `CONTEXT.md` para usar a linguagem do domínio e `gh issue view 1 --comments` para consultar o briefing inicial até que uma especificação mais completa o substitua.

### Guardrails do projeto

- GranaAI é dono da inteligência de classificação; GranaApp é dono de UI, importação, revisão manual, persistência no Supabase e commit final das transações.
- O primeiro marco prova o contrato local versionado de classificação antes de buscar qualidade de classificação.
- O MVP deve evitar provedores externos de IA, acesso ao Supabase, commit de transações e logs de payloads financeiros crus.
- Mantenha `CONTEXT.md` apenas como glossário. Registre decisões difíceis de reverter em `docs/adr/`.

## Agent skills

### Issue tracker

Issues e specs são acompanhadas no GitHub Issues de `igor-furtado/grana-ai`. Veja `docs/agents/issue-tracker.md`.

### Triage labels

A triagem usa o vocabulário padrão de cinco labels. Veja `docs/agents/triage-labels.md`.

### Domain docs

Este repo usa um layout de documentação de domínio com contexto único. Veja `docs/agents/domain.md`.
