# Categorização assistida via Codex CLI

Durante o MVP, a categorização assistida usa `codex exec` autenticado pela
assinatura local do usuário, em vez de Claude CLI ou API paga por uso. O app é
de uso pessoal, executado em um Mac com Codex instalado, e o volume esperado é
de 100 a 200 transações por mês.

Para reduzir tokens, as chamadas são sequenciais, sem exemplos few-shot, com
até 100 transações e contexto financeiro mínimo. Falhas dividem o lote em
metades até 25 itens; resultados válidos são preservados e apenas itens
ausentes ou inválidos são reenviados. Se o Codex permanecer indisponível, a
importação continua em Não Classificado.

O cache considera descrição normalizada, tipo da conta, sinal, modelo e versão
da taxonomia. Valor, data e apelido da conta não são enviados. O prompt recebe
descrição, sinal quando confiável, tipo da conta, categoria da fonte quando
existir e nomes das instituições próprias para reconhecer transferências.

Regras locais prevalecem sobre a confiança declarada pelo modelo. Sugestões sem
sinal confiável, transferências, subcategorias inválidas ou confiança inválida
sempre exigem revisão. Categorias incompatíveis com o sinal viram Não
Classificado.

Essa decisão evita cobrança adicional e preserva o fluxo local-first, ao custo
de acoplar temporariamente o MVP à instalação, autenticação, limites e formato
de execução do Codex CLI. Uma API dedicada permanece a alternativa indicada
caso o app seja distribuído.
