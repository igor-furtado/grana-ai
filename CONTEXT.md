# Finanças Pessoais

Este contexto organiza a vida financeira de uma única pessoa a partir de contas, movimentações, categorias e faturas. O produto apoia análise e organização; não movimenta dinheiro nem substitui bancos ou corretoras.

## Estrutura financeira

**Instituição financeira**:
Organização na qual uma ou mais contas do usuário são mantidas, como banco ou corretora.
_Evite_: Banco, quando o conceito também puder representar uma corretora

**Conta**:
Local financeiro no qual existe dinheiro ou dívida do usuário. Toda transação pertence a exatamente uma conta.
_Evite_: Banco, instituição, carteira

**Conta corrente**:
Conta que representa dinheiro disponível em uma instituição financeira.
_Evite_: Conta bancária, quando for necessário distingui-la de outros tipos de conta

**Cartão de crédito**:
Conta que representa compras a crédito e a dívida associada a elas. Suas compras são organizadas em faturas.
_Evite_: Cartão, conta-cartão, conta corrente

**Saldo inicial**:
Valor da conta no ponto anterior ao primeiro histórico acompanhado pelo produto.
_Evite_: Saldo atual, patrimônio

## Movimentações

**Transação**:
Movimento financeiro ocorrido em uma conta, classificado como receita, despesa ou transferência. Seu valor é sempre expresso como magnitude positiva; a classificação determina seu efeito financeiro.
_Evite_: Lançamento, movimentação, operação

**Receita**:
Transação que representa ganho ou entrada de dinheiro reconhecida na análise financeira.
_Evite_: Crédito, depósito, recebimento

**Despesa**:
Transação que representa consumo, compra ou saída de dinheiro reconhecida na análise financeira.
_Evite_: Débito, gasto

**Transferência**:
Transação que representa movimentação de valor sem compor receitas ou despesas. Quando ocorre entre contas próprias acompanhadas, distingue uma conta de origem e uma conta de destino.
_Evite_: Receita, despesa

**Conta de destino**:
Conta própria que recebe o valor de uma transferência.
_Evite_: Favorecido, contraparte

## Classificação

**Categoria**:
Classificação principal de uma transação, pertencente a um único tipo: receita, despesa ou transferência.
_Evite_: Tag, grupo

**Subcategoria**:
Classificação específica subordinada a uma categoria e do mesmo tipo dela.
_Evite_: Categoria filha, tag

**Não Classificado**:
Categoria de despesa usada quando a classificação definitiva ainda requer revisão.
_Evite_: Outros, desconhecido

## Cartão e faturas

**Fatura**:
Ciclo de compras de um cartão de crédito, identificado por suas datas de fechamento e vencimento. Reúne as transações de cartão que pertencem ao mesmo ciclo.
_Evite_: Extrato, boleto, invoice

**Data de fechamento**:
Data que encerra o período de compras de uma fatura.
_Evite_: Data de corte

**Data de vencimento**:
Data prevista para quitação de uma fatura.
_Evite_: Data de pagamento

**Pagamento de fatura**:
Distribuição integral de uma transferência entre uma ou mais faturas, com cada aplicação limitada ao saldo restante da respectiva fatura. Uma fatura pode receber vários pagamentos.
_Evite_: Compra, despesa, baixa

**Estorno de cartão**:
Reversão total ou parcial de uma compra específica, lançada no ciclo da data do estorno. Uma compra pode receber vários estornos, cuja soma não pode superar seu valor original.
_Evite_: Receita, pagamento, compra negativa

**Fatura em formação**:
Fatura cujo ciclo de compras ainda não alcançou a data de fechamento. Pode receber novas compras e estornos mesmo quando seu saldo restante estiver integralmente coberto.
_Evite_: Fatura aberta, fatura futura

**Fatura fechada**:
Fatura cujo ciclo de compras alcançou a data de fechamento e não recebe novos lançamentos ordinários.
_Evite_: Fatura paga, fatura quitada

**Fatura paga**:
Fatura fechada cujo total foi integralmente coberto por pagamentos.
_Evite_: Fatura quitada, quando houver saldo credor aplicado

**Fatura quitada**:
Fatura fechada cujo total foi integralmente coberto por pagamentos, saldos credores ou uma combinação de ambos.
_Evite_: Fatura paga, quando não houver pagamento

**Data de quitação**:
Momento em que pagamentos e saldos credores passaram a cobrir integralmente o total de uma fatura.
_Evite_: Data de pagamento, quando a quitação não depender exclusivamente de pagamento

**Total da fatura**:
Valor líquido a quitar em um ciclo, resultante das compras menos os estornos e os saldos credores recebidos. Os componentes permanecem distinguíveis para auditoria.
_Evite_: Soma das compras, saldo restante

**Saldo credor da fatura**:
Crédito resultante quando os estornos de um ciclo superam suas compras. Não exige pagamento e o excedente reduz a fatura seguinte do mesmo cartão de crédito.
_Evite_: Pagamento antecipado, receita, desconto

**Crédito pendente do cartão**:
Parcela de saldo credor ainda não aplicada porque não existe uma fatura posterior materializada. É consumida quando a próxima fatura do cartão surge.
_Evite_: Fatura futura, pagamento antecipado, saldo da conta

## Importação e classificação assistida

**Extrato**:
Registro emitido por uma instituição financeira com as transações de uma conta em determinado período.
_Evite_: Fatura, histórico do produto

**Importação**:
Entrada de transações provenientes de um arquivo financeiro para revisão e incorporação ao histórico.
_Evite_: Sincronização, integração bancária

**Lote de importação**:
Conjunto de transações incorporadas a partir de um mesmo extrato de conta, tratado como uma unidade reversível.
_Evite_: Arquivo, upload

**Categorização assistida**:
Sugestão de categorias para transações importadas antes de sua incorporação definitiva, sujeita à revisão do usuário.
_Evite_: Categorização automática, quando houver revisão humana
