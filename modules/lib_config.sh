#!/bin/bash
# modules/lib_config.sh
# Интерактивная настройка MTProxy и вывод информации о подключении.
# Зависимости: lib_common.sh, lib_sni.sh

[[ -n "${_LIB_CONFIG_LOADED:-}" ]] && return 0
_LIB_CONFIG_LOADED=1

# shellcheck source=modules/lib_common.sh
[[ -z "${_LIB_COMMON_LOADED:-}" ]] && source "$(dirname "${BASH_SOURCE[0]}")/lib_common.sh"
# shellcheck source=modules/lib_sni.sh
[[ -z "${_LIB_SNI_LOADED:-}" ]]    && source "$(dirname "${BASH_SOURCE[0]}")/lib_sni.sh"

################################################################################
# Информация о подключении
################################################################################

# Отображает текущие данные подключения и ссылку tg://proxy.
# Требует: $CONFIG_FILE существует и загружен (или загружается внутри).
show_connection_info() {
    print_header "Информация для подключения"

    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Файл конфигурации не найден: $CONFIG_FILE"
        return 1
    fi

    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    get_server_addr    # → $SERVER_ADDR  (lib_common)
    get_client_secret  # → $CLIENT_SECRET (lib_common)

    local proxy_link="tg://proxy?server=$SERVER_ADDR&port=$EXTERNAL_PORT&secret=$CLIENT_SECRET"

    echo
    echo "═══════════════════════════════════════════════════════════"
    echo -e "${CYAN}📋 КОНФИГУРАЦИЯ:${NC}"
    echo "   Сервер:     $SERVER_ADDR"
    echo "   Порт:       $EXTERNAL_PORT"
    echo "   Секрет:     $CLIENT_SECRET"
    echo "   Воркеры:    $WORKERS"
    if [ -n "${AD_TAG:-}" ] && [ "$AD_TAG" != "пропустить" ]; then
        echo "   AD Tag:     $AD_TAG"
    fi
    if [ "${USE_DOMAIN:-no}" = "yes" ] && [ -n "${TLS_DOMAIN:-}" ]; then
        echo "   SNI домен:  $TLS_DOMAIN"
    fi
    echo
    echo -e "${CYAN}🔗 ССЫЛКА ДЛЯ ПОДКЛЮЧЕНИЯ:${NC}"
    echo "═══════════════════════════════════════════════════════════"
    echo "$proxy_link"
    echo "═══════════════════════════════════════════════════════════"
    echo

    if [ -f "$INSTALL_DIR/proxy_link.txt" ]; then
        print_info "Ссылка сохранена: $INSTALL_DIR/proxy_link.txt"
    fi
}

################################################################################
# Интерактивная настройка
################################################################################

interactive_configuration() {
    print_header "Интерактивная настройка"

    # Загружаем существующую конфигурацию если есть
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        print_info "Загружена существующая конфигурация"
    fi

    # ── 1. Секрет ──────────────────────────────────────────────────────────────
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}1. СЕКРЕТ ПОЛЬЗОВАТЕЛЯ${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local existing_secret=""
    if [ -f "$MTPROXY_RUN_DIR/secret.txt" ]; then
        existing_secret=$(cat "$MTPROXY_RUN_DIR/secret.txt")
        echo -e "Текущий секрет: ${GREEN}$existing_secret${NC}"
    fi

    if read_yes_no "Сгенерировать новый секрет?" "y"; then
        SECRET=$(head -c 16 /dev/urandom | xxd -ps)
        print_success "Новый секрет: $SECRET"
    else
        SECRET="${existing_secret:-$(head -c 16 /dev/urandom | xxd -ps)}"
        print_info "Используется секрет: $SECRET"
    fi
    echo "$SECRET" > "$MTPROXY_RUN_DIR/secret.txt"

    # ── 2. Порты ───────────────────────────────────────────────────────────────
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}2. НАСТРОЙКА ПОРТОВ${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo -e "  ${YELLOW}► Порт для подключения клиентов${NC}"
    echo    "  Рекомендуется: 443 (стандартный HTTPS, меньше блокировок)"
    echo

    local default_ext="${EXTERNAL_PORT:-443}"
    while true; do
        read -p "Порт MTProxy [$default_ext]: " input
        EXTERNAL_PORT="${input:-$default_ext}"
        if is_port_available "$EXTERNAL_PORT"; then
            break
        else
            print_warning "Порт $EXTERNAL_PORT уже занят. Введите другой."
        fi
    done

    echo
    echo "Порт статистики (доступен только через 127.0.0.1)"
    read -p "Порт статистики [${STATS_PORT:-8888}]: " input
    STATS_PORT="${input:-${STATS_PORT:-8888}}"

    # ── 3. Воркеры ─────────────────────────────────────────────────────────────
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}3. ПРОИЗВОДИТЕЛЬНОСТЬ${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    local cpu_cores; cpu_cores=$(nproc)
    echo "Доступно CPU ядер: $cpu_cores"
    read -p "Количество воркеров [${WORKERS:-1}]: " input
    WORKERS="${input:-${WORKERS:-1}}"

    # ── 4. AD Tag ──────────────────────────────────────────────────────────────
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}4. AD TAG (ОПЦИОНАЛЬНО)${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "AD Tag получают у @MTProxybot для монетизации"
    read -p "AD Tag [${AD_TAG:-пропустить}]: " input
    AD_TAG="${input:-${AD_TAG:-}}"

    # ── 5. NAT ─────────────────────────────────────────────────────────────────
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}5. СЕТЕВЫЕ НАСТРОЙКИ${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    local detected_ip; detected_ip=$(get_external_ip)
    [ -n "$detected_ip" ] && print_info "Обнаружен внешний IP: $detected_ip"

    if read_yes_no "Использовать NAT?" "n"; then
        USE_NAT="yes"
        local detected_local
        detected_local=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' \
                         || hostname -I | awk '{print $1}')
        read -p "Локальный IP [${NAT_LOCAL_IP:-$detected_local}]: " input
        NAT_LOCAL_IP="${input:-${NAT_LOCAL_IP:-$detected_local}}"
        read -p "Внешний IP   [${NAT_IP:-$detected_ip}]: " input
        NAT_IP="${input:-${NAT_IP:-$detected_ip}}"
    else
        USE_NAT="no"
        NAT_LOCAL_IP=""
        NAT_IP=""
    fi

    # ── 6. Домен и TLS/fakeTLS ─────────────────────────────────────────────────
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}6. ДОМЕН И TLS-МАСКИРОВКА (fakeTLS)${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo    "  Без домена: клиенты подключаются по IP, секрет plain/dd"
    echo    "  С доменом:  fakeTLS-маскировка (секрет ee), лучше обходит блокировки"
    echo

    if read_yes_no "Использовать доменное имя и fakeTLS?" "n"; then
        USE_DOMAIN="yes"

        # Сканируем nginx/caddy/remnanode один раз
        detect_sni_domains

        # Выбор DOMAIN_NAME (адрес сервера в клиентской ссылке)
        echo
        echo -e "  ${YELLOW}► Доменное имя для клиентской ссылки (куда подключаются):${NC}"
        select_domain_name "${DOMAIN_NAME:-}"
        # DOMAIN_NAME установлен функцией

        # Проверяем DNS
        if host "$DOMAIN_NAME" >/dev/null 2>&1; then
            local d_ip; d_ip=$(host "$DOMAIN_NAME" 2>/dev/null \
                               | grep "has address" | awk '{print $4}' | head -1)
            print_success "DNS: $DOMAIN_NAME → $d_ip"
        else
            print_warning "Не удалось разрешить $DOMAIN_NAME"
        fi

        # Выбор TLS_DOMAIN (домен маскировки для флага -D)
        # Предлагаем DOMAIN_NAME первым — он уже на этом сервере с TLS
        echo
        echo -e "  ${YELLOW}► Домен маскировки TLS:${NC}"
        select_tls_domain "${TLS_DOMAIN:-}" "$DOMAIN_NAME"
        # TLS_DOMAIN установлен функцией

        USE_DD_PREFIX="no"
        DISPLAY_SECRET="ee$SECRET"
        print_success "fakeTLS включён. Секрет клиента: ee$SECRET"
        print_info   "Домен подключения: $DOMAIN_NAME  |  Маскировка: $TLS_DOMAIN"

    else
        USE_DOMAIN="no"
        DOMAIN_NAME=""
        TLS_DOMAIN=""
        echo

        if read_yes_no "Включить Random Padding (защита от DPI)?" "y"; then
            USE_DD_PREFIX="yes"
            DISPLAY_SECRET="dd$SECRET"
            print_success "Random Padding включён. Секрет: dd$SECRET"
        else
            USE_DD_PREFIX="no"
            DISPLAY_SECRET="$SECRET"
        fi
    fi

    _config_save
    print_success "Конфигурация сохранена: $CONFIG_FILE"
}

################################################################################
# Сохранение .env
################################################################################

_config_save() {
    cat > "$CONFIG_FILE" << EOF
# MTProxy Configuration
# Generated: $(date)

# User Secret
SECRET=$SECRET
USE_DD_PREFIX=${USE_DD_PREFIX:-no}
DISPLAY_SECRET=${DISPLAY_SECRET:-$SECRET}

# Ports
EXTERNAL_PORT=$EXTERNAL_PORT
STATS_PORT=$STATS_PORT

# Performance
WORKERS=$WORKERS

# Optional
AD_TAG=${AD_TAG:-}

# Network
USE_NAT=${USE_NAT:-no}
NAT_LOCAL_IP=${NAT_LOCAL_IP:-}
NAT_IP=${NAT_IP:-}
USE_DOMAIN=${USE_DOMAIN:-no}
DOMAIN_NAME=${DOMAIN_NAME:-}
TLS_DOMAIN=${TLS_DOMAIN:-}
EOF
}
