#!/bin/bash

# Carregar Redis nativo primeiro (sobrescreve funções do _backend.sh)
source "${PROJECT_ROOT}"/lib/redis-native.sh

# Carregar integrações de monitoramento
source "${PROJECT_ROOT}"/lib/sentry-integration.sh
source "${PROJECT_ROOT}"/lib/datadog-integration.sh

source "${PROJECT_ROOT}"/lib/_backend.sh
source "${PROJECT_ROOT}"/lib/_frontend.sh
source "${PROJECT_ROOT}"/lib/_system.sh
source "${PROJECT_ROOT}"/lib/_inquiry.sh
