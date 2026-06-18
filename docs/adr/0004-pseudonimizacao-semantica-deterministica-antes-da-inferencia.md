# Pseudonimização semântica determinística antes da inferência

Antes de qualquer lookup de cache, seleção de correções ou chamada ao provider, o backend transforma descrições e demais campos textuais enviados pelo app por meio de pseudonimização semântica determinística baseada em regras locais explícitas. A meta é reduzir exposição de dados identificáveis sem destruir pistas úteis de classificação, mantendo a mesma representação pseudonimizada como base para cache, few-shots dinâmicos, prompt e validação do resultado.
