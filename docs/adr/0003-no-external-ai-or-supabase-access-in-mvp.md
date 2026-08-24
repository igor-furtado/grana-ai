# Sem IA externa ou acesso ao Supabase no MVP

O MVP exclui provedores externos de IA e acesso direto ao Supabase pelo GranaAI porque o primeiro valor do produto é uma fronteira local de privacidade e um contrato estável de classificação, não qualidade de classificação. O GranaAI recebe a taxonomia do GranaApp, retorna apenas valores dessa taxonomia ou resultados de fallback, e deixa toda persistência financeira para o GranaApp.

## Opções consideradas

- Usar APIs públicas de IA para obter qualidade inicial de classificação.
- Permitir que o GranaAI leia ou escreva diretamente no Supabase.
- Manter o GranaAI local e limitado ao contrato no MVP.

## Consequências

O MVP pode retornar classificações fallback para todas as transações, mas precisa provar parsing, validação, responses por transação, erros estáveis e comportamento seguro em falhas.
