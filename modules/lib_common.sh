#!/bin/bash
# modules/lib_common.sh
# Общие константы, цвета и вспомогательные функции для всех модулей MTProxy.
# Подключается через: source "$(dirname "$0")/modules/lib_common.sh"
# Повторное подключение безопасно — guard предотвращает двойную загрузку.

[[ -n "${_LIB_COMMON_LOADED:-}" ]] && return 0
_LIB_COMMON_LOADED=1

################################################################################
# Константы
################################################################################

INSTALL_DIR="/opt/MTProxy"
SERVICE_NAME="mtproxy"
CONFIG_FILE="$INSTALL_DIR/.env"
MODULES_DIR="$INSTALL_DIR/modules"

MTPROXY_REPO="https://github.com/TelegramMessenger/MTProxy"
MTPROXY_BINARY="$INSTALL_DIR/objs/bin/mtproto-proxy"
MTPROXY_RUN_DIR="$INSTALL_DIR/run"

################################################################################
# Цвета
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

################################################################################
# Вывод
################################################################################

print_header() {
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error()   { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info()    { echo -e "${CYAN}ℹ $1${NC}"; }

################################################################################
# Ввод
################################################################################

# Читает Y/n или y/N ответ с валидацией. Повторяет запрос при некорректном вводе.
# Использование: read_yes_no "Вопрос?" [y|n]   (умолчание: y)
# Возвращает: 0=да, 1=нет
read_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local hint
    [ "$default" = "y" ] && hint="[Y/n]" || hint="[y/N]"
    while true; do
        read -p "$prompt $hint: " -n 1 -r
        echo
        case "$REPLY" in
            Y|y) return 0 ;;
            N|n) return 1 ;;
            "")  [ "$default" = "y" ] && return 0 || return 1 ;;
            *)   print_warning "Неверный ввод. Нажмите Y (да) или N (нет)" ;;
        esac
    done
}

################################################################################
# Сеть / Firewall
################################################################################

# Возвращает: 0=порт свободен, 1=порт занят
is_port_available() {
    local port="$1"
    if ss -tuln 2>/dev/null | grep -q ":${port} " || \
       netstat -tuln 2>/dev/null | grep -q ":${port} "; then
        return 1
    fi
    return 0
}

# Открывает порт в UFW (если UFW активен)
open_ufw_port() {
    local port="$1"
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow "${port}/tcp" >/dev/null 2>&1
        print_success "UFW: порт ${port}/tcp открыт"
    fi
}

# Закрывает порт в UFW (если UFW активен)
close_ufw_port() {
    local port="$1"
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw delete allow "${port}/tcp" >/dev/null 2>&1
        print_success "UFW: порт ${port}/tcp закрыт"
    fi
}

# Определяет внешний IPv4 адрес сервера
get_external_ip() {
    curl -4 -s --max-time 5 ifconfig.me 2>/dev/null \
        || curl -4 -s --max-time 5 icanhazip.com 2>/dev/null \
        || hostname -I | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1 \
        || echo ""
}

# Выводит список рекомендованных портов (свободные / занятые).
# После вызова $SUGGESTED_PORT содержит первый свободный из списка
# или пустую строку если все заняты.
_show_port_recommendations() {
    local candidates=(443 8443 2053 2083 2087 2096 9443)
    local free=() busy=()
    SUGGESTED_PORT=""
    for p in "${candidates[@]}"; do
        if is_port_available "$p"; then
            free+=("$p")
            [ -z "$SUGGESTED_PORT" ] && SUGGESTED_PORT="$p"
        else
            busy+=("$p")
        fi
    done
    if [ ${#free[@]} -gt 0 ]; then
        echo -e "  Свободные порты: ${GREEN}${free[*]}${NC}"
    fi
    if [ ${#busy[@]} -gt 0 ]; then
        echo -e "  Занятые порты:   ${RED}${busy[*]}${NC}"
    fi
}

################################################################################
# Проверки окружения
################################################################################

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Скрипт требует права root"
        echo "Запустите: sudo bash $0"
        exit 1
    fi
}

check_ubuntu() {
    if [ ! -f /etc/os-release ]; then
        print_error "Не удалось определить операционную систему"
        exit 1
    fi
    # shellcheck source=/dev/null
    . /etc/os-release
    if [ "$ID" != "ubuntu" ]; then
        print_error "Этот скрипт предназначен только для Ubuntu"
        exit 1
    fi
    print_success "Обнаружена Ubuntu $VERSION"
}

# Проверяет, что MTProxy установлен и systemd-сервис существует.
# При ошибке завершает скрипт с exit 1.
check_installation() {
    if [ ! -d "$INSTALL_DIR" ] || [ ! -f "$MTPROXY_BINARY" ]; then
        print_error "MTProxy не установлен"
        print_info "Выполните установку: sudo mtproxy install"
        exit 1
    fi
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Файл конфигурации не найден: $CONFIG_FILE"
        print_info "Переустановите: sudo mtproxy install"
        exit 1
    fi
    if ! systemctl list-unit-files 2>/dev/null | grep -q "^${SERVICE_NAME}.service"; then
        print_error "Systemd сервис не найден"
        print_info "Переустановите: sudo mtproxy install"
        exit 1
    fi
}

################################################################################
# Формирование команды запуска mtproto-proxy
################################################################################

# Строит полную команду ExecStart из текущей конфигурации ($CONFIG_FILE
# должен быть уже загружен через source).
# Результат записывается в переменную CMD.
# Использование:
#   source "$CONFIG_FILE"
#   build_cmd
#   echo "$CMD"
build_cmd() {
    CMD="$MTPROXY_BINARY"
    CMD="$CMD -u nobody"
    CMD="$CMD -p $STATS_PORT"
    CMD="$CMD -H $EXTERNAL_PORT"
    # -S принимает ровно 32 hex-символа (без dd/ee префикса)
    CMD="$CMD -S $SECRET"
    CMD="$CMD -M $WORKERS"

    if [ -n "$AD_TAG" ] && [ "$AD_TAG" != "пропустить" ]; then
        CMD="$CMD -P $AD_TAG"
    fi

    # NAT: формат <local-addr>:<global-addr>
    if [ "$USE_NAT" = "yes" ] && [ -n "$NAT_IP" ] && [ -n "$NAT_LOCAL_IP" ]; then
        CMD="$CMD --nat-info $NAT_LOCAL_IP:$NAT_IP"
    fi

    # fakeTLS-режим: -D задаёт внешний домен маскировки
    if [ "$USE_DOMAIN" = "yes" ] && [ -n "$TLS_DOMAIN" ]; then
        CMD="$CMD -D $TLS_DOMAIN"
    fi

    # ВАЖНО: --aes-pwd и конфиг должны быть В КОНЦЕ и именно в таком порядке
    CMD="$CMD --aes-pwd $MTPROXY_RUN_DIR/proxy-secret $MTPROXY_RUN_DIR/proxy-multi.conf"
}

# Обновляет строку ExecStart в systemd-сервисе и перезагружает daemon.
# Вызывать ПОСЛЕ build_cmd (переменная CMD должна быть заполнена).
apply_cmd_to_service() {
    sed -i "s|^ExecStart=.*|ExecStart=$CMD|" "/etc/systemd/system/$SERVICE_NAME.service"
    systemctl daemon-reload
    print_success "Systemd сервис обновлён"
}

# Вычисляет клиентский секрет (с ee/dd-префиксом) на основе конфигурации.
# Результат записывается в переменную CLIENT_SECRET.
# Требует: $SECRET, $USE_DOMAIN, $TLS_DOMAIN, $USE_DD_PREFIX — загружены из .env
#
# Форматы секрета:
#   plain:    <32 hex>
#   dd:       dd<32 hex>          — random padding
#   ee:       ee<32 hex><hex(домен)>  — fakeTLS; домен = TLS_DOMAIN (флаг -D),
#                               клиент использует его как SNI в TLS ClientHello
get_client_secret() {
    if [ "${USE_DOMAIN:-no}" = "yes" ] && [ -n "${TLS_DOMAIN:-}" ]; then
        local domain_hex
        domain_hex=$(printf '%s' "$TLS_DOMAIN" | xxd -ps | tr -d '\n')
        CLIENT_SECRET="ee${SECRET}${domain_hex}"
    elif [ "${USE_DD_PREFIX:-no}" = "yes" ]; then
        CLIENT_SECRET="dd${SECRET}"
    else
        CLIENT_SECRET="$SECRET"
    fi
}

# Вычисляет адрес сервера для клиентской ссылки.
# Результат записывается в переменную SERVER_ADDR.
get_server_addr() {
    if [ "${USE_DOMAIN:-no}" = "yes" ] && [ -n "${DOMAIN_NAME:-}" ]; then
        SERVER_ADDR="$DOMAIN_NAME"
    elif [ "${USE_NAT:-no}" = "yes" ] && [ -n "${NAT_IP:-}" ]; then
        SERVER_ADDR="$NAT_IP"
    else
        SERVER_ADDR=$(get_external_ip)
    fi
}
