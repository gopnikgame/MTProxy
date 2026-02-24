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
    print_header "Установка зависимостей"

    print_info "Обновление списка пакетов..."
    apt-get update -qq

    # Попытка исправить возможные проблемы с зависимостями
    print_info "Проверка целостности пакетов..."
    if ! apt-get install -f -y > /dev/null 2>&1; then
        print_warning "Обнаружены проблемы с зависимостями, попытка исправления..."
        dpkg --configure -a
        apt-get install -f -y
    fi

    print_info "Установка необходимых пакетов..."

    # Устанавливаем пакеты по одному, чтобы определить проблемный
    PACKAGES="git curl build-essential libssl-dev zlib1g-dev certbot xxd"

    for package in $PACKAGES; do
        if ! dpkg -l | grep -q "^ii.*$package"; then
            print_info "Установка $package..."
            if ! apt-get install -y "$package" 2>/dev/null; then
                print_warning "Не удалось установить $package, но продолжаем..."
            fi
        else
            print_info "$package уже установлен"
        fi
    done

    # Проверяем критичные зависимости
    if ! command -v git &> /dev/null; then
        print_error "Git не установлен и не может быть установлен"
        exit 1
    fi

    if ! command -v make &> /dev/null; then
        print_error "make не установлен (из build-essential)"
        exit 1
    fi

    print_success "Все критичные зависимости установлены"
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
    
    # Секрет пользователя
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}1. СЕКРЕТ ПОЛЬЗОВАТЕЛЯ${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ -f "$INSTALL_DIR/run/secret.txt" ]; then
        EXISTING_SECRET=$(cat "$INSTALL_DIR/run/secret.txt")
        echo -e "Текущий секрет: ${GREEN}$EXISTING_SECRET${NC}"
    fi
    
    read -p "Сгенерировать новый секрет? [Y/n]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        SECRET=$(head -c 16 /dev/urandom | xxd -ps)
        echo "$SECRET" > "$INSTALL_DIR/run/secret.txt"
        print_success "Новый секрет: $SECRET"
    else
        SECRET=${EXISTING_SECRET:-$(head -c 16 /dev/urandom | xxd -ps)}
        echo "$SECRET" > "$INSTALL_DIR/run/secret.txt"
    fi
    
    # Random Padding
    echo
    read -p "Включить Random Padding (защита от DPI)? [Y/n]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        USE_DD_PREFIX="yes"
        DISPLAY_SECRET="dd$SECRET"
        print_success "Random Padding включен"
        print_info "Секрет с префиксом: dd$SECRET"
    else
        USE_DD_PREFIX="no"
        DISPLAY_SECRET="$SECRET"
    fi
    
    # Порты
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}2. НАСТРОЙКА ПОРТОВ${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "Порт для клиентов (внешний): используется клиентами Telegram"
    read -p "Внешний порт [${EXTERNAL_PORT:-443}]: " input
    EXTERNAL_PORT=${input:-${EXTERNAL_PORT:-443}}
    
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
    DETECTED_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "")
    if [ -n "$DETECTED_IP" ]; then
        print_info "Обнаружен внешний IP: $DETECTED_IP"
    fi
    
    read -p "Использовать NAT? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        USE_NAT="yes"
        read -p "Внешний IP адрес [${NAT_IP:-$DETECTED_IP}]: " input
        NAT_IP=${input:-${NAT_IP:-$DETECTED_IP}}
    else
        USE_NAT="no"
    fi
    
    # Домен (для TLS)
    echo
    read -p "Использовать доменное имя вместо IP? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        USE_DOMAIN="yes"
        read -p "Доменное имя: " DOMAIN_NAME
        
        # Проверка DNS
        if host "$DOMAIN_NAME" > /dev/null 2>&1; then
            DOMAIN_IP=$(host "$DOMAIN_NAME" | grep "has address" | awk '{print $4}' | head -n1)
            print_success "Домен $DOMAIN_NAME указывает на $DOMAIN_IP"
        else
            print_warning "Не удалось разрешить домен $DOMAIN_NAME"
        fi
    else
        USE_DOMAIN="no"
    fi
    
    # Сохраняем конфигурацию
    cat > "$INSTALL_DIR/.env" << EOF
# MTProxy Configuration
# Generated: $(date)

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
NAT_IP=${NAT_IP}
USE_DOMAIN=$USE_DOMAIN
DOMAIN_NAME=${DOMAIN_NAME}
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
    
    # Формируем команду запуска
    CMD="/opt/MTProxy/objs/bin/mtproto-proxy"
    CMD="$CMD -u nobody"
    CMD="$CMD -p $STATS_PORT"
    CMD="$CMD -H $EXTERNAL_PORT"
    CMD="$CMD -S $DISPLAY_SECRET"
    CMD="$CMD --aes-pwd /opt/MTProxy/run/proxy-secret"
    CMD="$CMD /opt/MTProxy/run/proxy-multi.conf"
    CMD="$CMD -M $WORKERS"
    
    # Добавляем AD Tag если указан
    if [ -n "$AD_TAG" ]; then
        CMD="$CMD -P $AD_TAG"
    fi
    
    # Добавляем NAT если указан
    if [ "$USE_NAT" = "yes" ] && [ -n "$NAT_IP" ]; then
        CMD="$CMD --nat-info $NAT_IP"
    fi
    
    # Создаем service файл
    cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=MTProxy - Official Telegram MTProto Proxy
After=network.target
Documentation=https://github.com/TelegramMessenger/MTProxy

[Service]
Type=simple
WorkingDirectory=/opt/MTProxy/run
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
# Интеграция с Remnawave
################################################################################

integrate_with_remnawave() {
    print_header "Интеграция с Remnawave (опционально)"
    
    if [ ! -d "$REMNANODE_DIR" ]; then
        print_warning "Remnawave не обнаружена в $REMNANODE_DIR"
        print_info "Пропускаем интеграцию"
        return
    fi
    
    print_success "Remnawave обнаружена"
    echo
    
    read -p "Настроить интеграцию с Remnawave (Nginx SNI)? [y/N]: " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Интеграция пропущена"
        return
    fi
    
    # Запускаем отдельный скрипт интеграции
    if [ -f "./setup_remnawave_integration.sh" ]; then
        bash ./setup_remnawave_integration.sh
    else
        print_warning "Скрипт интеграции не найден"
        print_info "Для интеграции с Remnawave используйте setup_remnawave_integration.sh"
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
        SERVER_ADDR=$(curl -s ifconfig.me || curl -s icanhazip.com || hostname -I | awk '{print $1}')
    fi
    
    # Формируем ссылку для подключения
    PROXY_LINK="tg://proxy?server=$SERVER_ADDR&port=$EXTERNAL_PORT&secret=$DISPLAY_SECRET"
    
    echo
    echo "═══════════════════════════════════════════════════════════"
    echo -e "${GREEN}✓ MTProxy успешно установлен и запущен!${NC}"
    echo "═══════════════════════════════════════════════════════════"
    echo
    echo -e "${CYAN}📋 КОНФИГУРАЦИЯ:${NC}"
    echo "   Сервер:     $SERVER_ADDR"
    echo "   Порт:       $EXTERNAL_PORT"
    echo "   Секрет:     $DISPLAY_SECRET"
    echo "   Воркеры:    $WORKERS"
    if [ -n "$AD_TAG" ]; then
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
    echo "   Статус:       systemctl status $SERVICE_NAME"
    echo "   Остановка:    systemctl stop $SERVICE_NAME"
    echo "   Запуск:       systemctl start $SERVICE_NAME"
    echo "   Перезапуск:   systemctl restart $SERVICE_NAME"
    echo "   Логи:         journalctl -u $SERVICE_NAME -f"
    echo "   Статистика:   curl http://127.0.0.1:$STATS_PORT/stats"
    echo
    echo -e "${CYAN}📊 МОНИТОРИНГ:${NC}"
    echo "   bash manage_mtproxy_official.sh status"
    echo "   bash manage_mtproxy_official.sh stats"
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
Secret:  $DISPLAY_SECRET

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
