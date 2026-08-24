# Começar com contrato de processo via stdin/stdout

O primeiro marco do GranaAI usa um processo local com JSON via stdin/stdout para provar o contrato de classificação antes de assumir XPC ou formato de serviço em background. Isso é suficiente para testar integração entre dois processos macOS enquanto mantém o núcleo Swift reutilizável de classificação independente do transporte.

## Opções consideradas

- Começar diretamente com XPC Service.
- Rodar o GranaAI como LaunchAgent.
- Começar com contrato de processo local via stdin/stdout.

## Consequências

O executável inicial pode continuar fino, o GranaApp pode aplicar timeout e cancelamento, e o transporte pode evoluir para XPC depois sem mudar a linguagem central de classificação.
