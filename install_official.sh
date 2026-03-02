#!/bin/bash

################################################################################
# MTProxy Official - Автоматическая установка
# Официальная реализация от Telegram на C
# Система: Ubuntu 20.04+
# Использование: sudo bash install_official.sh
################################################################################

set -e

# Константы
MTPROXY_REPO="https://github.com/TelegramMessenger/MTProxy"
INSTALL_DIR="/opt/MTProxy"
SERVICE_NAME="mtproxy"
REMNANODE_DIR="/opt/remnanode"
# Директория расположения install_official.sh (для поиска смежных скриптов)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

################################################################################
# Вспомогательные функции
################################################################################

print_header() {
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

# Проверяет, доступен ли порт (не занят другим процессом)
# Возвращает: 0=доступен, 1=занят
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

# Читает Y/n или y/N ответ с валидацией. Повторяет запрос при некорректном вводе
# (в том числе при русской раскладке)
# Использование: read_yes_no "Вопрос?" [y|n]  (умолчание: y)
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

# Проверка прав root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Скрипт требует права root"
        echo "Запустите: sudo bash $0"
        exit 1
    fi
}

# Проверка Ubuntu
check_ubuntu() {
    if [ ! -f /etc/os-release ]; then
        print_error "Не удалось определить операционную систему"
        exit 1
    fi
    
    . /etc/os-release
    
    if [ "$ID" != "ubuntu" ]; then
        print_error "Этот скрипт предназначен только для Ubuntu"
        exit 1
    fi
    
    print_success "Обнаружена Ubuntu $VERSION"
}

################################################################################
# Установка зависимостей
################################################################################

install_dependencies() {
    print_header "Проверка зависимостей"

    # Проверяем критичные команды/инструменты
    print_info "Проверка необходимых инструментов..."

    local ALL_OK=true
    local MISSING_PACKAGES=""

    # Проверяем наличие критичных команд
    if ! command -v git &> /dev/null; then
        print_warning "git не найден"
        MISSING_PACKAGES="$MISSING_PACKAGES git"
        ALL_OK=false
    else
        print_success "git установлен"
    fi

    if ! command -v curl &> /dev/null; then
        print_warning "curl не найден"
        MISSING_PACKAGES="$MISSING_PACKAGES curl"
        ALL_OK=false
    else
        print_success "curl установлен"
    fi

    if ! command -v make &> /dev/null; then
        print_warning "make не найден"
        MISSING_PACKAGES="$MISSING_PACKAGES build-essential"
        ALL_OK=false
    else
        print_success "make установлен"
    fi

    if ! command -v gcc &> /dev/null; then
        print_warning "gcc не найден"
        MISSING_PACKAGES="$MISSING_PACKAGES build-essential"
        ALL_OK=false
    else
        print_success "gcc установлен"
    fi

    # Проверяем dev библиотеки (по наличию header файлов)
    if [ ! -f "/usr/include/openssl/ssl.h" ]; then
        print_warning "OpenSSL dev headers не найдены"
        MISSING_PACKAGES="$MISSING_PACKAGES libssl-dev"
        ALL_OK=false
    else
        print_success "libssl-dev установлен"
    fi

    if [ ! -f "/usr/include/zlib.h" ]; then
        print_warning "zlib dev headers не найдены"
        MISSING_PACKAGES="$MISSING_PACKAGES zlib1g-dev"
        ALL_OK=false
    else
        print_success "zlib1g-dev установлен"
    fi

    if ! command -v xxd &> /dev/null; then
        print_warning "xxd не найден"
        MISSING_PACKAGES="$MISSING_PACKAGES xxd"
        ALL_OK=false
    else
        print_success "xxd установлен"
    fi

    # Если что-то отсутствует, пытаемся установить
    if [ "$ALL_OK" = false ]; then
        echo
        print_warning "Обнаружены отсутствующие зависимости"
        print_info "Попытка установки: $MISSING_PACKAGES"
        echo

        # Обновляем список пакетов
        apt-get update -qq 2>/dev/null || true

        # Пытаемся установить отсутствующие пакеты
        for package in $MISSING_PACKAGES; do
            print_info "Установка $package..."
            if apt-get install -y "$package" 2>&1 | grep -q "E: "; then
                print_error "Не удалось установить $package"
                print_info "Попробуйте установить вручную: sudo apt-get install $package"
                exit 1
            else
                print_success "$package установлен"
            fi
        done
    fi

    # Финальная проверка критичных инструментов
    echo
    print_info "Финальная проверка критичных инструментов..."

    if ! command -v git &> /dev/null; then
        print_error "Git не установлен. Установка невозможна."
        echo "Выполните вручную: sudo apt-get install git"
        exit 1
    fi

    if ! command -v make &> /dev/null || ! command -v gcc &> /dev/null; then
        print_error "Компилятор (gcc/make) не установлен. Установка невозможна."
        echo "Выполните вручную: sudo apt-get install build-essential"
        exit 1
    fi

    if ! command -v curl &> /dev/null; then
        print_error "curl не установлен. Установка невозможна."
        echo "Выполните вручную: sudo apt-get install curl"
        exit 1
    fi

    print_success "Все необходимые инструменты доступны!"
}

################################################################################
# Клонирование и сборка MTProxy
################################################################################

clone_and_build_mtproxy() {
    print_header "Клонирование и сборка MTProxy"
    
    # Удаляем старую версию если существует
    if [ -d "$INSTALL_DIR" ]; then
        print_warning "Обнаружена существующая установка в $INSTALL_DIR"
        
        # Останавливаем сервис если запущен
        if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            print_info "Остановка существующего сервиса..."
            systemctl stop "$SERVICE_NAME"
        fi
        
        # Создаем backup конфигурации
        if [ -f "$INSTALL_DIR/.env" ]; then
            BACKUP_FILE="$INSTALL_DIR/.env.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$INSTALL_DIR/.env" "$BACKUP_FILE"
            print_success "Конфигурация сохранена: $BACKUP_FILE"
        fi
        
        print_info "Удаление старой установки..."
        rm -rf "$INSTALL_DIR"
    fi
    
    # Клонируем репозиторий
    print_info "Клонирование официального репозитория Telegram..."
    git clone "$MTPROXY_REPO" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    print_success "Репозиторий клонирован"
    
    # Компилируем
    print_info "Компиляция MTProxy (может занять несколько минут)..."
    make -j$(nproc)
    
    if [ ! -f "objs/bin/mtproto-proxy" ]; then
        print_error "Ошибка компиляции: бинарный файл не создан"
        exit 1
    fi
    
    print_success "MTProxy успешно скомпилирован"
    
    # Создаем рабочую директорию
    mkdir -p "$INSTALL_DIR/run"
    cd "$INSTALL_DIR/run"
}

################################################################################
# Получение конфигурации Telegram
################################################################################

download_telegram_configs() {
    print_header "Получение конфигурации Telegram"
    
    cd "$INSTALL_DIR/run"
    
    # Получаем секрет для подключения к серверам Telegram
    print_info "Загрузка proxy-secret..."
    curl -s https://core.telegram.org/getProxySecret -o proxy-secret
    
    if [ ! -f "proxy-secret" ] || [ ! -s "proxy-secret" ]; then
        print_error "Не удалось загрузить proxy-secret"
        exit 1
    fi
    print_success "proxy-secret получен"
    
    # Получаем конфигурацию серверов Telegram
    print_info "Загрузка proxy-multi.conf..."
    curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf
    
    if [ ! -f "proxy-multi.conf" ] || [ ! -s "proxy-multi.conf" ]; then
        print_error "Не удалось загрузить proxy-multi.conf"
        exit 1
    fi
    print_success "proxy-multi.conf получен"
    
    print_info "Эти файлы рекомендуется обновлять раз в день"
}

################################################################################
# Генерация секрета
################################################################################

generate_secret() {
    print_header "Генерация секрета для пользователей"
    
    # Генерируем секрет
    SECRET=$(head -c 16 /dev/urandom | xxd -ps)
    
    print_success "Секрет сгенерирован: $SECRET"
    echo
    
    print_info "Для включения Random Padding (защита от DPI):"
    print_info "Добавьте префикс 'dd' к секрету: dd$SECRET"
    
    echo "$SECRET" > "$INSTALL_DIR/run/secret.txt"
}

################################################################################
# Интерактивная настройка
################################################################################

interactive_configuration() {
    print_header "Интерактивная настройка"
    
    # Загружаем старую конфигурацию если есть
    if [ -f "$INSTALL_DIR/.env" ]; then
        source "$INSTALL_DIR/.env"
        print_info "Загружена существующая конфигурация"
    fi

    # Выбор режима работы
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}РЕЖИМ РАБОТЫ${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo -e "  ${GREEN}1) Через Nginx / Remnawave СНИ (рекомендуется)${NC}"
    echo    "     Internet:443 → Nginx → relay → MTProxy:backend"
    echo    "     ✓ Порт 443 общий с XRay Reality, панелью и др."
    echo    "     ✓ TLS/fakeTLS маскировка (флаг -D domain)"
    echo    "     ✓ Требует: домен + Remnawave + setup_remnawave_integration.sh"
    echo
    echo -e "  ${YELLOW}2) Прямое подключение (без Nginx)${NC}"
    echo    "     Internet:PORT → MTProxy напрямую"
    echo    "     ✓ Проще в настройке, не зависит от Remnawave"
    echo    "     ✓ Домен опционален (для TLS маскировки)"
    echo
    if [ "${NGINX_MODE:-yes}" = "yes" ]; then
        DEFAULT_MODE_HINT="1"
    else
        DEFAULT_MODE_HINT="2"
    fi
    while true; do
        read -p "Выберите режим [1/2, по умолчанию $DEFAULT_MODE_HINT]: " -n 1 -r
        echo
        _m="${REPLY:-$DEFAULT_MODE_HINT}"
        case "$_m" in
            1) NGINX_MODE="yes"; print_info "Режим: через Nginx (Remnawave SNI)"; break ;;
            2) NGINX_MODE="no";  print_info "Режим: прямое подключение"; break ;;
            *) print_warning "Неверный ввод. Нажмите 1 или 2" ;;
        esac
    done

    # Секрет пользователя
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}1. СЕКРЕТ ПОЛЬЗОВАТЕЛЯ${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ -f "$INSTALL_DIR/run/secret.txt" ]; then
        EXISTING_SECRET=$(cat "$INSTALL_DIR/run/secret.txt")
        echo -e "Текущий секрет: ${GREEN}$EXISTING_SECRET${NC}"
    fi
    
    if read_yes_no "Сгенерировать новый секрет?" "y"; then
        SECRET=$(head -c 16 /dev/urandom | xxd -ps)
        echo "$SECRET" > "$INSTALL_DIR/run/secret.txt"
        print_success "Новый секрет: $SECRET"
    else
        SECRET=${EXISTING_SECRET:-$(head -c 16 /dev/urandom | xxd -ps)}
        echo "$SECRET" > "$INSTALL_DIR/run/secret.txt"
    fi
    
    # Random Padding
    echo
    if [ "$NGINX_MODE" = "yes" ]; then
        # В fakeTLS-режиме (-D domain) клиентский секрет получает префикс 'ee'.
        # Префикс 'dd' (Random Padding) несовместим с 'ee': сервер с -D ожидает
        # TLS-хэндшейк, а dd-клиент шлёт MTProto+padding → соединение не установится.
        # FakeTLS уже обеспечивает маскировку сильнее, чем Random Padding.
        USE_DD_PREFIX="no"
        DISPLAY_SECRET="$SECRET"
        print_info "Random Padding отключён (несовместим с fakeTLS/Nginx-режимом)"
        print_info "Защита от DPI обеспечивается через TLS-маскировку (-D domain)"
    else
        if read_yes_no "Включить Random Padding (защита от DPI)?" "y"; then
            USE_DD_PREFIX="yes"
            DISPLAY_SECRET="dd$SECRET"
            print_success "Random Padding включён"
            print_info "Секрет с префиксом: dd$SECRET"
        else
            USE_DD_PREFIX="no"
            DISPLAY_SECRET="$SECRET"
        fi
    fi
    
    # Порты
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}2. НАСТРОЙКА ПОРТОВ${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    if [ "$NGINX_MODE" = "yes" ]; then
        echo -e "  ${GREEN}► Через Nginx: укажите BACKEND-порт MTProxy (не 443!)${NC}"
        echo    "  схема: Internet:443 → Nginx:443 → relay:RELAY → MTProxy:BACKEND"
        echo    "  Порт 443 занят Nginx. Клиентская ссылка всегда будет использовать порт 443."
        echo -e "  ${YELLOW}Рекомендуется: 10443 или любой свободный порт${NC}"
        DEFAULT_EXT_PORT="${EXTERNAL_PORT:-10443}"
    else
        echo -e "  ${YELLOW}► Прямое подключение: порт, на который подключаются клиенты${NC}"
        echo    "  схема: Internet:PORT → MTProxy:PORT напрямую"
        echo    "  Порт должен быть открыт в firewall: sudo ufw allow PORT/tcp"
        echo -e "  ${YELLOW}Рекомендуется: 443 (стандартный HTTPS, меньше блокировок)${NC}"
        DEFAULT_EXT_PORT="${EXTERNAL_PORT:-443}"
    fi
    echo
    while true; do
        read -p "Порт MTProxy [${DEFAULT_EXT_PORT}]: " input
        EXTERNAL_PORT=${input:-${DEFAULT_EXT_PORT}}
        if is_port_available "$EXTERNAL_PORT"; then
            break
        else
            print_warning "Порт $EXTERNAL_PORT уже занят. Введите другой порт."
        fi
    done

    echo
    echo "Порт статистики (локальный): доступен только через 127.0.0.1"
    read -p "Порт статистики [${STATS_PORT:-8888}]: " input
    STATS_PORT=${input:-${STATS_PORT:-8888}}
    
    # Количество воркеров
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}3. ПРОИЗВОДИТЕЛЬНОСТЬ${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    CPU_CORES=$(nproc)
    echo "Количество воркеров влияет на производительность"
    echo "Доступно CPU ядер: $CPU_CORES"
    read -p "Количество воркеров [${WORKERS:-1}]: " input
    WORKERS=${input:-${WORKERS:-1}}
    
    # AD Tag
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}4. AD TAG (ОПЦИОНАЛЬНО)${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "AD Tag можно получить у @MTProxybot для монетизации"
    read -p "AD Tag [${AD_TAG:-пропустить}]: " input
    AD_TAG=${input:-${AD_TAG}}
    
    # NAT и домен
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}5. СЕТЕВЫЕ НАСТРОЙКИ${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    # Определяем внешний IP
    DETECTED_IP=$(curl -4 -s ifconfig.me 2>/dev/null || curl -4 -s icanhazip.com 2>/dev/null || hostname -I | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || echo "")
    if [ -n "$DETECTED_IP" ]; then
        print_info "Обнаружен внешний IP: $DETECTED_IP"
    fi
    
    if read_yes_no "Использовать NAT?" "n"; then
        USE_NAT="yes"
        DETECTED_LOCAL_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || hostname -I | awk '{print $1}')
        read -p "Локальный (внутренний) IP [${NAT_LOCAL_IP:-$DETECTED_LOCAL_IP}]: " input
        NAT_LOCAL_IP=${input:-${NAT_LOCAL_IP:-$DETECTED_LOCAL_IP}}
        read -p "Внешний (глобальный) IP адрес [${NAT_IP:-$DETECTED_IP}]: " input
        NAT_IP=${input:-${NAT_IP:-$DETECTED_IP}}
    else
        USE_NAT="no"
    fi
    
    # Домен (для TLS)
    echo
    if [ "$NGINX_MODE" = "yes" ]; then
        echo -e "  ${GREEN}► Через Nginx: домен ОБЯЗАТЕЛЕН${NC}"
        echo    "  Nginx роутит трафик по SNI на основе этого домена."
        echo    "  Используйте OTДЕЛЬНЫЙ домен (не тот что у Remnawave/XRay)."
        echo -e "  ${YELLOW}Домен должен указывать A-записью на этот сервер.${NC}"
        echo -e "  ${YELLOW}Пример: proxy.example.com, mt.example.com${NC}"
        echo
        read -p "Домен MTProxy (сервисный, для подключения клиентов): " DOMAIN_NAME
        if [ -n "$DOMAIN_NAME" ]; then
            USE_DOMAIN="yes"
            if host "$DOMAIN_NAME" > /dev/null 2>&1; then
                DOMAIN_IP=$(host "$DOMAIN_NAME" | grep "has address" | awk '{print $4}' | head -n1)
                print_success "Домен $DOMAIN_NAME указывает на $DOMAIN_IP"
            else
                print_warning "Не удалось разрешить домен $DOMAIN_NAME"
                print_info "Убедитесь что A-запись добавлена перед запуском"
            fi
        else
            print_warning "Домен не указан! Nginx SNI не будет работать без домена."
            USE_DOMAIN="no"
        fi
        echo
        echo -e "  ${CYAN}► Домен маскировки (для флага -D):${NC}"
        echo    "  MTProxy подключается к этому домену чтобы получить реальный TLS fingerprint."
        echo    "  Должен быть ВНЕШНИЙ сайт с HTTPS — НЕ этот сервер."
        echo -e "  ${YELLOW}Примеры: www.google.com, www.cloudflare.com, telegram.org${NC}"
        echo
        read -p "Домен маскировки [www.google.com]: " TLS_DOMAIN
        TLS_DOMAIN=${TLS_DOMAIN:-www.google.com}
        print_success "Домен маскировки: $TLS_DOMAIN"
    else
        echo -e "  ${YELLOW}► Прямое подключение: домен опционален${NC}"
        echo    "  Без домена: подключение по IP-адресу:"
        echo -e "  ${CYAN}  tg://proxy?server=${DETECTED_IP:-IP}&port=$EXTERNAL_PORT&secret=<hex>${NC}"
        echo    "  С доменом: TLS/fakeTLS маскировка, лучше обходит блокировки:"
        echo -e "  ${CYAN}  tg://proxy?server=domain&port=$EXTERNAL_PORT&secret=ee<hex>${NC}"
        echo
        if read_yes_no "Использовать доменное имя?" "n"; then
            USE_DOMAIN="yes"
            read -p "Доменное имя: " DOMAIN_NAME
            if host "$DOMAIN_NAME" > /dev/null 2>&1; then
                DOMAIN_IP=$(host "$DOMAIN_NAME" | grep "has address" | awk '{print $4}' | head -n1)
                print_success "Домен $DOMAIN_NAME указывает на $DOMAIN_IP"
            else
                print_warning "Не удалось разрешить домен $DOMAIN_NAME"
            fi
            # В прямом режиме домен маскировки = сервисный домен
            TLS_DOMAIN="$DOMAIN_NAME"
        else
            USE_DOMAIN="no"
        fi
    fi
    
    # Сохраняем конфигурацию
    cat > "$INSTALL_DIR/.env" << EOF
# MTProxy Configuration
# Generated: $(date)

# Mode
NGINX_MODE=$NGINX_MODE

# User Secret
SECRET=$SECRET
USE_DD_PREFIX=$USE_DD_PREFIX
DISPLAY_SECRET=$DISPLAY_SECRET

# Ports
EXTERNAL_PORT=$EXTERNAL_PORT
STATS_PORT=$STATS_PORT

# Performance
WORKERS=$WORKERS

# Optional
AD_TAG=${AD_TAG}

# Network
USE_NAT=$USE_NAT
NAT_LOCAL_IP=${NAT_LOCAL_IP}
NAT_IP=${NAT_IP}
USE_DOMAIN=$USE_DOMAIN
DOMAIN_NAME=${DOMAIN_NAME}
TLS_DOMAIN=${TLS_DOMAIN}
EOF
    
    print_success "Конфигурация сохранена в $INSTALL_DIR/.env"
}

################################################################################
# Создание systemd service
################################################################################

create_systemd_service() {
    print_header "Создание systemd сервиса"

    # Загружаем конфигурацию
    source "$INSTALL_DIR/.env"

    # Формируем команду запуска (ПРАВИЛЬНЫЙ ПОРЯДОК АРГУМЕНТОВ!)
    CMD="/opt/MTProxy/objs/bin/mtproto-proxy"
    CMD="$CMD -u nobody"
    CMD="$CMD -p $STATS_PORT"
    CMD="$CMD -H $EXTERNAL_PORT"
    CMD="$CMD -S $SECRET"
    CMD="$CMD -M $WORKERS"

    # В режиме Nginx/relay: MTProxy должен слушать только на 127.0.0.1.
    # Relay (Nginx stream) подключается с 127.0.0.1; прямой доступ из интернета должен быть исключён.
    if [ "$NGINX_MODE" = "yes" ]; then
        CMD="$CMD --address 127.0.0.1"
    fi

    # Добавляем AD Tag если указан
    if [ -n "$AD_TAG" ] && [ "$AD_TAG" != "пропустить" ]; then
        CMD="$CMD -P $AD_TAG"
    fi

    # NAT: формат <local-addr>:<global-addr> (требуется C-кодом mtproto-proxy)
    if [ "$USE_NAT" = "yes" ] && [ -n "$NAT_IP" ] && [ -n "$NAT_LOCAL_IP" ]; then
        CMD="$CMD --nat-info $NAT_LOCAL_IP:$NAT_IP"
    fi

    # TLS-режим (fakeTLS): -D задаёт домен маскировки (чей TLS fingerprint имитировать).
    # TLS_DOMAIN — внешний сайт (напр. www.google.com), НЕ сервисный домен.
    # Это предотвращает циклическое подключение MTProxy к самому себе через Nginx.
    if [ "$USE_DOMAIN" = "yes" ] && [ -n "${TLS_DOMAIN:-$DOMAIN_NAME}" ]; then
        CMD="$CMD -D ${TLS_DOMAIN:-$DOMAIN_NAME}"
    fi

    # ВАЖНО: --aes-pwd и конфиг должны быть В КОНЦЕ и именно в таком порядке!
    CMD="$CMD --aes-pwd /opt/MTProxy/run/proxy-secret /opt/MTProxy/run/proxy-multi.conf"

    # MTProxy (C) имеет жёсткое ограничение в исходном коде:
    # common/pid.c: assert(!(p & 0xffff0000)) — PID процесса должен быть < 65536.
    # На модерных Linux серверах PID может превысить 65535, что приводит к крашу.
    # Решение: установить kernel.pid_max=65535.
    print_info "Применение воркараунда PID: kernel.pid_max=65535..."
    sysctl -w kernel.pid_max=65535
    echo "kernel.pid_max = 65535" > /etc/sysctl.d/99-mtproxy-pid.conf
    print_success "kernel.pid_max=65535 установлен (воркараунд MTProxy C-сервера)"

    # Создаем service файл
    cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=MTProxy - Official Telegram MTProto Proxy
After=network.target
Documentation=https://github.com/TelegramMessenger/MTProxy

[Service]
Type=simple
WorkingDirectory=/opt/MTProxy/run
# MTProxy C-код требует PID < 65536 (assert в common/pid.c)
ExecStartPre=/sbin/sysctl -w kernel.pid_max=65535
ExecStartPre=/bin/bash -c 'curl -s https://core.telegram.org/getProxySecret -o /opt/MTProxy/run/proxy-secret'
ExecStartPre=/bin/bash -c 'curl -s https://core.telegram.org/getProxyConfig -o /opt/MTProxy/run/proxy-multi.conf'
ExecStart=$CMD
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/MTProxy/run

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "Systemd сервис создан"

    # Перезагружаем systemd
    systemctl daemon-reload
    print_success "Systemd перезагружен"

    # Открываем порт в UFW (только для прямого подключения)
    if [ "$NGINX_MODE" = "no" ]; then
        if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
            ufw allow "${EXTERNAL_PORT}/tcp" >/dev/null 2>&1
            print_success "UFW: порт $EXTERNAL_PORT/tcp открыт"
        else
            print_info "UFW не активен. Откройте порт вручную: sudo ufw allow $EXTERNAL_PORT/tcp"
        fi
    fi
}

################################################################################
# Настройка автообновления конфигурации
################################################################################

setup_config_updater() {
    print_header "Настройка автообновления конфигурации Telegram"
    
    # Создаем скрипт обновления
    cat > "/opt/MTProxy/update-configs.sh" << 'EOF'
#!/bin/bash
# Автоматическое обновление конфигурации Telegram

cd /opt/MTProxy/run

# Обновляем конфигурацию
curl -s https://core.telegram.org/getProxySecret -o proxy-secret.new
curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf.new

# Проверяем что файлы скачались
if [ -s proxy-secret.new ] && [ -s proxy-multi.conf.new ]; then
    mv proxy-secret.new proxy-secret
    mv proxy-multi.conf.new proxy-multi.conf
    
    # Перезапускаем сервис
    systemctl restart mtproxy
    
    logger "MTProxy configs updated successfully"
else
    logger "MTProxy configs update failed"
    rm -f proxy-secret.new proxy-multi.conf.new
fi
EOF
    
    chmod +x "/opt/MTProxy/update-configs.sh"
    print_success "Скрипт обновления создан"
    
    # Создаем cron задачу (обновление раз в день в 3:00)
    CRON_CMD="0 3 * * * /opt/MTProxy/update-configs.sh >/dev/null 2>&1"
    
    # Проверяем существует ли уже задача
    if crontab -l 2>/dev/null | grep -q "update-configs.sh"; then
        print_info "Cron задача уже существует"
    else
        (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
        print_success "Cron задача добавлена (обновление в 3:00 каждый день)"
    fi
}

################################################################################
# Настройка скриптов управления
################################################################################

setup_management_scripts() {
    print_header "Настройка скриптов управления"

    # Скрипты управления должны лежать рядом с install_official.sh.
    # После клонирования репозитория Telegram в /opt/MTProxy копируем их туда,
    # чтобы они были доступны вместе с бинарником и конфигурацией.
    for script in manage_mtproxy_official.sh setup_remnawave_integration.sh; do
        if [ -f "$SCRIPT_DIR/$script" ]; then
            cp "$SCRIPT_DIR/$script" "$INSTALL_DIR/$script"
            chmod +x "$INSTALL_DIR/$script"
            print_success "Скрипт установлен: $INSTALL_DIR/$script"
        else
            print_warning "Скрипт не найден: $SCRIPT_DIR/$script"
            print_info "Ожидался рядом с install_official.sh"
        fi
    done

    # Создаём симлинки /usr/local/bin/mtproxy и /usr/local/bin/MTProxy
    # Позволяет запускать управление командами: mtproxy  и  MTProxy
    if [ -f "$INSTALL_DIR/manage_mtproxy_official.sh" ]; then
        ln -sf "$INSTALL_DIR/manage_mtproxy_official.sh" /usr/local/bin/mtproxy
        ln -sf "$INSTALL_DIR/manage_mtproxy_official.sh" /usr/local/bin/MTProxy
        print_success "Симлинки созданы: mtproxy  и  MTProxy → $INSTALL_DIR/manage_mtproxy_official.sh"
        print_info "Управление MTProxy доступно командами: mtproxy  или  MTProxy"
    fi
}

################################################################################
# Интеграция с Remnawave
################################################################################

integrate_with_remnawave() {
    # В режиме прямого подключения Nginx/Remnawave не используются
    if [ "$NGINX_MODE" = "no" ]; then
        return
    fi

    print_header "Интеграция с Remnawave (опционально)"
    
    if [ ! -d "$REMNANODE_DIR" ]; then
        print_warning "Remnawave не обнаружена в $REMNANODE_DIR"
        print_info "Пропускаем интеграцию"
        return
    fi
    
    print_success "Remnawave обнаружена"
    echo
    
    if ! read_yes_no "Настроить интеграцию с Remnawave (Nginx SNI)?" "n"; then
        print_info "Интеграция пропущена"
        return
    fi
    
    # Запускаем отдельный скрипт интеграции
    # Приоритет: /opt/MTProxy/ (куда setup_management_scripts скопировал скрипт)
    if [ -f "$INSTALL_DIR/setup_remnawave_integration.sh" ]; then
        bash "$INSTALL_DIR/setup_remnawave_integration.sh"
    elif [ -f "$SCRIPT_DIR/setup_remnawave_integration.sh" ]; then
        bash "$SCRIPT_DIR/setup_remnawave_integration.sh"
    else
        print_warning "Скрипт интеграции не найден"
        print_info "Скопируйте setup_remnawave_integration.sh в $INSTALL_DIR/ и повторите"
    fi
}

################################################################################
# Запуск и проверка
################################################################################

start_and_verify() {
    print_header "Запуск MTProxy"
    
    # Включаем автозапуск
    systemctl enable "$SERVICE_NAME"
    print_success "Автозапуск включен"
    
    # Запускаем сервис
    systemctl start "$SERVICE_NAME"
    
    # Ждем немного
    sleep 3
    
    # Проверяем статус
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "MTProxy успешно запущен!"
    else
        print_error "Ошибка запуска MTProxy"
        echo
        print_info "Просмотр логов: journalctl -u $SERVICE_NAME -n 50"
        systemctl status "$SERVICE_NAME" --no-pager
        exit 1
    fi
    
    # Проверяем порт
    source "$INSTALL_DIR/.env"
    
    echo
    print_info "Проверка портов..."
    
    if netstat -tuln | grep -q ":$EXTERNAL_PORT "; then
        print_success "Порт $EXTERNAL_PORT открыт"
    else
        print_warning "Порт $EXTERNAL_PORT не прослушивается"
    fi
    
    if netstat -tuln | grep -q "127.0.0.1:$STATS_PORT "; then
        print_success "Порт статистики $STATS_PORT доступен"
    fi
}

################################################################################
# Вывод информации для подключения
################################################################################

print_connection_info() {
    print_header "УСТАНОВКА ЗАВЕРШЕНА"
    
    source "$INSTALL_DIR/.env"
    
    # Определяем адрес сервера
    if [ "$USE_DOMAIN" = "yes" ] && [ -n "$DOMAIN_NAME" ]; then
        SERVER_ADDR="$DOMAIN_NAME"
    elif [ "$USE_NAT" = "yes" ] && [ -n "$NAT_IP" ]; then
        SERVER_ADDR="$NAT_IP"
    else
        SERVER_ADDR=$(curl -4 -s ifconfig.me 2>/dev/null || curl -4 -s icanhazip.com 2>/dev/null || hostname -I | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    fi
    
    # Формируем клиентский секрет для ссылки:
    # - TLS/fakeTLS (USE_DOMAIN=yes): ee + 32 hex
    # - Random Padding (USE_DD_PREFIX=yes): dd + 32 hex
    # - Иначе: plain 32 hex
    if [ "$USE_DOMAIN" = "yes" ] && [ -n "$DOMAIN_NAME" ]; then
        CLIENT_SECRET="ee${SECRET}"
    elif [ "$USE_DD_PREFIX" = "yes" ]; then
        CLIENT_SECRET="dd${SECRET}"
    else
        CLIENT_SECRET="$SECRET"
    fi

    # Формируем ссылку для подключения
    PROXY_LINK="tg://proxy?server=$SERVER_ADDR&port=$EXTERNAL_PORT&secret=$CLIENT_SECRET"

    echo
    echo "═══════════════════════════════════════════════════════════"
    echo -e "${GREEN}✓ MTProxy успешно установлен и запущен!${NC}"
    echo "═══════════════════════════════════════════════════════════"
    echo
    echo -e "${CYAN}📋 КОНФИГУРАЦИЯ:${NC}"
    echo "   Сервер:     $SERVER_ADDR"
    echo "   Порт:       $EXTERNAL_PORT"
    echo "   Секрет:     $CLIENT_SECRET"
    echo "   Воркеры:    $WORKERS"
    if [ -n "$AD_TAG" ] && [ "$AD_TAG" != "пропустить" ]; then
        echo "   AD Tag:     $AD_TAG"
    fi
    echo
    echo -e "${CYAN}🔗 ССЫЛКА ДЛЯ ПОДКЛЮЧЕНИЯ:${NC}"
    echo "═══════════════════════════════════════════════════════════"
    echo "$PROXY_LINK"
    echo "═══════════════════════════════════════════════════════════"
    echo
    echo -e "${CYAN}📱 ИНСТРУКЦИЯ:${NC}"
    echo "   1. Откройте ссылку на устройстве с Telegram"
    echo "   2. Нажмите 'Connect Proxy'"
    echo "   3. Прокси автоматически добавится"
    echo
    echo -e "${CYAN}🤖 РЕГИСТРАЦИЯ В @MTProxybot:${NC}"
    echo "   1. Откройте @MTProxybot в Telegram"
    echo "   2. Отправьте команду /newproxy"
    echo "   3. Отправьте вашу ссылку прокси"
    echo "   4. Получите AD Tag для монетизации"
    echo
    echo -e "${CYAN}🛠 УПРАВЛЕНИЕ:${NC}"
    echo "   Менеджер:     mtproxy  (симлинк → $INSTALL_DIR/manage_mtproxy_official.sh)"
    echo "   Статус:       systemctl status $SERVICE_NAME"
    echo "   Остановка:    systemctl stop $SERVICE_NAME"
    echo "   Запуск:       systemctl start $SERVICE_NAME"
    echo "   Перезапуск:   systemctl restart $SERVICE_NAME"
    echo "   Логи:         journalctl -u $SERVICE_NAME -f"
    echo "   Статистика:   curl http://127.0.0.1:$STATS_PORT/stats"
    echo
    echo -e "${CYAN}📊 МОНИТОРИНГ:${NC}"
    echo "   mtproxy status"
    echo "   mtproxy stats"
    echo
    echo -e "${CYAN}📁 ФАЙЛЫ:${NC}"
    echo "   Конфигурация: $INSTALL_DIR/.env"
    echo "   Бинарник:     $INSTALL_DIR/objs/bin/mtproto-proxy"
    echo "   Рабочая папка: $INSTALL_DIR/run"
    echo "   Service:      /etc/systemd/system/$SERVICE_NAME.service"
    echo
    
    # Сохраняем ссылку в файл
    cat > "$INSTALL_DIR/proxy_link.txt" << EOF
MTProxy Connection Link
═══════════════════════════════════════════════════════════

Server:  $SERVER_ADDR
Port:    $EXTERNAL_PORT
Secret:  $CLIENT_SECRET

Connection Link:
$PROXY_LINK

═══════════════════════════════════════════════════════════
Generated: $(date)
EOF
    
    print_success "Ссылка сохранена: $INSTALL_DIR/proxy_link.txt"
    echo
}

################################################################################
# ОСНОВНАЯ ФУНКЦИЯ
################################################################################

main() {
    clear
    
    print_header "MTProxy Official - Установка"
    echo -e "${CYAN}Официальная реализация от Telegram (C)${NC}"
    echo -e "${CYAN}Система: Ubuntu 20.04+${NC}"
    echo
    
    # Проверки
    check_root
    check_ubuntu
    
    # Установка
    install_dependencies
    clone_and_build_mtproxy
    setup_management_scripts
    download_telegram_configs
    interactive_configuration
    create_systemd_service
    setup_config_updater
    integrate_with_remnawave
    start_and_verify
    print_connection_info
    
    echo
    print_success "Установка успешно завершена!"
    echo
}

# Запуск
main "$@"
