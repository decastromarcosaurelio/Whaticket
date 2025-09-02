# Plano: Correção de Conflito de Variáveis no Logger

## Contexto
- **Problema**: Erro "RED: readonly variable" na linha 8 do logger.sh
- **Causa**: Conflito de variáveis de cor entre módulos
- **Solução**: Namespace único com prefixo LOG_ para todas as variáveis

## Plano de Execução

### ETAPA 1: Identificar Conflitos
- [x] Analisar lib/logger.sh linha 8
- [x] Mapear todas as variáveis de cor em conflito
- [x] Verificar outras readonly variables
- [x] **Conflito encontrado**: variables/_fonts.sh também define RED, GREEN, YELLOW

### ETAPA 2: Implementar Namespace
- [x] Renomear variáveis com prefixo LOG_
- [x] Manter funcionalidade idêntica
- [x] **Aplicado**: RED→LOG_RED, GREEN→LOG_GREEN, etc.

### ETAPA 3: Atualizar Referências
- [x] Substituir todas as referências
- [x] Garantir consistência no código  
- [x] **Corrigido**: 9 referências atualizadas no logger.sh

### ETAPA 4: Teste de Validação
- [x] Executar script corrigido
- [x] Verificar funcionamento dos logs
- [x] Confirmar resolução do erro

## Status Atual
- **Iniciado em**: Problema reportado pelo usuário
- **Fase Atual**: Implementação - Correção aplicada