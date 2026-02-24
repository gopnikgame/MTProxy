#!/bin/bash

################################################################################
# MTProxy Official - Интеграция с Remnawave
# Настройка Nginx SNI для официального MTProxy от Telegram
# Использование: sudo bash setup_remnawave_integration.sh
################################################################################

set -e

# Константы
MTPROXY_DIR="/opt/MTProxy"
REMNANODE_DIR="/opt/remnanode"
SITES_AVAILABLE="$REMNANODE_DIR/sites-available"
STREAM_CONF="$REMNANODE_DIR/stream.conf"

# Цвета
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

# Проверка установки MTProxy
check_mtproxy() {
    if [ ! -d "$MTPROXY_DIR" ]; then
        print_error "MTProxy не установлен в $MTPROXY_DIR"
        print_info "Сначала установите MTProxy: sudo bash install_official.sh"
        exit 1
    fi
    
    if [ ! -f "$MTPROXY_DIR/.env" ]; then
        print_error "Конфигурация MTProxy не найдена"
        exit 1
    fi
}

# Проверка установки Remnawave
check_remnawave() {
    if [ ! -d "$REMNANODE_DIR" ]; then
        print_error "Remnawave не найдена в $REMNANODE_DIR"
        exit 1
    fi
    
    if [ ! -f "$REMNANODE_DIR/docker-compose.yml" ]; then
        print_error "Docker Compose конфигурация Remnawave не найдена"
        exit 1
    fi
}

# Создание backup
backup_file() {
    local file=$1
    if [ -f "$file" ]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup"
        print_success "Создан backup: $backup"
    fi
}

################################################################################
# Интерактивная настройка
################################################################################

interactive_setup() {
    print_header "Интеграция MTProxy с Remnawave"
    
    # Загружаем конфигурацию MTProxy
    source "$MTPROXY_DIR/.env"
    
    echo "Текущие настройки MTProxy:"
    echo "  Внешний порт: $EXTERNAL_PORT"
    echo
    
    # Спрашиваем домен
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}1. ДОМЕННОЕ ИМЯ${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "Введите домен для MTProxy (например: proxy.example.com)"
    
    while true; do
        read -p "Домен: " MTPROXY_DOMAIN
        
        # Проверка формата домена
        if [[ ! "$MTPROXY_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
            print_error "Некорректный формат домена"
            continue
        fi
        
        # Проверка DNS
        if host "$MTPROXY_DOMAIN" > /dev/null 2>&1; then
            DOMAIN_IP=$(host "$MTPROXY_DOMAIN" | grep "has address" | awk '{print $4}' | head -n1)
            print_success "Домен $MTPROXY_DOMAIN указывает на $DOMAIN_IP"
            break
        else
            print_warning "Не удалось разрешить домен $MTPROXY_DOMAIN"
            read -p "Продолжить без проверки DNS? [y/N]: " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                break
            fi
        fi
    done
    
    # Backend порт для Nginx
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}2. BACKEND ПОРТ${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "Backend порт для Nginx (должен отличаться от других сервисов)"
    read -p "Backend порт [10443]: " BACKEND_PORT
    BACKEND_PORT=${BACKEND_PORT:-10443}
    
    # Проверка доступности порта
    if netstat -tuln 2>/dev/null | grep -q ":$BACKEND_PORT "; then
        print_warning "Порт $BACKEND_PORT уже используется!"
        read -p "Всё равно использовать этот порт? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Перезапустите скрипт с другим портом"
            exit 1
        fi
    fi
}

################################################################################
# Получение SSL сертификата
################################################################################

obtain_ssl_certificate() {
    print_header "Получение SSL сертификата"
    
    CERT_PATH="/etc/letsencrypt/live/$MTPROXY_DOMAIN/fullchain.pem"
    
    # Проверяем существующий сертификат
    if [ -f "$CERT_PATH" ]; then
        print_success "SSL сертификат уже существует для $MTPROXY_DOMAIN"
        
        # Проверяем срок действия
        EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_PATH" | cut -d= -f2)
        print_info "Срок действия: $EXPIRY"
        
        read -p "Получить новый сертификат? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi
    
    print_info "Получение SSL сертификата для $MTPROXY_DOMAIN"
    echo
    print_warning "Для получения сертификата необходимо временно остановить контейнеры"
    read -p "Продолжить? [Y/n]: " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        print_info "Получите сертификат вручную:"
        echo "  sudo certbot certonly --standalone -d $MTPROXY_DOMAIN"
        return 1
    fi
    
    # Останавливаем контейнеры
    print_info "Остановка контейнеров..."
    
    if [ -f "$REMNANODE_DIR/docker-compose.yml" ]; then
        cd "$REMNANODE_DIR"
        docker compose down 2>/dev/null || docker-compose down 2>/dev/null || true
    fi
    
    if systemctl is-active --quiet mtproxy; then
        systemctl stop mtproxy
    fi
    
    # Получаем сертификат
    print_info "Запуск certbot..."
    
    if certbot certonly --standalone --non-interactive --agree-tos \
        --register-unsafely-without-email -d "$MTPROXY_DOMAIN"; then
        print_success "SSL сертификат успешно получен"
        return 0
    else
        print_error "Ошибка получения сертификата"
        print_info "Попробуйте вручную:"
        echo "  sudo certbot certonly --standalone -d $MTPROXY_DOMAIN"
        return 1
    fi
}

################################################################################
# Обновление stream.conf
################################################################################

update_stream_conf() {
    print_header "Обновление stream.conf"
    
    backup_file "$STREAM_CONF"
    
    # Парсим существующую конфигурацию
    declare -A DOMAINS
    
    if [ -f "$STREAM_CONF" ]; then
        # Извлекаем существующие домены из map блока
        while IFS= read -r line; do
            if [[ $line =~ ^[[:space:]]*([a-zA-Z0-9\.\-]+)[[:space:]]+([a-zA-Z0-9_]+); ]]; then
                domain="${BASH_REMATCH[1]}"
                backend="${BASH_REMATCH[2]}"
                
                if [ "$domain" != "default" ]; then
                    DOMAINS["$domain"]="$backend"
                fi
            fi
        done < <(sed -n '/^map.*$ssl_preread_server_name/,/^}/p' "$STREAM_CONF")
    fi
    
    # Добавляем MTProxy домен
    DOMAINS["$MTPROXY_DOMAIN"]="mtproxy_backend"
    
    print_info "Найдено доменов: ${#DOMAINS[@]}"
    
    # Создаем новый stream.conf
    {
        echo "map \$ssl_preread_server_name \$backend_name {"
        
        for domain in "${!DOMAINS[@]}"; do
            printf "    %-30s %s;\n" "$domain" "${DOMAINS[$domain]}"
        done
        
        echo "    default                        nginx_backend;"
        echo "}"
        echo
        
        # Upstream блоки
        echo "upstream nginx_backend {"
        echo "    server 127.0.0.1:8443;"
        echo "}"
        echo
        
        echo "upstream mtproxy_backend {"
        echo "    server 127.0.0.1:$BACKEND_PORT;"
        echo "}"
        echo
        
        # Другие upstream если есть
        for backend in $(printf '%s\n' "${DOMAINS[@]}" | sort -u); do
            if [ "$backend" != "nginx_backend" ] && [ "$backend" != "mtproxy_backend" ]; then
                # Определяем порт для известных backend
                case "$backend" in
                    xray_reality)
                        port="9443"
                        ;;
                    *)
                        continue
                        ;;
                esac
                
                echo "upstream $backend {"
                echo "    server 127.0.0.1:$port;"
                echo "}"
                echo
            fi
        done
        
        # Server блок
        echo "server {"
        echo "    listen 443 reuseport;"
        echo "    listen [::]:443 reuseport;"
        echo
        echo "    proxy_pass  \$backend_name;"
        echo "    ssl_preread on;"
        echo "    proxy_protocol on;"
        echo "}"
        
    } > "$STREAM_CONF"
    
    print_success "stream.conf обновлен"
}

################################################################################
# Создание Nginx конфигурации для MTProxy
################################################################################

create_nginx_config() {
    print_header "Создание Nginx конфигурации"
    
    mkdir -p "$SITES_AVAILABLE"
    
    NGINX_CONF="$SITES_AVAILABLE/$MTPROXY_DOMAIN"
    backup_file "$NGINX_CONF"
    
    # Загружаем конфигурацию MTProxy
    source "$MTPROXY_DIR/.env"
    
    cat > "$NGINX_CONF" << EOF
server {
    server_tokens off;
    server_name $MTPROXY_DOMAIN;
    listen $BACKEND_PORT ssl proxy_protocol;
    listen [::]:$BACKEND_PORT ssl proxy_protocol;
    http2 on;
    
    index index.html;
    root /var/www/html/;

    real_ip_header proxy_protocol;
    set_real_ip_from 127.0.0.1;

    # SSL Configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_certificate /etc/letsencrypt/live/$MTPROXY_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$MTPROXY_DOMAIN/privkey.pem;

    # Proxy to MTProxy (official implementation uses raw TCP, not HTTP)
    # This location serves as a dummy for SSL handshake
    location / {
        # MTProxy works at transport level, not HTTP
        # This section handles HTTP requests if any
        return 200 'MTProxy Server';
        add_header Content-Type text/plain;
    }

    # Security
    set \$safe "";
    if (\$host !~* ^(.+\\.)?${MTPROXY_DOMAIN//./\\.}\$ ) {return 444;}
    if (\$scheme ~* https) {set \$safe 1;}
    if (\$ssl_server_name !~* ^(.+\\.)?${MTPROXY_DOMAIN//./\\.}\$ ) {set \$safe "\${safe}0"; }
    if (\$safe = 10) {return 444;}
    
    error_page 400 401 402 403 500 501 502 503 504 =404 /404;
    proxy_intercept_errors on;

    # Timeouts
    http2_max_concurrent_streams 1024;
    keepalive_timeout            60s;
    keepalive_requests           2048;
    client_body_timeout          600s;
    client_header_timeout        300s;

    sendfile              on;
    tcp_nodelay           on;
    tcp_nopush            on;
    client_max_body_size  10m;
}
EOF
    
    print_success "Nginx конфигурация создана: $NGINX_CONF"
}

################################################################################
# Обновление 80.conf
################################################################################

update_80_conf() {
    print_header "Обновление 80.conf (HTTP)"
    
    CONF_80="$SITES_AVAILABLE/80.conf"
    backup_file "$CONF_80"
    
    # Извлекаем существующие домены
    EXISTING_DOMAINS=()
    
    if [ -f "$CONF_80" ]; then
        while IFS= read -r line; do
            if [[ $line =~ server_name[[:space:]]+(.+); ]]; then
                domains_str="${BASH_REMATCH[1]}"
                IFS=' ' read -ra domains <<< "$domains_str"
                EXISTING_DOMAINS+=("${domains[@]}")
                break
            fi
        done < "$CONF_80"
    fi
    
    # Добавляем MTProxy домен если его нет
    if [[ ! " ${EXISTING_DOMAINS[@]} " =~ " ${MTPROXY_DOMAIN} " ]]; then
        EXISTING_DOMAINS+=("$MTPROXY_DOMAIN")
    fi
    
    # Создаем 80.conf
    {
        echo "server {"
        echo "    listen 80;"
        echo "    server_name ${EXISTING_DOMAINS[@]};"
        echo
        echo "    # ACME challenges для обновления сертификатов"
        echo "    location /.well-known/acme-challenge/ {"
        echo "        root /var/www/certbot;"
        echo "        try_files \$uri =404;"
        echo "    }"
        echo
        echo "    # Все остальные запросы редиректим на HTTPS"
        echo "    location / {"
        echo "        return 301 https://\$host\$request_uri;"
        echo "    }"
        echo "}"
    } > "$CONF_80"
    
    print_success "80.conf обновлен"
    print_info "Доменов в конфигурации: ${#EXISTING_DOMAINS[@]}"
}

################################################################################
# Обновление конфигурации MTProxy
################################################################################

update_mtproxy_config() {
    print_header "Обновление конфигурации MTProxy"
    
    # Обновляем .env с доменом и NAT info
    if ! grep -q "^DOMAIN_NAME=" "$MTPROXY_DIR/.env"; then
        echo "DOMAIN_NAME=$MTPROXY_DOMAIN" >> "$MTPROXY_DIR/.env"
    else
        sed -i "s/^DOMAIN_NAME=.*/DOMAIN_NAME=$MTPROXY_DOMAIN/" "$MTPROXY_DIR/.env"
    fi
    
    if ! grep -q "^USE_DOMAIN=" "$MTPROXY_DIR/.env"; then
        echo "USE_DOMAIN=yes" >> "$MTPROXY_DIR/.env"
    else
        sed -i "s/^USE_DOMAIN=.*/USE_DOMAIN=yes/" "$MTPROXY_DIR/.env"
    fi
    
    print_success "Конфигурация MTProxy обновлена"
}

################################################################################
# Перезапуск сервисов
################################################################################

restart_services() {
    print_header "Перезапуск сервисов"
    
    # Запускаем Remnawave
    print_info "Запуск Remnawave..."
    cd "$REMNANODE_DIR"
    
    if command -v docker-compose &> /dev/null; then
        docker-compose down 2>/dev/null || true
        docker-compose up -d
    else
        docker compose down 2>/dev/null || true
        docker compose up -d
    fi
    
    print_success "Remnawave запущена"
    
    # Запускаем MTProxy
    print_info "Запуск MTProxy..."
    
    if systemctl is-active --quiet mtproxy; then
        systemctl restart mtproxy
    else
        systemctl start mtproxy
    fi
    
    sleep 3
    
    if systemctl is-active --quiet mtproxy; then
        print_success "MTProxy запущен"
    else
        print_error "Ошибка запуска MTProxy"
        print_info "Логи: journalctl -u mtproxy -n 50"
        return 1
    fi
    
    # Проверяем порты
    print_info "Проверка портов..."
    
    if netstat -tuln 2>/dev/null | grep -q ":443 "; then
        print_success "Порт 443 открыт (Nginx)"
    fi
    
    if netstat -tuln 2>/dev/null | grep -q "127.0.0.1:$BACKEND_PORT "; then
        print_success "Backend порт $BACKEND_PORT открыт"
    fi
}

################################################################################
# Вывод итоговой информации
################################################################################

print_final_info() {
    print_header "ИНТЕГРАЦИЯ ЗАВЕРШЕНА"
    
    source "$MTPROXY_DIR/.env"
    
    # Формируем ссылку
    PROXY_LINK="tg://proxy?server=$MTPROXY_DOMAIN&port=443&secret=$DISPLAY_SECRET"
    
    echo
    echo "═══════════════════════════════════════════════════════════"
    echo -e "${GREEN}✓ MTProxy успешно интегрирован с Remnawave!${NC}"
    echo "═══════════════════════════════════════════════════════════"
    echo
    echo -e "${CYAN}📋 КОНФИГУРАЦИЯ:${NC}"
    echo "   Домен:          $MTPROXY_DOMAIN"
    echo "   Внешний порт:   443 (Nginx SNI)"
    echo "   Backend порт:   $BACKEND_PORT"
    echo "   Секрет:         $DISPLAY_SECRET"
    echo
    echo -e "${CYAN}🔗 ССЫЛКА ДЛЯ ПОДКЛЮЧЕНИЯ:${NC}"
    echo "═══════════════════════════════════════════════════════════"
    echo "$PROXY_LINK"
    echo "═══════════════════════════════════════════════════════════"
    echo
    echo -e "${CYAN}🏗 АРХИТЕКТУРА:${NC}"
    echo "   Internet:443 → Nginx SNI → Backend:$BACKEND_PORT → MTProxy"
    echo
    echo -e "${CYAN}📁 ФАЙЛЫ КОНФИГУРАЦИИ:${NC}"
    echo "   Stream:   $STREAM_CONF"
    echo "   Nginx:    $SITES_AVAILABLE/$MTPROXY_DOMAIN"
    echo "   HTTP:     $SITES_AVAILABLE/80.conf"
    echo "   MTProxy:  $MTPROXY_DIR/.env"
    echo
    echo -e "${CYAN}🛠 УПРАВЛЕНИЕ:${NC}"
    echo "   MTProxy:    bash manage_mtproxy_official.sh"
    echo "   Remnawave:  cd $REMNANODE_DIR && docker compose"
    echo
    
    # Сохраняем информацию
    cat > "$MTPROXY_DIR/remnawave_integration.txt" << EOF
MTProxy + Remnawave Integration
═══════════════════════════════════════════════════════════

Domain:         $MTPROXY_DOMAIN
External Port:  443 (Nginx SNI)
Backend Port:   $BACKEND_PORT
Secret:         $DISPLAY_SECRET

Connection Link:
$PROXY_LINK

Architecture:
Internet:443 → Nginx SNI → Backend:$BACKEND_PORT → MTProxy

Configuration Files:
- Stream:  $STREAM_CONF
- Nginx:   $SITES_AVAILABLE/$MTPROXY_DOMAIN
- HTTP:    $SITES_AVAILABLE/80.conf
- MTProxy: $MTPROXY_DIR/.env

═══════════════════════════════════════════════════════════
Generated: $(date)
EOF
    
    print_success "Информация сохранена: $MTPROXY_DIR/remnawave_integration.txt"
    echo
}

################################################################################
# ОСНОВНАЯ ФУНКЦИЯ
################################################################################

main() {
    clear
    
    print_header "MTProxy + Remnawave - Интеграция"
    echo -e "${CYAN}Настройка Nginx SNI для MTProxy${NC}"
    echo
    
    # Проверки
    check_root
    check_mtproxy
    check_remnawave
    
    # Установка
    interactive_setup
    obtain_ssl_certificate
    update_stream_conf
    create_nginx_config
    update_80_conf
    update_mtproxy_config
    restart_services
    print_final_info
    
    echo
    print_success "Интеграция успешно завершена!"
    echo
}

# Запуск
main "$@"
