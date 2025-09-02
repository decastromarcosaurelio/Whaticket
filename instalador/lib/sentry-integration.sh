#!/bin/bash
#
# Integração Sentry - Monitoramento de Erros
# Configura Sentry CLI e integração com o projeto Whaticket
# Autor: Laowang (error hunter extraordinaire)
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

# Configurações Sentry
readonly SENTRY_CLI_VERSION="2.21.2"
readonly SENTRY_CLI_URL="https://github.com/getsentry/sentry-cli/releases/download/${SENTRY_CLI_VERSION}/sentry-cli-Linux-x86_64"
readonly SENTRY_CLI_PATH="/usr/local/bin/sentry-cli"
readonly SENTRY_CONFIG_DIR="/etc/sentry"
readonly SENTRY_WHATICKET_ORG="${SENTRY_WHATICKET_ORG:-whaticket}"

#######################################
# Instala Sentry CLI
# Arguments:
#   None
#######################################
sentry_install_cli() {
    log_info "Instalando Sentry CLI versão $SENTRY_CLI_VERSION..."
    
    # Verificar se já está instalado
    if [[ -f "$SENTRY_CLI_PATH" ]] && $SENTRY_CLI_PATH --version | grep -q "$SENTRY_CLI_VERSION"; then
        log_info "Sentry CLI já está instalado na versão correta"
        return 0
    fi
    
    # Download do Sentry CLI
    log_operation "Download Sentry CLI" "
        sudo wget -O '$SENTRY_CLI_PATH' '$SENTRY_CLI_URL' &&
        sudo chmod +x '$SENTRY_CLI_PATH'
    "
    
    # Verificar instalação
    if ! $SENTRY_CLI_PATH --version >/dev/null 2>&1; then
        log_error "Falha na instalação do Sentry CLI"
        return 1
    fi
    
    log_info "✅ Sentry CLI instalado com sucesso"
    return 0
}

#######################################
# Configura autenticação Sentry
# Arguments:
#   $1 - Auth Token do Sentry
#######################################
sentry_configure_auth() {
    local auth_token="$1"
    
    if [[ -z "$auth_token" ]]; then
        log_error "Auth token do Sentry é obrigatório"
        log_info "Obtenha seu token em: https://sentry.io/settings/account/api/auth-tokens/"
        return 1
    fi
    
    log_info "Configurando autenticação Sentry..."
    
    # Criar diretório de configuração
    sudo mkdir -p "$SENTRY_CONFIG_DIR"
    
    # Criar arquivo de configuração
    sudo tee "$SENTRY_CONFIG_DIR/config" > /dev/null <<EOF
[defaults]
url=https://sentry.io/
org=$SENTRY_WHATICKET_ORG

[auth]
token=$auth_token
EOF
    
    # Definir permissões seguras
    sudo chmod 600 "$SENTRY_CONFIG_DIR/config"
    sudo chown root:root "$SENTRY_CONFIG_DIR/config"
    
    # Testar autenticação
    if ! sudo SENTRY_CONFIG_FILE="$SENTRY_CONFIG_DIR/config" $SENTRY_CLI_PATH info >/dev/null 2>&1; then
        log_error "Falha na autenticação com Sentry"
        log_error "Verifique se o token está correto e tem as permissões necessárias"
        return 1
    fi
    
    log_info "✅ Autenticação Sentry configurada"
    return 0
}

#######################################
# Cria projeto Sentry para instância
# Arguments:
#   $1 - Nome da instância
#   $2 - Nome do projeto (opcional)
#######################################
sentry_create_project() {
    local instance_name="$1"
    local project_name="${2:-$instance_name}"
    
    log_info "Criando projeto Sentry: $project_name"
    
    # Verificar se projeto já existe
    if sudo SENTRY_CONFIG_FILE="$SENTRY_CONFIG_DIR/config" $SENTRY_CLI_PATH projects list | grep -q "$project_name"; then
        log_info "Projeto Sentry já existe: $project_name"
        return 0
    fi
    
    # Criar projeto
    local create_result
    create_result=$(sudo SENTRY_CONFIG_FILE="$SENTRY_CONFIG_DIR/config" $SENTRY_CLI_PATH projects create \
        --org "$SENTRY_WHATICKET_ORG" \
        --team "whaticket" \
        --platform "node" \
        "$project_name" 2>&1)
    
    if [[ $? -eq 0 ]]; then
        log_info "✅ Projeto Sentry criado: $project_name"
        return 0
    else
        log_error "Falha ao criar projeto Sentry: $create_result"
        return 1
    fi
}

#######################################
# Configura Sentry no backend da instância
# Arguments:
#   $1 - Nome da instância
#   $2 - DSN do Sentry
#######################################
sentry_configure_backend() {
    local instance_name="$1"
    local sentry_dsn="$2"
    
    log_info "Configurando Sentry no backend: $instance_name"
    
    local backend_dir="/home/deploy/$instance_name/backend"
    local env_file="$backend_dir/.env"
    
    if [[ ! -f "$env_file" ]]; then
        log_error "Arquivo .env do backend não encontrado: $env_file"
        return 1
    fi
    
    # Adicionar configurações Sentry ao .env
    log_info "Adicionando configurações Sentry ao .env do backend"
    
    sudo su - deploy <<EOF
# Adicionar configurações Sentry
cat >> "$env_file" <<SENTRY_EOF

# Sentry Configuration
SENTRY_DSN=$sentry_dsn
SENTRY_ENVIRONMENT=${SENTRY_ENVIRONMENT:-production}
SENTRY_RELEASE=${SENTRY_RELEASE:-1.0.0}
SENTRY_TRACES_SAMPLE_RATE=${SENTRY_TRACES_SAMPLE_RATE:-0.1}
SENTRY_ENABLED=true
SENTRY_EOF
EOF
    
    # Verificar se o backend tem o pacote @sentry/node instalado
    local backend_package_json="$backend_dir/package.json"
    if [[ -f "$backend_package_json" ]] && ! grep -q "@sentry/node" "$backend_package_json"; then
        log_info "Instalando pacote @sentry/node no backend"
        
        sudo su - deploy <<EOF
cd "$backend_dir"
npm install @sentry/node @sentry/profiling-node
EOF
    fi
    
    # Criar arquivo de configuração Sentry para o backend
    _sentry_create_backend_config "$instance_name" "$backend_dir"
    
    log_info "✅ Sentry configurado no backend"
    return 0
}

#######################################
# Configura Sentry no frontend da instância
# Arguments:
#   $1 - Nome da instância
#   $2 - DSN do Sentry
#######################################
sentry_configure_frontend() {
    local instance_name="$1"
    local sentry_dsn="$2"
    
    log_info "Configurando Sentry no frontend: $instance_name"
    
    local frontend_dir="/home/deploy/$instance_name/frontend"
    local env_file="$frontend_dir/.env"
    
    if [[ ! -f "$env_file" ]]; then
        log_error "Arquivo .env do frontend não encontrado: $env_file"
        return 1
    fi
    
    # Adicionar configurações Sentry ao .env do frontend
    log_info "Adicionando configurações Sentry ao .env do frontend"
    
    sudo su - deploy <<EOF
# Adicionar configurações Sentry
cat >> "$env_file" <<SENTRY_EOF

# Sentry Configuration
REACT_APP_SENTRY_DSN=$sentry_dsn
REACT_APP_SENTRY_ENVIRONMENT=${SENTRY_ENVIRONMENT:-production}
REACT_APP_SENTRY_RELEASE=${SENTRY_RELEASE:-1.0.0}
REACT_APP_SENTRY_TRACES_SAMPLE_RATE=${SENTRY_TRACES_SAMPLE_RATE:-0.1}
SENTRY_EOF
EOF
    
    # Verificar se o frontend tem os pacotes Sentry instalados
    local frontend_package_json="$frontend_dir/package.json"
    if [[ -f "$frontend_package_json" ]] && ! grep -q "@sentry/react" "$frontend_package_json"; then
        log_info "Instalando pacotes Sentry no frontend"
        
        sudo su - deploy <<EOF
cd "$frontend_dir"
npm install @sentry/react @sentry/tracing
EOF
    fi
    
    # Criar arquivo de configuração Sentry para o frontend
    _sentry_create_frontend_config "$instance_name" "$frontend_dir"
    
    log_info "✅ Sentry configurado no frontend"
    return 0
}

#######################################
# Cria configuração Sentry para o backend
# Arguments:
#   $1 - Nome da instância
#   $2 - Diretório do backend
#######################################
_sentry_create_backend_config() {
    local instance_name="$1"
    local backend_dir="$2"
    local config_file="$backend_dir/src/config/sentry.js"
    
    # Criar diretório config se não existir
    sudo su - deploy -c "mkdir -p $(dirname "$config_file")"
    
    # Criar arquivo de configuração
    sudo su - deploy <<EOF
cat > "$config_file" <<'SENTRY_CONFIG'
const Sentry = require("@sentry/node");
const { ProfilingIntegration } = require("@sentry/profiling-node");

// Configuração do Sentry
const configureSentry = () => {
  if (!process.env.SENTRY_ENABLED || process.env.SENTRY_ENABLED !== "true") {
    console.log("Sentry está desabilitado");
    return;
  }

  if (!process.env.SENTRY_DSN) {
    console.log("SENTRY_DSN não configurado - Sentry desabilitado");
    return;
  }

  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    environment: process.env.SENTRY_ENVIRONMENT || "production",
    release: process.env.SENTRY_RELEASE || "1.0.0",
    
    // Performance Monitoring
    tracesSampleRate: parseFloat(process.env.SENTRY_TRACES_SAMPLE_RATE) || 0.1,
    
    // Profiling
    profilesSampleRate: 0.1,
    integrations: [
      new ProfilingIntegration(),
    ],
    
    // Configurações específicas do Node.js
    beforeSend(event) {
      // Filtrar eventos sensíveis
      if (event.exception) {
        const error = event.exception.values[0];
        if (error && error.value && error.value.includes("password")) {
          return null; // Não enviar erros que contenham senhas
        }
      }
      return event;
    },
    
    // Tags padrão
    initialScope: {
      tags: {
        component: "backend",
        instance: "$instance_name",
        service: "whaticket"
      }
    }
  });

  console.log("Sentry inicializado com sucesso");
};

// Middleware para Express
const sentryRequestHandler = () => {
  return Sentry.Handlers.requestHandler();
};

const sentryErrorHandler = () => {
  return Sentry.Handlers.errorHandler();
};

// Capturar exceções não tratadas
const setupGlobalHandlers = () => {
  process.on('uncaughtException', (error) => {
    console.error('Uncaught Exception:', error);
    Sentry.captureException(error);
  });

  process.on('unhandledRejection', (reason, promise) => {
    console.error('Unhandled Rejection at:', promise, 'reason:', reason);
    Sentry.captureException(reason);
  });
};

module.exports = {
  configureSentry,
  sentryRequestHandler,
  sentryErrorHandler,
  setupGlobalHandlers,
  Sentry
};
SENTRY_CONFIG
EOF

    log_debug "Configuração Sentry criada: $config_file"
}

#######################################
# Cria configuração Sentry para o frontend
# Arguments:
#   $1 - Nome da instância
#   $2 - Diretório do frontend
#######################################
_sentry_create_frontend_config() {
    local instance_name="$1"
    local frontend_dir="$2"
    local config_file="$frontend_dir/src/config/sentry.js"
    
    # Criar diretório config se não existir
    sudo su - deploy -c "mkdir -p $(dirname "$config_file")"
    
    # Criar arquivo de configuração
    sudo su - deploy <<EOF
cat > "$config_file" <<'SENTRY_CONFIG'
import * as Sentry from "@sentry/react";
import { BrowserTracing } from "@sentry/tracing";

// Configuração do Sentry para React
export const configureSentry = () => {
  if (!process.env.REACT_APP_SENTRY_DSN) {
    console.log("REACT_APP_SENTRY_DSN não configurado - Sentry desabilitado");
    return;
  }

  Sentry.init({
    dsn: process.env.REACT_APP_SENTRY_DSN,
    environment: process.env.REACT_APP_SENTRY_ENVIRONMENT || "production",
    release: process.env.REACT_APP_SENTRY_RELEASE || "1.0.0",
    
    // Performance Monitoring
    tracesSampleRate: parseFloat(process.env.REACT_APP_SENTRY_TRACES_SAMPLE_RATE) || 0.1,
    
    integrations: [
      new BrowserTracing({
        // Configurações de roteamento específicas para React Router
        routingInstrumentation: Sentry.reactRouterV6Instrumentation(
          React.useEffect,
          useLocation,
          useNavigationType,
          createRoutesFromChildren,
          matchRoutes
        ),
      }),
    ],
    
    // Configurações específicas do React
    beforeSend(event) {
      // Filtrar eventos em desenvolvimento
      if (process.env.NODE_ENV === "development") {
        console.log("Sentry event:", event);
      }
      
      // Filtrar informações sensíveis
      if (event.request && event.request.headers) {
        delete event.request.headers.Authorization;
        delete event.request.headers.Cookie;
      }
      
      return event;
    },
    
    // Tags padrão
    initialScope: {
      tags: {
        component: "frontend",
        instance: "$instance_name",
        service: "whaticket"
      }
    }
  });

  console.log("Sentry inicializado com sucesso no frontend");
};

// Hook para capturar erros de componentes React
export const withSentry = (Component) => {
  return Sentry.withErrorBoundary(Component, {
    fallback: ({ error, resetError }) => (
      <div style={{ padding: "20px", textAlign: "center" }}>
        <h2>Algo deu errado</h2>
        <p>Um erro inesperado ocorreu. Nossa equipe foi notificada.</p>
        <button onClick={resetError}>Tentar novamente</button>
        {process.env.NODE_ENV === "development" && (
          <pre style={{ marginTop: "20px", textAlign: "left" }}>
            {error.toString()}
          </pre>
        )}
      </div>
    ),
    showDialog: false,
  });
};

// Capturar erros manualmente
export const captureError = (error, context = {}) => {
  Sentry.captureException(error, {
    tags: context.tags,
    extra: context.extra,
  });
};

// Adicionar breadcrumb personalizado
export const addBreadcrumb = (message, category = "custom") => {
  Sentry.addBreadcrumb({
    message,
    category,
    level: "info",
    timestamp: new Date().getTime(),
  });
};

export default Sentry;
SENTRY_CONFIG
EOF

    log_debug "Configuração Sentry criada: $config_file"
}

#######################################
# Cria release Sentry e faz upload de sourcemaps
# Arguments:
#   $1 - Nome da instância
#   $2 - Versão da release
#######################################
sentry_create_release() {
    local instance_name="$1"
    local release_version="${2:-${SENTRY_RELEASE:-1.0.0}}"
    local project_name="$instance_name"
    
    log_info "Criando release Sentry: $release_version"
    
    # Criar release
    if ! sudo SENTRY_CONFIG_FILE="$SENTRY_CONFIG_DIR/config" $SENTRY_CLI_PATH releases new \
        --org "$SENTRY_WHATICKET_ORG" \
        --project "$project_name" \
        "$release_version"; then
        log_error "Falha ao criar release Sentry"
        return 1
    fi
    
    # Upload de sourcemaps do frontend se existirem
    local frontend_build_dir="/home/deploy/$instance_name/frontend/build"
    if [[ -d "$frontend_build_dir" ]]; then
        log_info "Fazendo upload de sourcemaps do frontend"
        
        sudo SENTRY_CONFIG_FILE="$SENTRY_CONFIG_DIR/config" $SENTRY_CLI_PATH releases files \
            --org "$SENTRY_WHATICKET_ORG" \
            --project "$project_name" \
            "$release_version" upload-sourcemaps \
            "$frontend_build_dir" \
            --url-prefix "~/static/js" \
            --validate || log_warn "Falha no upload de sourcemaps"
    fi
    
    # Finalizar release
    sudo SENTRY_CONFIG_FILE="$SENTRY_CONFIG_DIR/config" $SENTRY_CLI_PATH releases finalize \
        --org "$SENTRY_WHATICKET_ORG" \
        --project "$project_name" \
        "$release_version"
    
    log_info "✅ Release Sentry criada: $release_version"
    return 0
}

#######################################
# Configura alertas básicos no Sentry
# Arguments:
#   $1 - Nome da instância
#######################################
sentry_configure_alerts() {
    local instance_name="$1"
    
    log_info "Configurando alertas Sentry para: $instance_name"
    
    # Esta função criaria alertas via API do Sentry
    # Por simplicidade, apenas documentamos os alertas recomendados
    
    log_info "Alertas recomendados para configurar manualmente no Sentry:"
    log_info "1. Erros com taxa > 1% em 1 minuto"
    log_info "2. Novos issues críticos"
    log_info "3. Performance degradada (P95 > 2s)"
    log_info "4. Volume de erros > 100 em 5 minutos"
    log_info ""
    log_info "Configure em: https://sentry.io/organizations/$SENTRY_WHATICKET_ORG/alerts/rules/"
}

#######################################
# Função principal de configuração Sentry
# Arguments:
#   $1 - Nome da instância
#   $2 - Auth Token
#   $3 - DSN (opcional, será obtido automaticamente se não fornecido)
#######################################
sentry_setup_instance() {
    local instance_name="$1"
    local auth_token="$2"
    local sentry_dsn="$3"
    
    log_info "Configurando Sentry para instância: $instance_name"
    
    # Instalar CLI se necessário
    sentry_install_cli || return 1
    
    # Configurar autenticação
    sentry_configure_auth "$auth_token" || return 1
    
    # Criar projeto se necessário
    sentry_create_project "$instance_name" || return 1
    
    # Se DSN não foi fornecido, tentar obter
    if [[ -z "$sentry_dsn" ]]; then
        sentry_dsn=$(sudo SENTRY_CONFIG_FILE="$SENTRY_CONFIG_DIR/config" $SENTRY_CLI_PATH projects info \
            --org "$SENTRY_WHATICKET_ORG" \
            "$instance_name" --json | grep '"dsn"' | cut -d'"' -f4)
        
        if [[ -z "$sentry_dsn" ]]; then
            log_error "Não foi possível obter DSN do projeto"
            return 1
        fi
    fi
    
    # Configurar backend e frontend
    sentry_configure_backend "$instance_name" "$sentry_dsn" || return 1
    sentry_configure_frontend "$instance_name" "$sentry_dsn" || return 1
    
    # Criar release inicial
    sentry_create_release "$instance_name" || return 1
    
    # Configurar alertas
    sentry_configure_alerts "$instance_name"
    
    log_info "✅ Sentry configurado com sucesso para: $instance_name"
    log_info "DSN: $sentry_dsn"
    
    return 0
}

#######################################
# Remove configuração Sentry de uma instância
# Arguments:
#   $1 - Nome da instância
#######################################
sentry_remove_instance() {
    local instance_name="$1"
    
    log_info "Removendo configuração Sentry para: $instance_name"
    
    # Remover configurações do backend
    local backend_config="/home/deploy/$instance_name/backend/src/config/sentry.js"
    [[ -f "$backend_config" ]] && sudo rm -f "$backend_config"
    
    # Remover configurações do frontend
    local frontend_config="/home/deploy/$instance_name/frontend/src/config/sentry.js"
    [[ -f "$frontend_config" ]] && sudo rm -f "$frontend_config"
    
    # Remover variáveis do .env (seria mais complexo, por agora apenas avisar)
    log_warn "Remova manualmente as variáveis SENTRY_* dos arquivos .env"
    
    log_info "Configuração Sentry removida para: $instance_name"
}

#######################################
# Testa configuração Sentry
# Arguments:
#   $1 - Nome da instância
#######################################
sentry_test_configuration() {
    local instance_name="$1"
    
    log_info "Testando configuração Sentry para: $instance_name"
    
    # Verificar se CLI está funcionando
    if ! sudo SENTRY_CONFIG_FILE="$SENTRY_CONFIG_DIR/config" $SENTRY_CLI_PATH info >/dev/null 2>&1; then
        log_error "Sentry CLI não está configurado corretamente"
        return 1
    fi
    
    # Verificar se projeto existe
    if ! sudo SENTRY_CONFIG_FILE="$SENTRY_CONFIG_DIR/config" $SENTRY_CLI_PATH projects list | grep -q "$instance_name"; then
        log_error "Projeto Sentry não encontrado: $instance_name"
        return 1
    fi
    
    # Verificar arquivos de configuração
    local backend_config="/home/deploy/$instance_name/backend/src/config/sentry.js"
    local frontend_config="/home/deploy/$instance_name/frontend/src/config/sentry.js"
    
    if [[ ! -f "$backend_config" ]]; then
        log_error "Configuração Sentry do backend não encontrada"
        return 1
    fi
    
    if [[ ! -f "$frontend_config" ]]; then
        log_error "Configuração Sentry do frontend não encontrada"
        return 1
    fi
    
    log_info "✅ Configuração Sentry está OK para: $instance_name"
    return 0
}