#!/bin/bash
#
# Sistema de Limpeza Automática para Whaticket Installer
# Remove configurações antigas e prepara sistema para reinstalação
# Autor: Laowang (clean freak when it comes to configs)
#

# Source do logger se disponível
if [[ -f "${PROJECT_ROOT}/lib/logger.sh" ]]; then
    source "${PROJECT_ROOT}/lib/logger.sh"
else
    # Fallback para logs simples se logger não estiver disponível
    log_info() { echo "[INFO] $*"; }
    log_warn() { echo "[WARN] $*"; }
    log_error() { echo "[ERROR] $*"; }
    log_debug() { echo "[DEBUG] $*"; }
fi

# Diretórios padrão onde ficam as configurações
readonly NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
readonly NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
readonly PM2_CONFIG_DIR="/home/deploy/.pm2"
readonly DEPLOY_HOME="/home/deploy"
readonly POSTGRES_DATA_DIR="/var/lib/postgresql"
readonly REDIS_CONFIG_DIR="/etc/redis"
readonly SSL_CERT_DIR="/etc/letsencrypt/live"
readonly SYSTEMD_SERVICE_DIR="/etc/systemd/system"
readonly BACKUP_DIR="./backups/$(date +%Y%m%d_%H%M%S)"

#######################################
# Função principal de limpeza
# Arguments:
#   $1 - Nome da instância (opcional, se vazio limpa tudo)
#   $2 - Fazer backup antes da limpeza (true/false)
#######################################
cleanup_system() {
    local instance_name="$1"
    local make_backup="${2:-true}"
    
    log_info "Iniciando limpeza do sistema..."
    
    if [[ "$make_backup" == "true" ]]; then
        _create_backup_structure
    fi
    
    if [[ -n "$instance_name" ]]; then
        log_info "Limpeza específica para instância: $instance_name"
        _cleanup_instance_specific "$instance_name" "$make_backup"
    else
        log_warn "Limpeza COMPLETA do sistema - todas as instâncias serão removidas!"
        _cleanup_complete_system "$make_backup"
    fi
    
    log_info "Limpeza do sistema concluída"
}

#######################################
# Limpeza específica para uma instância
# Arguments:
#   $1 - Nome da instância
#   $2 - Fazer backup
#######################################
_cleanup_instance_specific() {
    local instance="$1"
    local make_backup="$2"
    
    log_info "Removendo configurações da instância: $instance"
    
    # Parar processos PM2
    _stop_pm2_processes "$instance"
    
    # Remover containers Docker (Redis)
    _remove_docker_containers "$instance" "$make_backup"
    
    # Remover configurações Nginx
    _remove_nginx_configs "$instance" "$make_backup"
    
    # Remover banco PostgreSQL
    _remove_postgres_database "$instance" "$make_backup"
    
    # Remover certificados SSL
    _remove_ssl_certificates "$instance" "$make_backup"
    
    # Remover arquivos da aplicação
    _remove_app_files "$instance" "$make_backup"
    
    # Remover serviços systemd customizados
    _remove_systemd_services "$instance" "$make_backup"
    
    # Limpeza de logs específicos
    _cleanup_logs "$instance"
}

#######################################
# Limpeza completa do sistema
# Arguments:
#   $1 - Fazer backup
#######################################
_cleanup_complete_system() {
    local make_backup="$1"
    
    log_warn "ATENÇÃO: Executando limpeza completa do sistema!"
    
    # Parar todos os processos PM2
    _stop_all_pm2_processes
    
    # Remover todos os containers relacionados ao Whaticket
    _remove_all_whaticket_containers "$make_backup"
    
    # Limpar todas as configurações Nginx
    _remove_all_nginx_configs "$make_backup"
    
    # Limpar bancos PostgreSQL
    _remove_all_postgres_databases "$make_backup"
    
    # Limpar certificados SSL
    _remove_all_ssl_certificates "$make_backup"
    
    # Limpar arquivos de aplicação
    _remove_all_app_files "$make_backup"
    
    # Limpar serviços systemd
    _remove_all_systemd_services "$make_backup"
    
    # Limpeza geral de logs
    _cleanup_all_logs
    
    # Limpar configurações residuais
    _cleanup_residual_configs
}

#######################################
# Para processos PM2
# Arguments:
#   $1 - Nome da instância
#######################################
_stop_pm2_processes() {
    local instance="$1"
    
    log_info "Parando processos PM2 para: $instance"
    
    if command -v pm2 >/dev/null 2>&1; then
        sudo su - deploy -c "
            pm2 stop ${instance}-frontend 2>/dev/null || true
            pm2 stop ${instance}-backend 2>/dev/null || true
            pm2 delete ${instance}-frontend 2>/dev/null || true
            pm2 delete ${instance}-backend 2>/dev/null || true
            pm2 save 2>/dev/null || true
        "
        log_info "Processos PM2 removidos para: $instance"
    else
        log_debug "PM2 não está instalado"
    fi
}

#######################################
# Para todos os processos PM2
# Arguments:
#   None
#######################################
_stop_all_pm2_processes() {
    log_warn "Parando TODOS os processos PM2"
    
    if command -v pm2 >/dev/null 2>&1; then
        sudo su - deploy -c "
            pm2 kill 2>/dev/null || true
            pm2 save --force 2>/dev/null || true
        "
        log_info "Todos os processos PM2 foram parados"
    fi
}

#######################################
# Remove containers Docker
# Arguments:
#   $1 - Nome da instância
#   $2 - Fazer backup
#######################################
_remove_docker_containers() {
    local instance="$1"
    local make_backup="$2"
    
    log_info "Removendo containers Docker para: $instance"
    
    if command -v docker >/dev/null 2>&1; then
        # Backup do Redis se solicitado
        if [[ "$make_backup" == "true" ]]; then
            _backup_redis_data "$instance"
        fi
        
        # Parar e remover container Redis
        sudo docker stop "redis-$instance" 2>/dev/null || true
        sudo docker rm "redis-$instance" 2>/dev/null || true
        
        # Remover volumes órfãos se existirem
        sudo docker volume prune -f 2>/dev/null || true
        
        log_info "Containers Docker removidos para: $instance"
    else
        log_debug "Docker não está instalado"
    fi
}

#######################################
# Remove todos os containers Whaticket
# Arguments:
#   $1 - Fazer backup
#######################################
_remove_all_whaticket_containers() {
    local make_backup="$1"
    
    log_warn "Removendo TODOS os containers Docker do Whaticket"
    
    if command -v docker >/dev/null 2>&1; then
        # Backup de todos os Redis se solicitado
        if [[ "$make_backup" == "true" ]]; then
            _backup_all_redis_data
        fi
        
        # Parar e remover todos os containers que começam com "redis-"
        sudo docker ps -a --format "{{.Names}}" | grep "^redis-" | while read -r container; do
            sudo docker stop "$container" 2>/dev/null || true
            sudo docker rm "$container" 2>/dev/null || true
            log_info "Container removido: $container"
        done
        
        # Limpeza geral
        sudo docker system prune -f 2>/dev/null || true
    fi
}

#######################################
# Remove configurações Nginx
# Arguments:
#   $1 - Nome da instância
#   $2 - Fazer backup
#######################################
_remove_nginx_configs() {
    local instance="$1"
    local make_backup="$2"
    
    log_info "Removendo configurações Nginx para: $instance"
    
    # Lista de arquivos de configuração
    local configs=(
        "${NGINX_SITES_ENABLED}/${instance}-frontend"
        "${NGINX_SITES_ENABLED}/${instance}-backend"
        "${NGINX_SITES_AVAILABLE}/${instance}-frontend"
        "${NGINX_SITES_AVAILABLE}/${instance}-backend"
    )
    
    for config in "${configs[@]}"; do
        if [[ -f "$config" ]]; then
            if [[ "$make_backup" == "true" ]]; then
                _backup_file "$config"
            fi
            sudo rm -f "$config"
            log_info "Removido: $config"
        fi
    done
    
    # Recarregar Nginx se estiver rodando
    if systemctl is-active nginx >/dev/null 2>&1; then
        sudo systemctl reload nginx
        log_info "Nginx recarregado"
    fi
}

#######################################
# Remove todas as configurações Nginx do Whaticket
# Arguments:
#   $1 - Fazer backup
#######################################
_remove_all_nginx_configs() {
    local make_backup="$1"
    
    log_warn "Removendo TODAS as configurações Nginx do Whaticket"
    
    # Procurar todos os arquivos que podem ser do Whaticket
    find "$NGINX_SITES_ENABLED" -name "*-frontend" -o -name "*-backend" 2>/dev/null | while read -r config; do
        if [[ "$make_backup" == "true" ]]; then
            _backup_file "$config"
        fi
        sudo rm -f "$config"
        log_info "Removido: $config"
    done
    
    find "$NGINX_SITES_AVAILABLE" -name "*-frontend" -o -name "*-backend" 2>/dev/null | while read -r config; do
        if [[ "$make_backup" == "true" ]]; then
            _backup_file "$config"
        fi
        sudo rm -f "$config"
        log_info "Removido: $config"
    done
    
    # Recarregar Nginx
    if systemctl is-active nginx >/dev/null 2>&1; then
        sudo systemctl reload nginx
    fi
}

#######################################
# Remove banco PostgreSQL
# Arguments:
#   $1 - Nome da instância
#   $2 - Fazer backup
#######################################
_remove_postgres_database() {
    local instance="$1"
    local make_backup="$2"
    
    log_info "Removendo banco PostgreSQL para: $instance"
    
    if command -v psql >/dev/null 2>&1; then
        # Backup do banco se solicitado
        if [[ "$make_backup" == "true" ]]; then
            _backup_postgres_database "$instance"
        fi
        
        # Remover banco e usuário
        sudo su - postgres -c "
            dropdb $instance 2>/dev/null || true
            dropuser $instance 2>/dev/null || true
        "
        log_info "Banco PostgreSQL removido para: $instance"
    else
        log_debug "PostgreSQL não está instalado"
    fi
}

#######################################
# Remove todos os bancos Whaticket
# Arguments:
#   $1 - Fazer backup
#######################################
_remove_all_postgres_databases() {
    local make_backup="$1"
    
    log_warn "Esta função precisaria de uma lista específica dos bancos do Whaticket"
    log_warn "Por segurança, não vou remover todos os bancos PostgreSQL"
    log_info "Para remover bancos específicos, use cleanup_system com nome da instância"
}

#######################################
# Remove certificados SSL
# Arguments:
#   $1 - Nome da instância
#   $2 - Fazer backup
#######################################
_remove_ssl_certificates() {
    local instance="$1"
    local make_backup="$2"
    
    log_info "Removendo certificados SSL para: $instance"
    
    # Certificados Let's Encrypt ficam organizados por domínio
    # Precisaríamos saber os domínios para remover corretamente
    log_warn "Remoção de certificados SSL requer domínios específicos"
    log_info "Certificados em $SSL_CERT_DIR devem ser verificados manualmente"
}

#######################################
# Remove arquivos da aplicação
# Arguments:
#   $1 - Nome da instância
#   $2 - Fazer backup
#######################################
_remove_app_files() {
    local instance="$1"
    local make_backup="$2"
    
    log_info "Removendo arquivos da aplicação para: $instance"
    
    local app_dir="$DEPLOY_HOME/$instance"
    
    if [[ -d "$app_dir" ]]; then
        if [[ "$make_backup" == "true" ]]; then
            _backup_directory "$app_dir"
        fi
        
        sudo rm -rf "$app_dir"
        log_info "Diretório removido: $app_dir"
    fi
}

#######################################
# Cria estrutura de backup
# Arguments:
#   None
#######################################
_create_backup_structure() {
    log_info "Criando estrutura de backup em: $BACKUP_DIR"
    
    mkdir -p "$BACKUP_DIR"/{nginx,postgres,redis,app-files,ssl,systemd,logs}
    
    echo "# Backup criado em: $(date)" > "$BACKUP_DIR/backup_info.txt"
    echo "# Sistema: $(uname -a)" >> "$BACKUP_DIR/backup_info.txt"
    echo "# Usuário: $(whoami)" >> "$BACKUP_DIR/backup_info.txt"
}

#######################################
# Backup de um arquivo
# Arguments:
#   $1 - Caminho do arquivo
#######################################
_backup_file() {
    local file_path="$1"
    
    if [[ -f "$file_path" ]]; then
        local backup_path="$BACKUP_DIR/$(dirname "$file_path")"
        mkdir -p "$backup_path"
        cp "$file_path" "$backup_path/"
        log_debug "Backup criado: $file_path -> $backup_path"
    fi
}

#######################################
# Backup de um diretório
# Arguments:
#   $1 - Caminho do diretório
#######################################
_backup_directory() {
    local dir_path="$1"
    local dir_name
    dir_name=$(basename "$dir_path")
    
    if [[ -d "$dir_path" ]]; then
        tar -czf "$BACKUP_DIR/app-files/${dir_name}.tar.gz" -C "$(dirname "$dir_path")" "$dir_name"
        log_info "Backup do diretório criado: ${dir_name}.tar.gz"
    fi
}

#######################################
# Backup do banco PostgreSQL
# Arguments:
#   $1 - Nome do banco
#######################################
_backup_postgres_database() {
    local database="$1"
    
    log_info "Criando backup do banco: $database"
    
    sudo su - postgres -c "
        pg_dump $database > $BACKUP_DIR/postgres/${database}.sql 2>/dev/null || true
    "
}

#######################################
# Backup dos dados Redis
# Arguments:
#   $1 - Nome da instância
#######################################
_backup_redis_data() {
    local instance="$1"
    
    log_info "Criando backup dos dados Redis: $instance"
    
    # Criar dump do Redis se o container estiver rodando
    if sudo docker ps --format "{{.Names}}" | grep -q "redis-$instance"; then
        sudo docker exec "redis-$instance" redis-cli BGSAVE
        sleep 2
        sudo docker cp "redis-$instance:/data/dump.rdb" "$BACKUP_DIR/redis/redis-${instance}.rdb"
    fi
}

#######################################
# Limpeza de logs
# Arguments:
#   $1 - Nome da instância
#######################################
_cleanup_logs() {
    local instance="$1"
    
    log_info "Limpando logs para: $instance"
    
    # Logs PM2
    sudo su - deploy -c "
        rm -rf ~/.pm2/logs/*${instance}* 2>/dev/null || true
    "
    
    # Logs da aplicação se existirem
    if [[ -d "$DEPLOY_HOME/$instance/logs" ]]; then
        rm -rf "$DEPLOY_HOME/$instance/logs"/*
    fi
}

#######################################
# Remove serviços systemd customizados
# Arguments:
#   $1 - Nome da instância
#   $2 - Fazer backup
#######################################
_remove_systemd_services() {
    local instance="$1"
    local make_backup="$2"
    
    log_info "Removendo serviços systemd para: $instance"
    
    # Procurar serviços que podem estar relacionados
    find "$SYSTEMD_SERVICE_DIR" -name "*${instance}*" 2>/dev/null | while read -r service_file; do
        if [[ "$make_backup" == "true" ]]; then
            _backup_file "$service_file"
        fi
        
        local service_name
        service_name=$(basename "$service_file")
        
        sudo systemctl stop "$service_name" 2>/dev/null || true
        sudo systemctl disable "$service_name" 2>/dev/null || true
        sudo rm -f "$service_file"
        
        log_info "Serviço removido: $service_name"
    done
    
    sudo systemctl daemon-reload
}

#######################################
# Verificação pré-limpeza
# Arguments:
#   None
#######################################
cleanup_check() {
    log_info "Verificando sistema antes da limpeza..."
    
    # Verificar se é root ou tem sudo
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        log_error "Este script precisa de privilégios de root ou sudo sem senha"
        return 1
    fi
    
    # Verificar serviços críticos
    local critical_services=("nginx" "postgresql")
    for service in "${critical_services[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            log_warn "Serviço crítico detectado: $service"
        fi
    done
    
    # Verificar espaço em disco para backup
    local available_space
    available_space=$(df . | tail -1 | awk '{print $4}')
    if [[ $available_space -lt 1000000 ]]; then # Menos de 1GB
        log_warn "Pouco espaço em disco disponível: ${available_space}KB"
    fi
    
    log_info "Verificação pré-limpeza concluída"
    return 0
}