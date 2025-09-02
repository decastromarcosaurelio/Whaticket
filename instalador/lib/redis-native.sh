#!/bin/bash
#
# Redis Nativo - Substituição para Docker Redis
# Instala e configura Redis como serviço systemd nativo
# Autor: Laowang (Docker-free zone enforcer)
#

# Source do logger se disponível
if [[ -f "${PROJECT_ROOT}/lib/logger.sh" ]]; then
    source "${PROJECT_ROOT}/lib/logger.sh"
else
    # Fallback para logs simples
    log_info() { echo "[INFO] $*"; }
    log_warn() { echo "[WARN] $*"; }
    log_error() { echo "[ERROR] $*"; }
    log_debug() { echo "[DEBUG] $*"; }
    log_operation() { echo "[OPERATION] $1"; eval "$2"; }
fi

# Configurações padrão
readonly REDIS_CONFIG_DIR="/etc/redis"
readonly REDIS_DATA_DIR="/var/lib/redis"
readonly REDIS_LOG_DIR="/var/log/redis"
readonly REDIS_USER="redis"

#######################################
# Instala Redis nativo no Ubuntu
# Arguments:
#   None
#######################################
redis_native_install() {
    log_info "Instalando Redis nativo..."
    
    # Atualizar cache de pacotes
    log_operation "Atualizando cache APT" "sudo apt-get update"
    
    # Instalar Redis
    log_operation "Instalando Redis Server" "sudo apt-get install -y redis-server"
    
    # Verificar se instalou corretamente
    if ! command -v redis-server >/dev/null 2>&1; then
        log_error "Falha na instalação do Redis"
        return 1
    fi
    
    log_info "Redis instalado com sucesso"
    return 0
}

#######################################
# Configura instância Redis para uma empresa específica
# Arguments:
#   $1 - Nome da instância
#   $2 - Porta Redis
#   $3 - Senha Redis
#   $4 - Memória máxima (opcional, padrão: 256mb)
#######################################
redis_native_configure_instance() {
    local instance_name="$1"
    local redis_port="$2"
    local redis_password="$3"
    local max_memory="${4:-256mb}"
    
    log_info "Configurando Redis para instância: $instance_name"
    
    # Validar parâmetros
    if [[ -z "$instance_name" || -z "$redis_port" || -z "$redis_password" ]]; then
        log_error "Parâmetros obrigatórios: instance_name, redis_port, redis_password"
        return 1
    fi
    
    # Criar diretórios específicos da instância
    local instance_config_dir="$REDIS_CONFIG_DIR/$instance_name"
    local instance_data_dir="$REDIS_DATA_DIR/$instance_name"
    local instance_log_dir="$REDIS_LOG_DIR/$instance_name"
    
    sudo mkdir -p "$instance_config_dir"
    sudo mkdir -p "$instance_data_dir"
    sudo mkdir -p "$instance_log_dir"
    
    # Definir permissões corretas
    sudo chown -R $REDIS_USER:$REDIS_USER "$instance_data_dir"
    sudo chown -R $REDIS_USER:$REDIS_USER "$instance_log_dir"
    sudo chmod 750 "$instance_data_dir"
    sudo chmod 755 "$instance_log_dir"
    
    # Criar arquivo de configuração específico
    local config_file="$instance_config_dir/redis.conf"
    
    log_info "Criando configuração Redis: $config_file"
    
    sudo tee "$config_file" > /dev/null <<EOF
# Redis Configuration for Whaticket Instance: $instance_name
# Generated on: $(date)

# Network
bind 127.0.0.1
port $redis_port
protected-mode yes
timeout 300
keepalive 300

# General
daemonize yes
supervised systemd
pidfile /var/run/redis/redis-${instance_name}.pid

# Logging
loglevel notice
logfile $instance_log_dir/redis.log
syslog-enabled yes
syslog-ident redis-$instance_name

# Snapshotting
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump-${instance_name}.rdb
dir $instance_data_dir

# Replication
# slave-serve-stale-data yes
# slave-read-only yes

# Security
requirepass $redis_password
rename-command FLUSHDB FLUSHDB_$instance_name
rename-command FLUSHALL FLUSHALL_$instance_name
rename-command DEBUG ""
rename-command CONFIG CONFIG_$instance_name

# Limits
maxclients 10000

# Memory management
maxmemory $max_memory
maxmemory-policy ${REDIS_MAX_MEMORY_POLICY:-allkeys-lru}
maxmemory-samples 5

# Lazy freeing
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes

# Append only file
appendonly yes
appendfilename "appendonly-${instance_name}.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
aof-load-truncated yes
aof-use-rdb-preamble yes

# Lua scripting
lua-time-limit 5000

# Slow log
slowlog-log-slower-than 10000
slowlog-max-len 128

# Latency monitor
latency-monitor-threshold 100

# Event notification
notify-keyspace-events ""

# Hash type
hash-max-ziplist-entries 512
hash-max-ziplist-value 64

# List type
list-max-ziplist-size -2
list-compress-depth 0

# Set type
set-max-intset-entries 512

# Zset type
zset-max-ziplist-entries 128
zset-max-ziplist-value 64

# HyperLogLog
hll-sparse-max-bytes 3000

# Streams
stream-node-max-bytes 4096
stream-node-max-entries 100

# Client output buffer limits
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit slave 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60

# Client query buffer
client-query-buffer-limit 1gb

# Protocol
proto-max-bulk-len 512mb

# Frequency
hz 10

# Dynamic HZ
dynamic-hz yes

# AOF rewrite
aof-rewrite-incremental-fsync yes

# RDB save
rdb-save-incremental-fsync yes
EOF

    log_info "Configuração Redis criada: $config_file"
    return 0
}

#######################################
# Cria serviço systemd para instância Redis
# Arguments:
#   $1 - Nome da instância
#######################################
redis_native_create_service() {
    local instance_name="$1"
    
    log_info "Criando serviço systemd para: redis-$instance_name"
    
    local service_file="/etc/systemd/system/redis-${instance_name}.service"
    local config_file="$REDIS_CONFIG_DIR/$instance_name/redis.conf"
    
    # Verificar se arquivo de configuração existe
    if [[ ! -f "$config_file" ]]; then
        log_error "Arquivo de configuração não encontrado: $config_file"
        return 1
    fi
    
    # Criar arquivo de serviço
    sudo tee "$service_file" > /dev/null <<EOF
[Unit]
Description=Redis In-Memory Data Store (Instance: $instance_name)
After=network.target
Documentation=http://redis.io/documentation

[Service]
Type=notify
ExecStart=/usr/bin/redis-server $config_file
ExecStop=/usr/bin/redis-cli -p $redis_port shutdown
ExecReload=/bin/kill -USR2 \$MAINPID
TimeoutStopSec=0
Restart=always
RestartSec=3
User=$REDIS_USER
Group=$REDIS_USER

# Security
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=$REDIS_DATA_DIR/$instance_name $REDIS_LOG_DIR/$instance_name /var/run/redis
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@debug @mount @cpu-emulation @obsolete @privileged

# Resource limits
LimitNOFILE=65535
LimitNPROC=65535

[Install]
WantedBy=multi-user.target
EOF

    # Recarregar systemd
    sudo systemctl daemon-reload
    
    log_info "Serviço criado: $service_file"
    return 0
}

#######################################
# Inicia e habilita serviço Redis
# Arguments:
#   $1 - Nome da instância
#######################################
redis_native_start_service() {
    local instance_name="$1"
    local service_name="redis-${instance_name}"
    
    log_info "Iniciando serviço: $service_name"
    
    # Habilitar serviço para iniciar no boot
    log_operation "Habilitando serviço $service_name" "sudo systemctl enable $service_name"
    
    # Iniciar serviço
    log_operation "Iniciando serviço $service_name" "sudo systemctl start $service_name"
    
    # Verificar se está rodando
    if sudo systemctl is-active "$service_name" >/dev/null; then
        log_info "✅ Serviço $service_name iniciado com sucesso"
        
        # Verificar conectividade
        _redis_test_connection "$instance_name"
        
        return 0
    else
        log_error "❌ Falha ao iniciar serviço $service_name"
        
        # Mostrar logs do serviço para debug
        log_error "Logs do serviço:"
        sudo journalctl -u "$service_name" --no-pager --lines=10
        
        return 1
    fi
}

#######################################
# Testa conexão com Redis
# Arguments:
#   $1 - Nome da instância
#######################################
_redis_test_connection() {
    local instance_name="$1"
    local redis_port="${redis_port:-6379}"  # Usar porta da variável global ou padrão
    local redis_password="${redis_password:-}"
    
    log_info "Testando conexão Redis na porta $redis_port..."
    
    local redis_cli_cmd="redis-cli -p $redis_port"
    if [[ -n "$redis_password" ]]; then
        redis_cli_cmd="$redis_cli_cmd -a $redis_password"
    fi
    
    # Teste de ping
    if $redis_cli_cmd ping >/dev/null 2>&1; then
        log_info "✅ Redis respondendo corretamente"
        
        # Teste de escrita/leitura
        local test_key="test_key_$$"
        local test_value="test_value_$(date +%s)"
        
        if $redis_cli_cmd set "$test_key" "$test_value" >/dev/null 2>&1 && \
           [[ "$($redis_cli_cmd get "$test_key" 2>/dev/null)" == "$test_value" ]]; then
            log_info "✅ Teste de escrita/leitura Redis OK"
            $redis_cli_cmd del "$test_key" >/dev/null 2>&1
        else
            log_warn "⚠️  Falha no teste de escrita/leitura Redis"
        fi
        
        return 0
    else
        log_error "❌ Redis não está respondendo"
        return 1
    fi
}

#######################################
# Para serviço Redis de uma instância
# Arguments:
#   $1 - Nome da instância
#######################################
redis_native_stop_service() {
    local instance_name="$1"
    local service_name="redis-${instance_name}"
    
    log_info "Parando serviço: $service_name"
    
    sudo systemctl stop "$service_name"
    sudo systemctl disable "$service_name"
    
    log_info "Serviço $service_name parado"
}

#######################################
# Remove completamente instância Redis
# Arguments:
#   $1 - Nome da instância
#   $2 - Fazer backup (true/false)
#######################################
redis_native_remove_instance() {
    local instance_name="$1"
    local make_backup="${2:-true}"
    local service_name="redis-${instance_name}"
    
    log_info "Removendo instância Redis: $instance_name"
    
    # Parar serviço
    redis_native_stop_service "$instance_name"
    
    # Backup se solicitado
    if [[ "$make_backup" == "true" ]]; then
        _redis_backup_instance "$instance_name"
    fi
    
    # Remover arquivos de configuração
    sudo rm -rf "$REDIS_CONFIG_DIR/$instance_name"
    
    # Remover dados (cuidado!)
    sudo rm -rf "$REDIS_DATA_DIR/$instance_name"
    
    # Remover logs
    sudo rm -rf "$REDIS_LOG_DIR/$instance_name"
    
    # Remover serviço systemd
    sudo rm -f "/etc/systemd/system/${service_name}.service"
    sudo systemctl daemon-reload
    
    log_info "Instância Redis removida: $instance_name"
}

#######################################
# Backup de instância Redis
# Arguments:
#   $1 - Nome da instância
#######################################
_redis_backup_instance() {
    local instance_name="$1"
    local backup_dir="${BACKUP_DIR:-./backups}/redis"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    
    log_info "Criando backup da instância Redis: $instance_name"
    
    mkdir -p "$backup_dir"
    
    # Backup dos dados
    if [[ -d "$REDIS_DATA_DIR/$instance_name" ]]; then
        tar -czf "$backup_dir/redis-${instance_name}-data-${timestamp}.tar.gz" \
            -C "$REDIS_DATA_DIR" "$instance_name"
    fi
    
    # Backup da configuração
    if [[ -d "$REDIS_CONFIG_DIR/$instance_name" ]]; then
        tar -czf "$backup_dir/redis-${instance_name}-config-${timestamp}.tar.gz" \
            -C "$REDIS_CONFIG_DIR" "$instance_name"
    fi
    
    log_info "Backup Redis criado em: $backup_dir"
}

#######################################
# Função principal compatível com script antigo
# Substitui backend_redis_create() do _backend.sh
# Arguments:
#   None (usa variáveis globais)
#######################################
backend_redis_create() {
    log_info "💻 Criando Redis nativo & Banco Postgres..."
    
    # Instalar Redis se não estiver instalado
    if ! command -v redis-server >/dev/null 2>&1; then
        redis_native_install || return 1
    fi
    
    # Configurar instância Redis
    redis_native_configure_instance "$instancia_add" "$redis_port" "$mysql_root_password" || return 1
    
    # Criar serviço
    redis_native_create_service "$instancia_add" || return 1
    
    # Iniciar serviço
    redis_native_start_service "$instancia_add" || return 1
    
    # Configurar PostgreSQL (mantém lógica original)
    log_info "Configurando banco PostgreSQL..."
    
    sudo su - root <<EOF
  usermod -aG postgres deploy
  
  sleep 2
  
  sudo su - postgres <<PGEOF
  createdb $instancia_add;
  psql -c "CREATE USER $instancia_add SUPERUSER INHERIT CREATEDB CREATEROLE;"
  psql -c "ALTER USER $instancia_add PASSWORD '$mysql_root_password';"
PGEOF
  
  exit
EOF

    sleep 2
    
    log_info "✅ Redis nativo e PostgreSQL configurados!"
    return 0
}

#######################################
# Status de todas as instâncias Redis
# Arguments:
#   None
#######################################
redis_native_status() {
    log_info "Status das instâncias Redis nativas:"
    
    # Listar serviços Redis
    systemctl list-units "redis-*" --no-pager --no-legend | while read -r service_status; do
        local service_name
        service_name=$(echo "$service_status" | awk '{print $1}')
        local status
        status=$(echo "$service_status" | awk '{print $3}')
        
        if [[ "$status" == "active" ]]; then
            log_info "✅ $service_name - ATIVO"
        else
            log_warn "❌ $service_name - $status"
        fi
    done
}