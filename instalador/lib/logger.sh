#!/bin/bash
#
# Sistema de Logs Avançado para Whaticket Installer
# Autor: Laowang (grumpy but precise)
# 

# Cores para output do terminal (namespace LOG_ para evitar conflitos)
readonly LOG_RED='\033[0;31m'
readonly LOG_GREEN='\033[0;32m'
readonly LOG_YELLOW='\033[1;33m'
readonly LOG_BLUE='\033[0;34m'
readonly LOG_PURPLE='\033[0;35m'
readonly LOG_CYAN='\033[0;36m'
readonly LOG_WHITE='\033[1;37m'
readonly LOG_GRAY='\033[0;37m'
readonly LOG_NC='\033[0m' # No Color

# Configurações de log padrão
LOG_DIR="${LOG_DIR:-./logs}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_MAX_SIZE="${LOG_MAX_SIZE:-100}"
LOG_MAX_FILES="${LOG_MAX_FILES:-10}"
COMPONENT_NAME="installer"

# Arquivos de log
MAIN_LOG_FILE="${LOG_DIR}/install.log"
ERROR_LOG_FILE="${LOG_DIR}/error.log"
DEBUG_LOG_FILE="${LOG_DIR}/debug.log"
MONITORING_LOG_FILE="${LOG_DIR}/monitoring.log"

# Níveis de log com valores numéricos
declare -A LOG_LEVELS=(
    ["DEBUG"]=0
    ["INFO"]=1
    ["WARN"]=2
    ["ERROR"]=3
    ["FATAL"]=4
)

#######################################
# Inicializa o sistema de logs
# Arguments:
#   $1 - Nome do componente (opcional)
#######################################
log_init() {
    local component="${1:-installer}"
    COMPONENT_NAME="$component"
    
    # Criar diretório de logs se não existir
    mkdir -p "$LOG_DIR"
    
    # Inicializar arquivos de log com headers
    if [[ ! -f "$MAIN_LOG_FILE" ]]; then
        echo "# Whaticket Installer - Log Principal" > "$MAIN_LOG_FILE"
        echo "# Iniciado em: $(date '+%Y-%m-%d %H:%M:%S')" >> "$MAIN_LOG_FILE"
        echo "# =========================================" >> "$MAIN_LOG_FILE"
    fi
    
    # Rotacionar logs se necessário
    _rotate_logs
    
    log_info "Sistema de logs inicializado - Componente: $COMPONENT_NAME"
}

#######################################
# Log nivel DEBUG - apenas para desenvolvimento
# Arguments:
#   $* - Mensagem
#######################################
log_debug() {
    _log "DEBUG" "$*"
}

#######################################
# Log nivel INFO - informações gerais
# Arguments:
#   $* - Mensagem
#######################################
log_info() {
    _log "INFO" "$*"
}

#######################################
# Log nivel WARN - avisos importantes
# Arguments:
#   $* - Mensagem
#######################################
log_warn() {
    _log "WARN" "$*"
}

#######################################
# Log nivel ERROR - erros não fatais
# Arguments:
#   $* - Mensagem
#######################################
log_error() {
    _log "ERROR" "$*"
}

#######################################
# Log nivel FATAL - erros que param execução
# Arguments:
#   $* - Mensagem
#######################################
log_fatal() {
    _log "FATAL" "$*"
    exit 1
}

#######################################
# Log uma operação com início e fim
# Arguments:
#   $1 - Nome da operação
#   $2 - Comando a executar
#######################################
log_operation() {
    local operation_name="$1"
    local command="$2"
    local start_time
    local end_time
    local duration
    local exit_code
    
    start_time=$(date +%s)
    log_info "INICIANDO: $operation_name"
    
    # Executar comando e capturar saída
    if [[ -n "$command" ]]; then
        eval "$command" 2>&1 | while IFS= read -r line; do
            log_debug "$operation_name: $line"
        done
        exit_code=${PIPESTATUS[0]}
    else
        exit_code=0
    fi
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    if [[ $exit_code -eq 0 ]]; then
        log_info "CONCLUÍDO: $operation_name (${duration}s)"
    else
        log_error "FALHADO: $operation_name (${duration}s) - Exit Code: $exit_code"
    fi
    
    # Log para monitoring
    echo "$(date '+%Y-%m-%d %H:%M:%S') OPERATION $operation_name DURATION ${duration}s EXIT_CODE $exit_code" >> "$MONITORING_LOG_FILE"
    
    return $exit_code
}

#######################################
# Log com progresso visual
# Arguments:
#   $1 - Porcentagem (0-100)
#   $2 - Mensagem
#######################################
log_progress() {
    local percent=$1
    local message="$2"
    local bar_length=50
    local filled_length=$((percent * bar_length / 100))
    local bar=""
    
    # Construir barra de progresso
    for ((i=0; i<filled_length; i++)); do
        bar+="█"
    done
    for ((i=filled_length; i<bar_length; i++)); do
        bar+="░"
    done
    
    printf "\r${LOG_CYAN}[%s] %3d%% %s${LOG_NC}" "$bar" "$percent" "$message"
    
    if [[ $percent -eq 100 ]]; then
        echo # Nova linha quando completar
        log_info "Progresso completado: $message"
    fi
}

#######################################
# Log de métricas do sistema
# Arguments:
#   None
#######################################
log_system_metrics() {
    local cpu_usage
    local memory_usage
    local disk_usage
    local timestamp
    
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # CPU usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
    
    # Memory usage
    memory_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    
    # Disk usage of current directory
    disk_usage=$(df . | tail -1 | awk '{print $5}' | sed 's/%//')
    
    # Log para monitoring
    echo "$timestamp METRICS CPU=${cpu_usage}% MEM=${memory_usage}% DISK=${disk_usage}%" >> "$MONITORING_LOG_FILE"
    
    log_debug "Métricas - CPU: ${cpu_usage}% | MEM: ${memory_usage}% | DISK: ${disk_usage}%"
}

#######################################
# Função interna para fazer o log real
# Arguments:
#   $1 - Nível do log
#   $* - Mensagem
#######################################
_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    local color
    local log_file
    
    # Verificar se deve logar este nível
    if [[ ${LOG_LEVELS[$level]} -lt ${LOG_LEVELS[$LOG_LEVEL]} ]]; then
        return 0
    fi
    
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Definir cor baseada no nível
    case $level in
        "DEBUG") color="$LOG_GRAY" ;;
        "INFO")  color="$LOG_GREEN" ;;
        "WARN")  color="$LOG_YELLOW" ;;
        "ERROR") color="$LOG_RED" ;;
        "FATAL") color="$LOG_PURPLE" ;;
        *)       color="$LOG_WHITE" ;;
    esac
    
    # Definir arquivo de destino
    case $level in
        "ERROR"|"FATAL") log_file="$ERROR_LOG_FILE" ;;
        "DEBUG")         log_file="$DEBUG_LOG_FILE" ;;
        *)               log_file="$MAIN_LOG_FILE" ;;
    esac
    
    # Formato: TIMESTAMP [LEVEL] COMPONENT: MESSAGE
    local log_entry="$timestamp [$level] $COMPONENT_NAME: $message"
    
    # Escrever no arquivo
    echo "$log_entry" >> "$log_file"
    
    # Também escrever no log principal se não for o arquivo principal
    if [[ "$log_file" != "$MAIN_LOG_FILE" ]]; then
        echo "$log_entry" >> "$MAIN_LOG_FILE"
    fi
    
    # Output no terminal com cor
    echo -e "${color}[$level]${LOG_NC} $COMPONENT_NAME: $message"
}

#######################################
# Rotaciona logs quando ficam muito grandes
# Arguments:
#   None
#######################################
_rotate_logs() {
    local files=("$MAIN_LOG_FILE" "$ERROR_LOG_FILE" "$DEBUG_LOG_FILE" "$MONITORING_LOG_FILE")
    
    for log_file in "${files[@]}"; do
        if [[ -f "$log_file" ]]; then
            local size_mb
            size_mb=$(du -m "$log_file" | cut -f1)
            
            if [[ $size_mb -gt $LOG_MAX_SIZE ]]; then
                # Mover logs antigos
                for ((i=LOG_MAX_FILES-1; i>0; i--)); do
                    if [[ -f "${log_file}.$i" ]]; then
                        mv "${log_file}.$i" "${log_file}.$((i+1))"
                    fi
                done
                
                # Mover log atual para .1
                mv "$log_file" "${log_file}.1"
                
                # Remover logs muito antigos
                if [[ -f "${log_file}.$((LOG_MAX_FILES+1))" ]]; then
                    rm "${log_file}.$((LOG_MAX_FILES+1))"
                fi
                
                echo "# Log rotacionado em: $(date '+%Y-%m-%d %H:%M:%S')" > "$log_file"
            fi
        fi
    done
}

#######################################
# Wrapper para executar comandos com log automático
# Arguments:
#   $* - Comando a executar
#######################################
log_exec() {
    local command="$*"
    local exit_code
    
    log_debug "Executando: $command"
    
    # Executar e capturar tanto stdout quanto stderr
    {
        eval "$command" 2>&1
        exit_code=$?
    } | while IFS= read -r line; do
        log_debug "OUTPUT: $line"
    done
    
    exit_code=${PIPESTATUS[0]}
    
    if [[ $exit_code -eq 0 ]]; then
        log_debug "Comando executado com sucesso: $command"
    else
        log_error "Comando falhado (exit $exit_code): $command"
    fi
    
    return $exit_code
}

#######################################
# Cria um checkpoint no log
# Arguments:
#   $1 - Nome do checkpoint
#######################################
log_checkpoint() {
    local checkpoint_name="$1"
    local separator="=========================================="
    
    echo "" >> "$MAIN_LOG_FILE"
    echo "$separator" >> "$MAIN_LOG_FILE"
    echo "CHECKPOINT: $checkpoint_name" >> "$MAIN_LOG_FILE"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')" >> "$MAIN_LOG_FILE"
    echo "$separator" >> "$MAIN_LOG_FILE"
    echo "" >> "$MAIN_LOG_FILE"
    
    log_info "Checkpoint: $checkpoint_name"
}

#######################################
# Finaliza o sistema de logs
# Arguments:
#   None
#######################################
log_finalize() {
    local end_time
    end_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    log_checkpoint "INSTALAÇÃO FINALIZADA"
    log_info "Logs disponíveis em: $LOG_DIR"
    log_info "Sistema de logs finalizado em: $end_time"
    
    # Resumo final
    if [[ -f "$ERROR_LOG_FILE" ]] && [[ -s "$ERROR_LOG_FILE" ]]; then
        local error_count
        error_count=$(grep -c "ERROR\|FATAL" "$ERROR_LOG_FILE" 2>/dev/null || echo "0")
        if [[ $error_count -gt 0 ]]; then
            log_warn "Total de erros encontrados: $error_count (veja $ERROR_LOG_FILE)"
        fi
    fi
}