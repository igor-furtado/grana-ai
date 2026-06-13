# Recálculo cronológico de faturas

Correções retroativas reprocessam, em ordem cronológica e numa única transação de banco, as faturas, os saldos credores e os pagamentos do cartão afetado. Saldos credores são consumidos antes dos pagamentos; cada pagamento só cobre dívidas já existentes em sua data e a alteração é rejeitada se deixar parte da transferência sem aplicação, preservando um resultado determinístico sem bloquear correções históricas.
