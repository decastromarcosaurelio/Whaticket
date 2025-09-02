# Plano: Sistema de Instalação Unificado Whaticket

## Contexto
- **Objetivo**: Transformar instalação de 2 repositórios em sistema unificado
- **Stack**: Ubuntu Server 24.04, sem Docker, com .env automático
- **Integrações**: Sentry + Datadog + logs detalhados
- **Abordagem**: Wrapper inteligente + modularização (Solução 2)

## Plano de Execução

### ETAPA 1: Estrutura Base do Sistema Unificado
- [x] .env.example com todas as variáveis
- [x] Script principal install-whaticket.sh
- [x] Módulo lib/logger.sh
- [x] Módulo lib/cleanup.sh

### ETAPA 2: Substituição da Interface Interativa
- [ ] Modificar lib/_inquiry.sh para suporte .env
- [ ] Criar lib/env-validator.sh

### ETAPA 3: Eliminação da Dependência Docker para Redis
- [ ] Modificar lib/_backend.sh
- [ ] Criar lib/redis-native.sh

### ETAPA 4: Sistema de Logs Avançado
- [ ] Integrar logs em todas as funções
- [ ] Criar lib/monitoring.sh

### ETAPA 5: Integração Sentry + Datadog
- [ ] Implementar lib/sentry-integration.sh
- [ ] Implementar lib/datadog-integration.sh

### ETAPA 6: Melhorias no Sistema de Git
- [ ] Eliminar dependência de clone
- [ ] Criar lib/git-manager.sh

### ETAPA 7: Validação e Testes
- [ ] Criar lib/health-check.sh
- [ ] Implementar testes de instalação

## Status Atual
- **Iniciado em**: 2025-09-01 19:03:42
- **Fase Atual**: Implementação - Etapa 1