# Projeto local de classificação separado

GranaAI é um projeto separado do GranaApp porque a inteligência de classificação precisa evoluir atrás de uma fronteira própria, enquanto o GranaApp permanece responsável pelos fluxos de produto e pela persistência financeira. Isso mantém regras, memória, classificadores locais e futuro trabalho com LLM local fora do app principal, preservando o Supabase como fonte de verdade financeira.

## Opções consideradas

- Manter a inteligência de classificação dentro do GranaApp.
- Mover a inteligência de classificação para um backend ou Edge Function.
- Criar o GranaAI como projeto local separado para macOS.

## Consequências

O GranaApp depende de um contrato de classificação em vez de depender de estratégias, modelos, prompts ou runtimes específicos.
