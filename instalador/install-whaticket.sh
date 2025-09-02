#!/bin/bash
#
# Whaticket - Sistema de Instalação Unificado
# Transforma instalação de múltiplos repositórios em sistema único
# Autor: Laowang (reformed from scattered hell to organized paradise)
# Versão: 2.0.0
#

set -euo pipefail # Exit on error, undefined vars, pipe failures

# Reset terminal colors
tput init

# Definir diretório do projeto
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  PROJECT_ROOT="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$PROJECT_ROOT/$SOURCE"
done
PROJECT_ROOT="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
export PROJECT_ROOT

# Carregar sistema de logs primeiro
source "${PROJECT_ROOT}/lib/logger.sh"

# Inicializar logging
log_init "whaticket-installer"

log_info "==================================================="
log_info "      WHATICKET - INSTALADOR UNIFICADO v2.0"
log_info "==================================================="
log_info "Projeto: $PROJECT_ROOT"

# Verificar se arquivo .env existe
if [[ ! -f "${PROJECT_ROOT}/.env" ]]; then
    log_error "Arquivo .env não encontrado!"
    log_info "Copie o arquivo .env.example para .env e configure:"
    log_info "cp ${PROJECT_ROOT}/.env.example ${PROJECT_ROOT}/.env"
    log_info "Depois edite o arquivo .env com suas configurações"
    exit 1
fi

# Carregar configurações do .env
log_info "Carregando configurações do arquivo .env..."
set -a
source "${PROJECT_ROOT}/.env"
set +a

# Carregar módulos do sistema
log_info "Carregando módulos do sistema..."

# Módulos novos
source "${PROJECT_ROOT}/lib/cleanup.sh"

# Módulos existentes (mantendo compatibilidade)
source "${PROJECT_ROOT}/variables/manifest.sh"
source "${PROJECT_ROOT}/utils/manifest.sh"
source "${PROJECT_ROOT}/lib/manifest.sh"

#######################################
# Valida configurações do .env
# Arguments:
#   None
#######################################
validate_env_config() {
    log_info "Validando configurações..."
    
    local required_vars=(
        "DEPLOY_PASSWORD"
        "ADMIN_EMAIL"
        "INSTANCE_NAME"
        "FRONTEND_URL"
        "BACKEND_URL"
        "FRONTEND_PORT"
        "BACKEND_PORT"
        "REDIS_PORT"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Variáveis obrigatórias não configuradas:"
        for var in "${missing_vars[@]}"; do
            log_error "  - $var"
        done
        log_info "Configure essas variáveis no arquivo .env"
        return 1
    fi
    
    # Validar formato de domínios
    if [[ ! "$FRONTEND_URL" =~ ^https?:// ]]; then
        log_error "FRONTEND_URL deve começar com http:// ou https://"
        return 1
    fi
    
    if [[ ! "$BACKEND_URL" =~ ^https?:// ]]; then
        log_error "BACKEND_URL deve começar com http:// ou https://"
        return 1
    fi
    
    # Validar formato do email
    if [[ ! "$ADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        log_error "ADMIN_EMAIL deve ter formato válido de email"
        return 1
    fi
    
    # Validar nome da instância
    if [[ ! "$INSTANCE_NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
        log_error "INSTANCE_NAME deve conter apenas letras minúsculas, números e hífens"
        return 1
    fi
    
    # Verificar se portas são números
    if ! [[ "$FRONTEND_PORT" =~ ^[0-9]+$ ]] || [[ "$FRONTEND_PORT" -lt 1000 ]] || [[ "$FRONTEND_PORT" -gt 65535 ]]; then
        log_error "FRONTEND_PORT deve ser um número entre 1000 e 65535"
        return 1
    fi
    
    if ! [[ "$BACKEND_PORT" =~ ^[0-9]+$ ]] || [[ "$BACKEND_PORT" -lt 1000 ]] || [[ "$BACKEND_PORT" -gt 65535 ]]; then
        log_error "BACKEND_PORT deve ser um número entre 1000 e 65535"
        return 1
    fi
    
    if ! [[ "$REDIS_PORT" =~ ^[0-9]+$ ]] || [[ "$REDIS_PORT" -lt 1000 ]] || [[ "$REDIS_PORT" -gt 65535 ]]; then
        log_error "REDIS_PORT deve ser um número entre 1000 e 65535"
        return 1
    fi
    
    log_info "Configurações validadas com sucesso!"
    return 0
}

#######################################
# Gera secrets se não estiverem definidos
# Arguments:
#   None
#######################################
generate_missing_secrets() {
    local env_file="${PROJECT_ROOT}/.env"
    local updated=false
    
    # Gerar JWT_SECRET se vazio
    if [[ -z "${JWT_SECRET:-}" ]]; then
        local jwt_secret
        jwt_secret=$(openssl rand -hex 32)
        sed -i "s/^JWT_SECRET=.*/JWT_SECRET=$jwt_secret/" "$env_file"
        export JWT_SECRET="$jwt_secret"
        log_info "JWT_SECRET gerado automaticamente"
        updated=true
    fi
    
    # Gerar JWT_REFRESH_SECRET se vazio
    if [[ -z "${JWT_REFRESH_SECRET:-}" ]]; then
        local jwt_refresh_secret
        jwt_refresh_secret=$(openssl rand -hex 32)
        sed -i "s/^JWT_REFRESH_SECRET=.*/JWT_REFRESH_SECRET=$jwt_refresh_secret/" "$env_file"
        export JWT_REFRESH_SECRET="$jwt_refresh_secret"
        log_info "JWT_REFRESH_SECRET gerado automaticamente"
        updated=true
    fi
    
    if [[ "$updated" == "true" ]]; then
        log_info "Secrets atualizados no arquivo .env"
    fi
}

#######################################
# Verifica se sistema está pronto para instalação
# Arguments:
#   None
#######################################
check_system_requirements() {
    log_info "Verificando requisitos do sistema..."
    
    # Verificar se é Ubuntu
    if [[ ! -f "/etc/lsb-release" ]] || ! grep -q "Ubuntu" /etc/lsb-release; then
        log_warn "Sistema não é Ubuntu - alguns comandos podem falhar"
    fi
    
    # Verificar privilégios
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        log_error "Este script precisa de privilégios root ou sudo sem senha"
        return 1
    fi
    
    # Verificar conexão com internet
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_error "Sem conexão com internet - necessária para instalação"
        return 1
    fi
    
    # Verificar espaço em disco
    local available_space
    available_space=$(df . | tail -1 | awk '{print $4}')
    if [[ $available_space -lt 2000000 ]]; then # Menos de 2GB
        log_warn "Pouco espaço em disco: ${available_space}KB - mínimo recomendado: 2GB"
    fi
    
    # Verificar se portas estão livres
    local ports=("$FRONTEND_PORT" "$BACKEND_PORT" "$REDIS_PORT")
    for port in "${ports[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            log_error "Porta $port já está em uso"
            return 1
        fi
    done
    
    log_info "Requisitos do sistema verificados!"
    return 0
}

#######################################
# Preparar sistema para instalação
# Arguments:
#   None
#######################################
prepare_system() {
    log_checkpoint "PREPARAÇÃO DO SISTEMA"
    
    # Executar limpeza se solicitada
    if [[ "${CLEAN_INSTALL:-false}" == "true" ]]; then
        log_warn "Limpeza completa solicitada - removendo configurações antigas"
        cleanup_system "$INSTANCE_NAME" "${BACKUP_EXISTING_CONFIG:-true}"
    fi
    
    # Atualizar sistema se não for pulado
    if [[ "${SKIP_SYSTEM_DEPS:-false}" == "false" ]]; then
        log_operation "Atualização do sistema" "system_update"
    else
        log_info "Atualização do sistema pulada (SKIP_SYSTEM_DEPS=true)"
    fi
    
    # Mapear variáveis do .env para variáveis esperadas pelos scripts antigos
    export deploy_password="$DEPLOY_PASSWORD"
    export mysql_root_password="$DEPLOY_PASSWORD"  
    export db_pass="$DEPLOY_PASSWORD"
    export deploy_email="$ADMIN_EMAIL"
    export instancia_add="$INSTANCE_NAME"
    export max_whats="$MAX_WHATSAPP_CONNECTIONS"
    export max_user="$MAX_USERS"
    export frontend_url="$FRONTEND_URL"
    export backend_url="$BACKEND_URL"
    export frontend_port="$FRONTEND_PORT"
    export backend_port="$BACKEND_PORT"
    export redis_port="$REDIS_PORT"
    export jwt_secret="$JWT_SECRET"
    export jwt_refresh_secret="$JWT_REFRESH_SECRET"
    
    log_info "Sistema preparado para instalação"
}

#######################################
# Instalar dependências do sistema
# Arguments:
#   None
#######################################
install_system_dependencies() {
    log_checkpoint "INSTALAÇÃO DE DEPENDÊNCIAS"
    
    if [[ "${SKIP_SYSTEM_DEPS:-false}" == "true" ]]; then
        log_info "Instalação de dependências pulada"
        return 0
    fi
    
    log_operation "Instalação Node.js e PostgreSQL" "system_node_install"
    log_operation "Instalação PM2" "system_pm2_install"
    
    # Pular Docker já que não vamos usar
    log_info "Docker pulado - usando Redis nativo"
    
    log_operation "Dependências Puppeteer" "system_puppeteer_dependencies"
    log_operation "Instalação Snapd" "system_snapd_install"
    
    if [[ "${SKIP_NGINX_CONFIG:-false}" == "false" ]]; then
        log_operation "Instalação Nginx" "system_nginx_install"
    fi
    
    if [[ "${SKIP_SSL_CONFIG:-false}" == "false" ]]; then
        log_operation "Instalação Certbot" "system_certbot_install"
    fi
}

#######################################
# Configurar sistema base
# Arguments:
#   None
#######################################
configure_system() {
    log_checkpoint "CONFIGURAÇÃO DO SISTEMA"
    
    log_operation "Criação usuário deploy" "system_create_user"
    
    # Não fazer git clone - código já está local
    log_info "Git clone pulado - usando código local"
}

#######################################
# Instalar e configurar backend
# Arguments:
#   None
#######################################
install_backend() {
    log_checkpoint "INSTALAÇÃO BACKEND"
    
    # Usar Redis nativo em vez de Docker
    log_info "Configurando Redis nativo (sem Docker)"
    # TODO: Implementar redis nativo na próxima etapa
    
    log_operation "Configuração ambiente backend" "backend_set_env"
    log_operation "Instalação dependências backend" "backend_node_dependencies"  
    log_operation "Build do backend" "backend_node_build"
    log_operation "Migração do banco" "backend_db_migrate"
    log_operation "Seed do banco" "backend_db_seed"
    log_operation "Inicialização PM2 backend" "backend_start_pm2"
    
    if [[ "${SKIP_NGINX_CONFIG:-false}" == "false" ]]; then
        log_operation "Configuração Nginx backend" "backend_nginx_setup"
    fi
}

#######################################
# Instalar e configurar frontend
# Arguments:
#   None
#######################################
install_frontend() {
    log_checkpoint "INSTALAÇÃO FRONTEND"
    
    log_operation "Configuração ambiente frontend" "frontend_set_env"
    log_operation "Instalação dependências frontend" "frontend_node_dependencies"
    log_operation "Build do frontend" "frontend_node_build"
    log_operation "Inicialização PM2 frontend" "frontend_start_pm2"
    
    if [[ "${SKIP_NGINX_CONFIG:-false}" == "false" ]]; then
        log_operation "Configuração Nginx frontend" "frontend_nginx_setup"
    fi
}

#######################################
# Configurar rede e SSL
# Arguments:
#   None
#######################################
configure_network() {
    log_checkpoint "CONFIGURAÇÃO DE REDE"
    
    if [[ "${SKIP_NGINX_CONFIG:-false}" == "false" ]]; then
        log_operation "Configuração Nginx principal" "system_nginx_conf"
        log_operation "Reinicialização Nginx" "system_nginx_restart"
    fi
    
    if [[ "${SKIP_SSL_CONFIG:-false}" == "false" ]]; then
        log_operation "Configuração certificados SSL" "system_certbot_setup"
    fi
}

#######################################
# Configurar monitoramento (Sentry + Datadog)
# Arguments:
#   None
#######################################
configure_monitoring() {
    log_checkpoint "CONFIGURAÇÃO DE MONITORAMENTO"
    
    local monitoring_errors=0
    
    # Configurar Sentry se habilitado
    if [[ "${SENTRY_ENABLED:-false}" == "true" ]]; then
        log_info "Configurando integração Sentry..."
        
        if [[ -z "${SENTRY_DSN:-}" ]]; then
            log_warn "SENTRY_DSN não configurado - solicite as credenciais"
            log_info "Quando tiver as credenciais, execute:"
            log_info "  export SENTRY_AUTH_TOKEN='seu_token_aqui'"
            log_info "  export SENTRY_DSN='seu_dsn_aqui'"
            log_info "  sentry_setup_instance '$INSTANCE_NAME' \"\$SENTRY_AUTH_TOKEN\" \"\$SENTRY_DSN\""
        else
            if [[ -n "${SENTRY_AUTH_TOKEN:-}" ]]; then
                if sentry_setup_instance "$INSTANCE_NAME" "$SENTRY_AUTH_TOKEN" "$SENTRY_DSN"; then
                    log_info "✅ Sentry configurado com sucesso"
                else
                    log_error "❌ Falha na configuração do Sentry"
                    ((monitoring_errors++))
                fi
            else
                log_warn "SENTRY_AUTH_TOKEN não definido - configuração manual necessária"
                log_info "Execute: sentry_setup_instance '$INSTANCE_NAME' 'seu_token' '$SENTRY_DSN'"
            fi
        fi
    else
        log_info "Sentry desabilitado (SENTRY_ENABLED=false)"
    fi
    
    # Configurar Datadog se habilitado
    if [[ "${DATADOG_ENABLED:-false}" == "true" ]]; then
        log_info "Configurando integração Datadog..."
        
        if [[ -z "${DATADOG_API_KEY:-}" ]]; then
            log_warn "DATADOG_API_KEY não configurado - solicite as credenciais"
            log_info "Quando tiver as credenciais, execute:"
            log_info "  export DATADOG_API_KEY='sua_api_key_aqui'"
            log_info "  datadog_setup_instance '$INSTANCE_NAME' \"\$DATADOG_API_KEY\" '${DATADOG_SITE:-us1.datadoghq.com}'"
        else
            if datadog_setup_instance "$INSTANCE_NAME" "$DATADOG_API_KEY" "${DATADOG_SITE:-us1.datadoghq.com}"; then
                log_info "✅ Datadog configurado com sucesso"
            else
                log_error "❌ Falha na configuração do Datadog"
                ((monitoring_errors++))
            fi
        fi
    else
        log_info "Datadog desabilitado (DATADOG_ENABLED=false)"
    fi
    
    # Log do status final
    if [[ $monitoring_errors -eq 0 ]]; then
        log_info "✅ Monitoramento configurado sem erros"
    else
        log_warn "⚠️ Monitoramento configurado com $monitoring_errors erro(s)"
        log_info "Execute os comandos manuais listados acima quando tiver as credenciais"
    fi
    
    return 0  # Não falhar a instalação por problemas de monitoramento
}

#######################################
# Verificar saúde da instalação
# Arguments:
#   None
#######################################
health_check() {
    log_checkpoint "VERIFICAÇÃO DE SAÚDE"
    
    local errors=0
    
    # Verificar se PM2 está rodando os processos
    if ! sudo su - deploy -c "pm2 list | grep -q $INSTANCE_NAME"; then
        log_error "Processos PM2 não estão rodando"
        ((errors++))
    fi
    
    # Verificar se portas estão ouvindo
    local ports=("$FRONTEND_PORT" "$BACKEND_PORT" "$REDIS_PORT")
    for port in "${ports[@]}"; do
        if ! ss -tuln | grep -q ":$port "; then
            log_error "Porta $port não está ouvindo"
            ((errors++))
        fi
    done
    
    # Verificar Nginx se não foi pulado
    if [[ "${SKIP_NGINX_CONFIG:-false}" == "false" ]] && ! systemctl is-active nginx >/dev/null; then
        log_error "Nginx não está rodando"
        ((errors++))
    fi
    
    # Verificar PostgreSQL
    if ! systemctl is-active postgresql >/dev/null; then
        log_error "PostgreSQL não está rodando"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_info "✅ Instalação concluída com sucesso!"
        log_info "Frontend: $FRONTEND_URL"
        log_info "Backend: $BACKEND_URL"
        log_info "Instância: $INSTANCE_NAME"
    else
        log_error "❌ Instalação concluída com $errors erro(s)"
        return 1
    fi
}

#######################################
# Exibir informações finais
# Arguments:
#   None
#######################################
show_final_info() {
    log_info ""
    log_info "================================================="
    log_info "           INSTALAÇÃO CONCLUÍDA"  
    log_info "================================================="
    log_info ""
    log_info "📋 INFORMAÇÕES DA INSTALAÇÃO:"
    log_info "   Instância: $INSTANCE_NAME"
    log_info "   Frontend: $FRONTEND_URL"
    log_info "   Backend: $BACKEND_URL"
    log_info "   Max WhatsApp: $MAX_WHATSAPP_CONNECTIONS"
    log_info "   Max Usuários: $MAX_USERS"
    log_info ""
    log_info "📁 LOGS DISPONÍVEIS:"
    log_info "   Diretório: $LOG_DIR"
    log_info "   Principal: $MAIN_LOG_FILE"
    log_info "   Erros: $ERROR_LOG_FILE"
    log_info ""
    log_info "🔧 COMANDOS ÚTEIS:"
    log_info "   Ver processos: sudo su - deploy -c 'pm2 list'"
    log_info "   Ver logs: sudo su - deploy -c 'pm2 logs $INSTANCE_NAME'"
    log_info "   Reiniciar: sudo su - deploy -c 'pm2 restart all'"
    log_info "   Redis status: redis_native_status"
    log_info "   Limpeza completa: cleanup_system '$INSTANCE_NAME'"
    log_info ""
    
    # Informações de monitoramento
    if [[ "${SENTRY_ENABLED:-false}" == "true" ]] || [[ "${DATADOG_ENABLED:-false}" == "true" ]]; then
        log_info "📊 MONITORAMENTO:"
        
        if [[ "${SENTRY_ENABLED:-false}" == "true" ]]; then
            if [[ -n "${SENTRY_DSN:-}" ]]; then
                log_info "   ✅ Sentry: Configurado"
                log_info "      Dashboard: https://sentry.io/organizations/${SENTRY_WHATICKET_ORG:-whaticket}/projects/$INSTANCE_NAME/"
            else
                log_info "   ⚠️ Sentry: Habilitado mas DSN não configurado"
                log_info "      Configure: export SENTRY_DSN='seu_dsn' && sentry_setup_instance '$INSTANCE_NAME' 'token' \"\$SENTRY_DSN\""
            fi
        fi
        
        if [[ "${DATADOG_ENABLED:-false}" == "true" ]]; then
            if [[ -n "${DATADOG_API_KEY:-}" ]]; then
                log_info "   ✅ Datadog: Configurado"
                log_info "      Dashboard: https://app.${DATADOG_SITE:-us1.datadoghq.com}/dashboard/lists"
                log_info "      Logs: https://app.${DATADOG_SITE:-us1.datadoghq.com}/logs"
                log_info "      APM: https://app.${DATADOG_SITE:-us1.datadoghq.com}/apm/traces"
            else
                log_info "   ⚠️ Datadog: Habilitado mas API Key não configurada"
                log_info "      Configure: export DATADOG_API_KEY='sua_key' && datadog_setup_instance '$INSTANCE_NAME' \"\$DATADOG_API_KEY\""
            fi
        fi
        
        log_info ""
    fi
    
    # Configurações de desenvolvimento
    if [[ "${DEV_MODE:-false}" == "true" ]]; then
        log_info "🚧 MODO DESENVOLVIMENTO:"
        log_info "   Debug verbose: ${DEBUG_VERBOSE:-false}"
        log_info "   Security checks: ${SKIP_SECURITY_CHECKS:-false}"
        log_info "   ⚠️ NÃO use em produção!"
        log_info ""
    fi
    
    # Comandos de monitoramento manual
    log_info "🔍 COMANDOS DE MONITORAMENTO:"
    log_info "   Status geral: ./install-whaticket.sh --status"
    log_info "   Teste Sentry: sentry_test_configuration '$INSTANCE_NAME'"
    log_info "   Status Datadog: datadog_status"
    log_info "   Métricas sistema: log_system_metrics"
    log_info ""
    
    # Dicas de segurança
    log_info "🔒 SEGURANÇA:"
    log_info "   • Altere senhas padrão"
    log_info "   • Configure firewall (ufw enable)"
    log_info "   • Monitore logs regularmente"
    log_info "   • Mantenha sistema atualizado"
    log_info "   • Backup regular do banco de dados"
    log_info ""
    
    log_info "✅ Instalação finalizada com sucesso!"
    log_info "📞 Suporte: Verifique logs em caso de problemas"
}

#######################################
# Função principal
# Arguments:
#   None
#######################################
main() {
    local start_time
    start_time=$(date +%s)
    
    log_info "Iniciando instalação do Whaticket..."
    log_system_metrics
    
    # Validações iniciais
    validate_env_config || exit 1
    generate_missing_secrets
    check_system_requirements || exit 1
    
    # Preparação
    prepare_system
    
    # Instalação
    install_system_dependencies
    configure_system
    install_backend
    install_frontend
    configure_network
    configure_monitoring
    
    # Verificação final
    health_check
    
    # Finalização
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_info "Instalação concluída em ${duration} segundos"
    log_system_metrics
    
    show_final_info
    log_finalize
}

# Tratamento de sinais para limpeza
trap 'log_error "Instalação interrompida"; log_finalize; exit 1' INT TERM

# Executar se script foi chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi