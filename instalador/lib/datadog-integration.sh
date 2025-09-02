#!/bin/bash
#
# Integração Datadog - Monitoramento e Métricas
# Instala e configura Datadog Agent para monitoramento do Whaticket
# Autor: Laowang (metrics obsessed engineer)
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

# Configurações Datadog
readonly DATADOG_AGENT_MAJOR_VERSION=7
readonly DATADOG_APT_KEYRING="/usr/share/keyrings/datadog-archive-keyring.gpg"
readonly DATADOG_APT_REPO="https://apt.datadoghq.com"
readonly DATADOG_CONFIG_DIR="/etc/datadog-agent"
readonly DATADOG_LOG_DIR="/var/log/datadog"
readonly DATADOG_RUN_DIR="/opt/datadog-agent/run"

#######################################
# Instala repositório e chaves Datadog
# Arguments:
#   None
#######################################
datadog_setup_repository() {
    log_info "Configurando repositório Datadog..."
    
    # Instalar dependências
    log_operation "Instalando dependências" "
        sudo apt-get update &&
        sudo apt-get install -y apt-transport-https curl gnupg
    "
    
    # Adicionar chave GPG do Datadog
    log_operation "Adicionando chave GPG Datadog" "
        sudo sh -c \"echo 'deb [signed-by=$DATADOG_APT_KEYRING] $DATADOG_APT_REPO/ stable main' > /etc/apt/sources.list.d/datadog.list\"
    "
    
    # Download e instalação da chave
    if ! sudo test -f "$DATADOG_APT_KEYRING"; then
        log_operation "Download da chave GPG" "
            sudo touch '$DATADOG_APT_KEYRING' &&
            sudo chmod a+r '$DATADOG_APT_KEYRING' &&
            curl -o /tmp/DATADOG_APT_KEY_CURRENT.public 'https://keys.datadoghq.com/DATADOG_APT_KEY_CURRENT.public' &&
            sudo gpg --no-default-keyring --keyring '$DATADOG_APT_KEYRING' --import /tmp/DATADOG_APT_KEY_CURRENT.public &&
            rm /tmp/DATADOG_APT_KEY_CURRENT.public
        "
    fi
    
    # Atualizar cache de pacotes
    log_operation "Atualizando cache APT" "sudo apt-get update"
    
    log_info "✅ Repositório Datadog configurado"
    return 0
}

#######################################
# Instala Datadog Agent
# Arguments:
#   $1 - API Key do Datadog
#   $2 - Site do Datadog (opcional, padrão: us1.datadoghq.com)
#######################################
datadog_install_agent() {
    local api_key="$1"
    local datadog_site="${2:-us1.datadoghq.com}"
    
    if [[ -z "$api_key" ]]; then
        log_error "API Key do Datadog é obrigatória"
        log_info "Obtenha sua API key em: https://app.datadoghq.com/organization-settings/api-keys"
        return 1
    fi
    
    log_info "Instalando Datadog Agent..."
    
    # Verificar se já está instalado
    if systemctl is-active datadog-agent >/dev/null 2>&1; then
        log_info "Datadog Agent já está instalado e ativo"
        return 0
    fi
    
    # Configurar repositório se necessário
    if [[ ! -f "/etc/apt/sources.list.d/datadog.list" ]]; then
        datadog_setup_repository || return 1
    fi
    
    # Instalar agent
    log_operation "Instalando Datadog Agent" "
        sudo apt-get install -y datadog-agent
    "
    
    # Verificar instalação
    if ! command -v datadog-agent >/dev/null 2>&1; then
        log_error "Falha na instalação do Datadog Agent"
        return 1
    fi
    
    log_info "✅ Datadog Agent instalado"
    return 0
}

#######################################
# Configura Datadog Agent básico
# Arguments:
#   $1 - API Key do Datadog
#   $2 - Site do Datadog
#   $3 - Nome da instância
#######################################
datadog_configure_agent() {
    local api_key="$1"
    local datadog_site="$2"
    local instance_name="$3"
    
    log_info "Configurando Datadog Agent..."
    
    # Criar configuração principal
    local config_file="$DATADOG_CONFIG_DIR/datadog.yaml"
    
    # Backup da configuração existente
    if [[ -f "$config_file" ]]; then
        sudo cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Criar nova configuração
    sudo tee "$config_file" > /dev/null <<EOF
# Datadog Agent Configuration for Whaticket Instance: $instance_name
# Generated on: $(date)

# API Key (obrigatória)
api_key: $api_key

# Site Datadog
site: $datadog_site

# Hostname e tags
hostname: $(hostname)-$instance_name
tags:
  - env:${DATADOG_ENV:-production}
  - service:${DATADOG_SERVICE_NAME:-whaticket-$instance_name}
  - instance:$instance_name
  - application:whaticket
  - stack:nodejs

# Configurações de logs
logs_enabled: true
logs_config:
  container_collect_all: false
  processing_rules:
    - type: exclude_at_match
      name: exclude_debug_logs
      pattern: "DEBUG"

# APM (Application Performance Monitoring)
apm_config:
  enabled: true
  max_traces_per_second: 10
  max_events_per_second: 200

# Process monitoring
process_config:
  enabled: true

# Network monitoring
network_config:
  enabled: false

# Sistema de check de saúde
health_port: 5555

# Configurações de coleta
collect_ec2_tags: false
collect_gce_tags: false

# Intervalo de coleta (default: 15s)
check_runners: 4

# Configurações de proxy (se necessário)
# proxy:
#   http: http://proxy.example.com:8080
#   https: https://proxy.example.com:8080
#   no_proxy:
#     - localhost
#     - 127.0.0.1

# Configurações de segurança
secret_backend_command: /bin/true

# Configurações avançadas
forwarder_timeout: 20
default_integration_http_timeout: 9

# JMX (para Java apps, se houver)
jmx_check_period: 15

# Configurações específicas do sistema
system_probe_config:
  sysprobe_socket: /opt/datadog-agent/run/sysprobe.sock

# External tags
# external_config:
#   external_agent_dd_url: https://app.datadoghq.com

# Configurações de inventário
inventories_configuration_enabled: true
inventories_checks_configuration_enabled: true

# Configurações de compliance
compliance_config:
  enabled: false

# Runtime security
runtime_security_config:
  enabled: false
EOF

    # Definir permissões corretas
    sudo chown dd-agent:dd-agent "$config_file"
    sudo chmod 640 "$config_file"
    
    log_info "✅ Configuração básica do Datadog criada"
    return 0
}

#######################################
# Configura coleta de logs específicos do Whaticket
# Arguments:
#   $1 - Nome da instância
#######################################
datadog_configure_logs() {
    local instance_name="$1"
    local logs_config_dir="$DATADOG_CONFIG_DIR/conf.d"
    
    log_info "Configurando coleta de logs para: $instance_name"
    
    # Configurar logs do Nginx
    _datadog_configure_nginx_logs "$instance_name" "$logs_config_dir"
    
    # Configurar logs do PM2
    _datadog_configure_pm2_logs "$instance_name" "$logs_config_dir"
    
    # Configurar logs do PostgreSQL
    _datadog_configure_postgres_logs "$instance_name" "$logs_config_dir"
    
    # Configurar logs do Redis
    _datadog_configure_redis_logs "$instance_name" "$logs_config_dir"
    
    # Configurar logs da aplicação
    _datadog_configure_app_logs "$instance_name" "$logs_config_dir"
    
    log_info "✅ Coleta de logs configurada"
    return 0
}

#######################################
# Configura logs do Nginx
# Arguments:
#   $1 - Nome da instância
#   $2 - Diretório de configuração
#######################################
_datadog_configure_nginx_logs() {
    local instance_name="$1"
    local config_dir="$2"
    local nginx_config="$config_dir/nginx.d/conf.yaml"
    
    sudo mkdir -p "$config_dir/nginx.d"
    
    sudo tee "$nginx_config" > /dev/null <<EOF
# Nginx integration for $instance_name
logs:
  - type: file
    path: /var/log/nginx/access.log
    service: nginx
    source: nginx
    tags:
      - instance:$instance_name
      - component:nginx
      - log_type:access
    
  - type: file
    path: /var/log/nginx/error.log
    service: nginx
    source: nginx
    tags:
      - instance:$instance_name
      - component:nginx
      - log_type:error
    log_processing_rules:
      - type: multi_line
        name: new_log_start_with_date
        pattern: \d{4}/\d{2}/\d{2}
EOF

    sudo chown dd-agent:dd-agent "$nginx_config"
    log_debug "Configuração Nginx criada: $nginx_config"
}

#######################################
# Configura logs do PM2
# Arguments:
#   $1 - Nome da instância
#   $2 - Diretório de configuração
#######################################
_datadog_configure_pm2_logs() {
    local instance_name="$1"
    local config_dir="$2"
    local pm2_config="$config_dir/pm2_logs.d/conf.yaml"
    
    sudo mkdir -p "$config_dir/pm2_logs.d"
    
    sudo tee "$pm2_config" > /dev/null <<EOF
# PM2 logs for $instance_name
logs:
  - type: file
    path: /home/deploy/.pm2/logs/${instance_name}-frontend-out.log
    service: ${instance_name}-frontend
    source: pm2
    tags:
      - instance:$instance_name
      - component:frontend
      - log_type:stdout
    
  - type: file
    path: /home/deploy/.pm2/logs/${instance_name}-frontend-error.log
    service: ${instance_name}-frontend
    source: pm2
    tags:
      - instance:$instance_name
      - component:frontend
      - log_type:stderr
    
  - type: file
    path: /home/deploy/.pm2/logs/${instance_name}-backend-out.log
    service: ${instance_name}-backend
    source: pm2
    tags:
      - instance:$instance_name
      - component:backend
      - log_type:stdout
    
  - type: file
    path: /home/deploy/.pm2/logs/${instance_name}-backend-error.log
    service: ${instance_name}-backend
    source: pm2
    tags:
      - instance:$instance_name
      - component:backend
      - log_type:stderr
EOF

    sudo chown dd-agent:dd-agent "$pm2_config"
    log_debug "Configuração PM2 criada: $pm2_config"
}

#######################################
# Configura logs do PostgreSQL
# Arguments:
#   $1 - Nome da instância
#   $2 - Diretório de configuração
#######################################
_datadog_configure_postgres_logs() {
    local instance_name="$1"
    local config_dir="$2"
    local postgres_config="$config_dir/postgres.d/conf.yaml"
    
    sudo mkdir -p "$config_dir/postgres.d"
    
    sudo tee "$postgres_config" > /dev/null <<EOF
# PostgreSQL integration for $instance_name
init_config:

instances:
  - host: localhost
    port: 5432
    username: datadog
    dbname: $instance_name
    tags:
      - instance:$instance_name
      - component:postgresql

logs:
  - type: file
    path: /var/log/postgresql/postgresql-*-main.log
    service: postgresql
    source: postgresql
    tags:
      - instance:$instance_name
      - component:postgresql
    log_processing_rules:
      - type: multi_line
        name: new_log_start_with_date
        pattern: \d{4}-\d{2}-\d{2}
EOF

    sudo chown dd-agent:dd-agent "$postgres_config"
    log_debug "Configuração PostgreSQL criada: $postgres_config"
}

#######################################
# Configura logs do Redis
# Arguments:
#   $1 - Nome da instância
#   $2 - Diretório de configuração
#######################################
_datadog_configure_redis_logs() {
    local instance_name="$1"
    local config_dir="$2"
    local redis_config="$config_dir/redisdb.d/conf.yaml"
    
    sudo mkdir -p "$config_dir/redisdb.d"
    
    sudo tee "$redis_config" > /dev/null <<EOF
# Redis integration for $instance_name
init_config:

instances:
  - host: localhost
    port: ${redis_port:-6379}
    password: ${redis_password}
    tags:
      - instance:$instance_name
      - component:redis

logs:
  - type: file
    path: /var/log/redis/$instance_name/redis.log
    service: redis-$instance_name
    source: redis
    tags:
      - instance:$instance_name
      - component:redis
EOF

    sudo chown dd-agent:dd-agent "$redis_config"
    log_debug "Configuração Redis criada: $redis_config"
}

#######################################
# Configura logs da aplicação
# Arguments:
#   $1 - Nome da instância
#   $2 - Diretório de configuração
#######################################
_datadog_configure_app_logs() {
    local instance_name="$1"
    local config_dir="$2"
    local app_config="$config_dir/whaticket_app.d/conf.yaml"
    
    sudo mkdir -p "$config_dir/whaticket_app.d"
    
    sudo tee "$app_config" > /dev/null <<EOF
# Whaticket application logs for $instance_name
logs:
  - type: file
    path: /home/deploy/$instance_name/backend/logs/*.log
    service: ${instance_name}-app
    source: whaticket
    tags:
      - instance:$instance_name
      - component:application
      - log_type:app
    
  # Logs do nosso sistema de logs unificado
  - type: file
    path: ${LOG_DIR:-./logs}/*.log
    service: ${instance_name}-installer
    source: whaticket-installer
    tags:
      - instance:$instance_name
      - component:installer
      - log_type:installation
EOF

    sudo chown dd-agent:dd-agent "$app_config"
    log_debug "Configuração aplicação criada: $app_config"
}

#######################################
# Configura métricas customizadas do Node.js
# Arguments:
#   $1 - Nome da instância
#######################################
datadog_configure_nodejs_apm() {
    local instance_name="$1"
    local backend_dir="/home/deploy/$instance_name/backend"
    
    log_info "Configurando APM Node.js para: $instance_name"
    
    # Verificar se backend existe
    if [[ ! -d "$backend_dir" ]]; then
        log_error "Diretório backend não encontrado: $backend_dir"
        return 1
    fi
    
    # Instalar dd-trace se não estiver instalado
    if ! grep -q "dd-trace" "$backend_dir/package.json"; then
        log_info "Instalando dd-trace no backend"
        
        sudo su - deploy <<EOF
cd "$backend_dir"
npm install dd-trace
EOF
    fi
    
    # Criar arquivo de configuração APM
    _datadog_create_nodejs_apm_config "$instance_name" "$backend_dir"
    
    log_info "✅ APM Node.js configurado"
    return 0
}

#######################################
# Cria configuração APM para Node.js
# Arguments:
#   $1 - Nome da instância
#   $2 - Diretório do backend
#######################################
_datadog_create_nodejs_apm_config() {
    local instance_name="$1"
    local backend_dir="$2"
    local apm_config="$backend_dir/datadog-apm.js"
    
    sudo su - deploy <<EOF
cat > "$apm_config" <<'APM_CONFIG'
// Datadog APM Configuration for Whaticket Backend
// This file should be imported BEFORE any other modules

const tracer = require('dd-trace').init({
  service: '${DATADOG_SERVICE_NAME:-whaticket}-$instance_name-backend',
  env: '${DATADOG_ENV:-production}',
  version: '${SENTRY_RELEASE:-1.0.0}',
  
  // Configurações de amostragem
  sampleRate: 0.1, // 10% das traces
  
  // Tags globais
  tags: {
    'instance': '$instance_name',
    'component': 'backend',
    'stack': 'nodejs'
  },
  
  // Configurações específicas
  runtimeMetrics: true,
  profiling: true,
  
  // Configurações de integração
  plugins: false, // Desabilitar auto-instrumentação para controle manual
});

// Instrumentação manual para Express
tracer.use('express', {
  // Filtrar rotas sensíveis
  blacklist: ['/health', '/metrics'],
  
  // Configurações de erro
  reportErrorTypes: true,
  
  // Headers para capturar
  headers: ['user-agent', 'x-forwarded-for'],
});

// Instrumentação para PostgreSQL
tracer.use('pg', {
  service: '${DATADOG_SERVICE_NAME:-whaticket}-$instance_name-postgres',
});

// Instrumentação para Redis
tracer.use('redis', {
  service: '${DATADOG_SERVICE_NAME:-whaticket}-$instance_name-redis',
});

// Métricas customizadas
const { metrics } = require('datadog-metrics');
metrics.init({
  host: '$instance_name',
  prefix: 'whaticket.',
  flushIntervalSeconds: 15,
  
  defaultTags: [
    'instance:$instance_name',
    'component:backend',
    'env:${DATADOG_ENV:-production}'
  ]
});

// Função para enviar métricas customizadas
const sendCustomMetric = (name, value, tags = []) => {
  metrics.gauge(name, value, [...tags, 'instance:$instance_name']);
};

// Função para incrementar contador
const incrementCounter = (name, tags = []) => {
  metrics.increment(name, 1, [...tags, 'instance:$instance_name']);
};

// Função para medir tempo de operação
const measureTime = (name, tags = []) => {
  const start = Date.now();
  return () => {
    const duration = Date.now() - start;
    metrics.histogram(name, duration, [...tags, 'instance:$instance_name']);
  };
};

// Capturar métricas de negócio (exemplo)
const trackBusinessMetrics = () => {
  // Exemplo: número de tickets criados
  // incrementCounter('tickets.created');
  
  // Exemplo: tempo de resposta médio
  // sendCustomMetric('response.time.avg', responseTime);
  
  // Exemplo: usuários ativos
  // sendCustomMetric('users.active', activeUsers);
};

module.exports = {
  tracer,
  metrics,
  sendCustomMetric,
  incrementCounter,
  measureTime,
  trackBusinessMetrics
};
APM_CONFIG
EOF

    log_debug "Configuração APM criada: $apm_config"
}

#######################################
# Inicia e habilita Datadog Agent
# Arguments:
#   None
#######################################
datadog_start_agent() {
    log_info "Iniciando Datadog Agent..."
    
    # Habilitar e iniciar serviço
    log_operation "Habilitando serviço" "sudo systemctl enable datadog-agent"
    log_operation "Iniciando serviço" "sudo systemctl start datadog-agent"
    
    # Aguardar inicialização
    sleep 5
    
    # Verificar status
    if sudo systemctl is-active datadog-agent >/dev/null; then
        log_info "✅ Datadog Agent iniciado com sucesso"
        
        # Verificar conectividade
        _datadog_test_connectivity
        
        return 0
    else
        log_error "❌ Falha ao iniciar Datadog Agent"
        
        # Mostrar logs para debug
        log_error "Logs do serviço:"
        sudo journalctl -u datadog-agent --no-pager --lines=10
        
        return 1
    fi
}

#######################################
# Testa conectividade do Datadog Agent
# Arguments:
#   None
#######################################
_datadog_test_connectivity() {
    log_info "Testando conectividade Datadog..."
    
    # Verificar status do agent
    if sudo datadog-agent status >/dev/null 2>&1; then
        log_info "✅ Agent status OK"
    else
        log_warn "⚠️ Agent status com problemas"
        return 1
    fi
    
    # Verificar conectividade com Datadog
    if sudo datadog-agent check connectivity >/dev/null 2>&1; then
        log_info "✅ Conectividade com Datadog OK"
    else
        log_warn "⚠️ Problemas de conectividade"
        return 1
    fi
    
    return 0
}

#######################################
# Função principal de configuração Datadog
# Arguments:
#   $1 - Nome da instância
#   $2 - API Key
#   $3 - Site (opcional)
#######################################
datadog_setup_instance() {
    local instance_name="$1"
    local api_key="$2"
    local datadog_site="${3:-us1.datadoghq.com}"
    
    log_info "Configurando Datadog para instância: $instance_name"
    
    # Instalar agent
    datadog_install_agent "$api_key" "$datadog_site" || return 1
    
    # Configurar agent básico
    datadog_configure_agent "$api_key" "$datadog_site" "$instance_name" || return 1
    
    # Configurar coleta de logs
    datadog_configure_logs "$instance_name" || return 1
    
    # Configurar APM Node.js
    datadog_configure_nodejs_apm "$instance_name" || return 1
    
    # Iniciar agent
    datadog_start_agent || return 1
    
    log_info "✅ Datadog configurado com sucesso para: $instance_name"
    log_info "Dashboard: https://app.$datadog_site/dashboard/lists"
    log_info "Logs: https://app.$datadog_site/logs"
    log_info "APM: https://app.$datadog_site/apm/traces"
    
    return 0
}

#######################################
# Remove configuração Datadog de uma instância
# Arguments:
#   $1 - Nome da instância
#######################################
datadog_remove_instance() {
    local instance_name="$1"
    
    log_info "Removendo configuração Datadog para: $instance_name"
    
    # Remover configurações específicas
    sudo rm -rf "$DATADOG_CONFIG_DIR/conf.d/*${instance_name}*" 2>/dev/null || true
    
    # Remover configuração APM
    sudo rm -f "/home/deploy/$instance_name/backend/datadog-apm.js" 2>/dev/null || true
    
    # Reiniciar agent para aplicar mudanças
    sudo systemctl restart datadog-agent
    
    log_info "Configuração Datadog removida para: $instance_name"
}

#######################################
# Status do Datadog Agent
# Arguments:
#   None
#######################################
datadog_status() {
    log_info "Status do Datadog Agent:"
    
    if sudo systemctl is-active datadog-agent >/dev/null; then
        log_info "✅ Datadog Agent - ATIVO"
        
        # Informações básicas do agent
        sudo datadog-agent version
        
        # Status detalhado (resumido)
        sudo datadog-agent status | head -20
    else
        log_warn "❌ Datadog Agent - INATIVO"
    fi
}

#######################################
# Configuração de dashboard personalizado
# Arguments:
#   $1 - Nome da instância
#######################################
datadog_create_dashboard() {
    local instance_name="$1"
    
    log_info "Para criar dashboard personalizado para $instance_name:"
    log_info "1. Acesse: https://app.${DATADOG_SITE:-us1.datadoghq.com}/dashboard/lists"
    log_info "2. Clique em 'New Dashboard'"
    log_info "3. Use estas queries para métricas importantes:"
    log_info ""
    log_info "📊 MÉTRICAS RECOMENDADAS:"
    log_info "   - CPU: avg:system.cpu.user{instance:$instance_name}"
    log_info "   - Memória: avg:system.mem.pct_usable{instance:$instance_name}"
    log_info "   - Disk: avg:system.disk.used{instance:$instance_name}"
    log_info "   - Network: avg:system.net.bytes_rcvd{instance:$instance_name}"
    log_info "   - PM2: avg:pm2.cpu{instance:$instance_name}"
    log_info "   - PostgreSQL: avg:postgresql.connections{instance:$instance_name}"
    log_info "   - Redis: avg:redis.connected_clients{instance:$instance_name}"
    log_info "   - Nginx: avg:nginx.requests{instance:$instance_name}"
    log_info ""
    log_info "🔍 LOGS IMPORTANTES:"
    log_info "   - Erros: service:${instance_name}-backend status:error"
    log_info "   - Performance: service:${instance_name}-backend @duration:>2000"
    log_info "   - Nginx: service:nginx @http.status_code:>=400"
}