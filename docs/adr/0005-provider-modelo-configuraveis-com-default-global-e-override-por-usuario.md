# Provider e modelo configuráveis com default global e override por usuário

O backend mantém um par `provider + modelo` padrão do produto e resolve opcionalmente um override por usuário autenticado, com uma única escolha ativa por vez e sem fallback silencioso entre provedores. No MVP, a integração inicial prevista é OpenAI com `gpt-5.4-mini`, a lista de pares permitidos fica só no backend, preferências do usuário, cache e correções são isolados por usuário no Supabase Postgres, e o app ainda não expõe UI para alterar essa configuração.
