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
# Имя Docker-контейнера с Nginx (Remnawave запускается через docker-compose)
NGINX_CONTAINER="remnawave-nginx"

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
        print_info "Укажите правильный путь, отредактировав переменную REMNANODE_DIR в начале скрипта"
        exit 1
    fi

    if [ ! -f "$REMNANODE_DIR/docker-compose.yml" ]; then
        print_error "Docker Compose конфигурация Remnawave не найдена"
        exit 1
    fi

    # Nginx работает в Docker контейнере — проверяем что он запущен
    if ! docker inspect "$NGINX_CONTAINER" > /dev/null 2>&1; then
        print_error "Docker контейнер '$NGINX_CONTAINER' не найден"
        print_info "Запустите Remnawave: cd $REMNANODE_DIR && docker compose up -d"
        exit 1
    fi

    if ! docker inspect --format='{{.State.Running}}' "$NGINX_CONTAINER" 2>/dev/null | grep -q "true"; then
        print_error "Контейнер '$NGINX_CONTAINER' существует, но не запущен"
        print_info "Запустите: cd $REMNANODE_DIR && docker compose up -d"
        exit 1
    fi

    print_success "Remnawave обнаружена, контейнер $NGINX_CONTAINER запущен"
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
    [ -n "$DOMAIN_NAME" ] && echo "  Домен:        $DOMAIN_NAME"
    echo
    
    # Спрашиваем домен
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}1. ДОМЕННОЕ ИМЯ${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    if [ -n "$DOMAIN_NAME" ]; then
        print_info "Из конфигурации MTProxy: $DOMAIN_NAME (Enter для подтверждения)"
    else
        echo "Введите домен для MTProxy (например: proxy.example.com)"
    fi

    while true; do
        if [ -n "$DOMAIN_NAME" ]; then
            read -p "Домен [${DOMAIN_NAME}]: " MTPROXY_DOMAIN
            MTPROXY_DOMAIN="${MTPROXY_DOMAIN:-$DOMAIN_NAME}"
        else
            read -p "Домен: " MTPROXY_DOMAIN
        fi

        # Проверка формата домена
        if [[ ! "$MTPROXY_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
            print_error "Некорректный формат домена"
            continue
        fi

        # Если домен совпадает с уже настроенным — DNS уже проверялся при установке
        if [ "$MTPROXY_DOMAIN" = "$DOMAIN_NAME" ]; then
            print_success "Домен подтверждён: $MTPROXY_DOMAIN"
            break
        fi

        # Новый домен — проверяем DNS
        if host "$MTPROXY_DOMAIN" > /dev/null 2>&1; then
            DOMAIN_IP=$(host "$MTPROXY_DOMAIN" | grep "has address" | awk '{print $4}' | head -n1)
            print_success "Домен $MTPROXY_DOMAIN указывает на $DOMAIN_IP"
            break
        else
            print_warning "Не удалось разрешить домен $MTPROXY_DOMAIN"
            while true; do
                read -p "Продолжить без проверки DNS? [y/N]: " -n 1 -r
                echo
                case "$REPLY" in
                    Y|y) break 2 ;;
                    N|n|"") break ;;
                    *)  print_warning "Неверный ввод. Нажмите Y (да) или N (нет)" ;;
                esac
            done
        fi
    done
    
    # Backend порт для Nginx
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}2. ДОМЕН МАСКИРОВКИ TLS${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "MTProxy подключается к этому домену чтобы получить реальный TLS fingerprint для маскировки."
    echo "Должен быть ВНЕШНИЙ сайт с HTTPS — НЕ сервисный домен этого сервера."
    print_info "Примеры: www.google.com, www.cloudflare.com, telegram.org"
    echo
    # Используем значение из .env если уже есть
    EXISTING_TLS_DOMAIN=$(grep '^TLS_DOMAIN=' "$MTPROXY_DIR/.env" 2>/dev/null | cut -d= -f2)
    # Сбрасываем, если предыдущий TLS_DOMAIN совпадал с сервисным доменом (circular bug)
    if [ "$EXISTING_TLS_DOMAIN" = "$MTPROXY_DOMAIN" ]; then
        EXISTING_TLS_DOMAIN="www.google.com"
        print_warning "Предыдущий TLS_DOMAIN совпадал с сервисным доменом — сброшен до www.google.com"
    fi
    while true; do
        read -p "Домен маскировки [${EXISTING_TLS_DOMAIN:-www.google.com}]: " TLS_DOMAIN
        TLS_DOMAIN=${TLS_DOMAIN:-${EXISTING_TLS_DOMAIN:-www.google.com}}
        if [ "$TLS_DOMAIN" = "$MTPROXY_DOMAIN" ]; then
            print_error "Домен маскировки НЕ может совпадать с сервисным доменом $MTPROXY_DOMAIN!"
            print_info "MTProxy попытается подключиться к себе через Nginx → циклическое соединение"
            print_info "Используйте внешний сайт: www.google.com, telegram.org, cloudflare.com"
            EXISTING_TLS_DOMAIN="www.google.com"
            continue
        fi
        break
    done
    print_success "Домен маскировки: $TLS_DOMAIN"

    # Backend порт для Nginx
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}3. BACKEND ПОРТ${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "Backend порт для Nginx (должен отличаться от других сервисов)"
    print_info "По умолчанию используется EXTERNAL_PORT из конфигурации MTProxy"
    read -p "Backend порт [${EXTERNAL_PORT:-10443}]: " BACKEND_PORT
    BACKEND_PORT=${BACKEND_PORT:-${EXTERNAL_PORT:-10443}}

    # Проверка доступности порта
    if netstat -tuln 2>/dev/null | grep -q ":$BACKEND_PORT "; then
        print_warning "Порт $BACKEND_PORT уже используется!"
        while true; do
            read -p "Всё равно использовать этот порт? [y/N]: " -n 1 -r
            echo
            case "$REPLY" in
                Y|y) break ;;
                N|n|"") print_info "Перезапустите скрипт с другим портом"; exit 1 ;;
                *)    print_warning "Неверный ввод. Нажмите Y (да) или N (нет)" ;;
            esac
        done
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
        
        while true; do
            read -p "Получить новый сертификат? [y/N]: " -n 1 -r
            echo
            case "$REPLY" in
                Y|y) break ;;
                N|n|"") return 0 ;;
                *) print_warning "Неверный ввод. Нажмите Y (да) или N (нет)" ;;
            esac
        done
    fi
    
    print_info "Получение SSL сертификата для $MTPROXY_DOMAIN"
    echo
    # Используем webroot — Nginx уже настроен с /.well-known/acme-challenge/
    # и не требует остановки сервисов (в отличие от --standalone)
    print_info "Используется метод webroot (/var/www/certbot) — сервисы не останавливаются"
    echo

    # Получаем сертификат через webroot (Nginx обслуживает ACME-challenge)
    if certbot certonly --webroot -w /var/www/certbot \
        --non-interactive --agree-tos \
        --register-unsafely-without-email -d "$MTPROXY_DOMAIN"; then
        print_success "SSL сертификат успешно получен"
        return 0
    else
        print_error "Ошибка получения сертификата через webroot"
        print_info "Убедитесь что:"
        echo "  1. Домен $MTPROXY_DOMAIN указывает на этот сервер"
        echo "  2. Nginx запущен и обслуживает /.well-known/acme-challenge/"
        echo "  3. Директория /var/www/certbot существует"
        echo ""
        print_info "Ручное получение:"
        echo "  sudo certbot certonly --webroot -w /var/www/certbot -d $MTPROXY_DOMAIN"
        return 1
    fi
}

################################################################################
# Обновление stream.conf
################################################################################

update_stream_conf() {
    print_header "Обновление stream.conf"

    backup_file "$STREAM_CONF"

    # Relay-порт: Nginx-relay на localhost, снимающий proxy_protocol перед MTProxy.
    # Используем ngx_stream_realip_module (set_real_ip_from) для consume PROXY-заголовка.
    RELAY_PORT=$(( BACKEND_PORT + 1000 ))

    # Парсим существующую конфигурацию
    declare -A DOMAINS
    declare -A BACKEND_PORTS

    if [ -f "$STREAM_CONF" ]; then
        # Извлекаем существующие домены из map блока
        # Важно: regex с ';' нельзя вставлять напрямую в [[ =~ ]] -
        # bash парсит ';' как разделитель команды ещё до входа в контекст regex.
        local _map_re='^[[:space:]]*([a-zA-Z0-9\.-]+)[[:space:]]+([a-zA-Z0-9_]+);'
        local _srv_re='server[[:space:]]+127\.0\.0\.1:([0-9]+);'
        while IFS= read -r line; do
            if [[ $line =~ $_map_re ]]; then
                domain="${BASH_REMATCH[1]}"
                backend="${BASH_REMATCH[2]}"

                if [ "$domain" != "default" ]; then
                    DOMAINS["$domain"]="$backend"
                fi
            fi
        done < <(sed -n '/^map.*$ssl_preread_server_name/,/^}/p' "$STREAM_CONF")

        # Извлекаем порты существующих upstream
        while IFS= read -r line; do
            if [[ $line =~ upstream[[:space:]]+([a-zA-Z0-9_]+)[[:space:]]*\{ ]]; then
                current_upstream="${BASH_REMATCH[1]}"
            fi
            if [[ $line =~ $_srv_re ]] && [ -n "$current_upstream" ]; then
                BACKEND_PORTS["$current_upstream"]="${BASH_REMATCH[1]}"
                current_upstream=""
            fi
        done < "$STREAM_CONF"
    fi

    # Добавляем MTProxy домен — направляем через relay (strips proxy_protocol)
    DOMAINS["$MTPROXY_DOMAIN"]="mtproxy_relay"

    print_info "Найдено доменов: ${#DOMAINS[@]}"

    # Создаем новый stream.conf
    {
        echo "map \$ssl_preread_server_name \$backend_name {"

        for domain in "${!DOMAINS[@]}"; do
            printf "    %-35s %s;\n" "$domain" "${DOMAINS[$domain]}"
        done

        echo "    default                             nginx_backend;"
        echo "}"
        echo

        # Upstream для HTTP-бэкенда (Remnawave/Nginx)
        echo "upstream nginx_backend {"
        echo "    server 127.0.0.1:${BACKEND_PORTS[nginx_backend]:-8443};"
        echo "}"
        echo

        # Upstream для MTProxy relay (промежуточный, снимает proxy_protocol)
        echo "upstream mtproxy_relay {"
        echo "    server 127.0.0.1:$RELAY_PORT;"
        echo "}"
        echo

        # Другие upstream если есть (xray_reality и т.д.)
        for backend in $(printf '%s\n' "${DOMAINS[@]}" | sort -u); do
            if [ "$backend" != "nginx_backend" ] && \
               [ "$backend" != "mtproxy_relay" ] && \
               [ "$backend" != "nginx_backend" ]; then
                case "$backend" in
                    xray_reality)
                        port="${BACKEND_PORTS[$backend]:-9443}"
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

        # Основной SNI-сервер (proxy_protocol on — для HTTP-бэкендов нужен реальный IP)
        echo "server {"
        echo "    listen 443 reuseport;"
        echo "    listen [::]:443 reuseport;"
        echo
        echo "    proxy_pass  \$backend_name;"
        echo "    ssl_preread on;"
        echo "    proxy_protocol on;"
        echo "}"
        echo

        # Relay-сервер для MTProxy:
        # Nginx работает в Docker с network_mode: host, поэтому 127.0.0.1 общий
        # между контейнером и хостом. MTProxy (systemd) слушает на 127.0.0.1:BACKEND_PORT.
        #
        # Поток данных:
        #   client → 443 (main server, proxy_protocol on) → 127.0.0.1:RELAY_PORT
        #   → set_real_ip_from: consume/strip PROXY-заголовок
        #   → proxy_pass: чистый TLS-поток → MTProxy:BACKEND_PORT
        #
        # ngx_stream_realip_module включён в официальный образ nginx:1.29.1
        echo "# MTProxy relay: strips PROXY protocol before forwarding to MTProxy"
        echo "# nginx:1.29.1 includes ngx_stream_realip_module by default"
        echo "# 'proxy_protocol' on listen is REQUIRED for set_real_ip_from to consume the header"
        echo "server {"
        echo "    listen 127.0.0.1:$RELAY_PORT proxy_protocol;"
        echo "    set_real_ip_from 127.0.0.1;"
        echo "    proxy_pass 127.0.0.1:$BACKEND_PORT;"
        echo "}"

    } > "$STREAM_CONF"

    print_success "stream.conf обновлен"
    print_info "MTProxy relay порт: $RELAY_PORT → MTProxy: $BACKEND_PORT"
    print_info "Для работы relay необходим модуль ngx_stream_realip_module"
    print_info "Установка: sudo apt install nginx-full (если не установлен)"
}

################################################################################
# Проверка модуля ngx_stream_realip_module
################################################################################

check_nginx_realip_module() {
    print_header "Проверка Nginx модулей"

    # Проверяем внутри Docker контейнера (nginx:1.29.1 включает stream_realip по умолчанию)
    if docker exec "$NGINX_CONTAINER" nginx -V 2>&1 | grep -q "stream_realip"; then
        print_success "ngx_stream_realip_module доступен в контейнере $NGINX_CONTAINER"
    else
        print_warning "ngx_stream_realip_module НЕ обнаружен в контейнере $NGINX_CONTAINER!"
        print_info "Официальный образ nginx:1.29.1 включает этот модуль — возможно используется другой образ"
        print_info "Проверьте: docker exec $NGINX_CONTAINER nginx -V 2>&1 | grep stream"
        echo
        while true; do
            read -p "Продолжить без проверки модуля? [y/N]: " -n 1 -r
            echo
            case "$REPLY" in
                Y|y) break ;;
                N|n|"") exit 1 ;;
                *) print_warning "Неверный ввод. Нажмите Y (да) или N (нет)" ;;
            esac
        done
        print_warning "Продолжаем — убедитесь что модуль доступен"
    fi
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
    local _sn_re='server_name[[:space:]]+(.+);'
    if [ -f "$CONF_80" ]; then
        while IFS= read -r line; do
            if [[ $line =~ $_sn_re ]]; then
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

    # TLS_DOMAIN — домен маскировки (для флага -D), НЕ сервисный домен.
    # MTProxy подключается к этому внешнему сайту для получения TLS fingerprint.
    if ! grep -q "^TLS_DOMAIN=" "$MTPROXY_DIR/.env"; then
        echo "TLS_DOMAIN=$TLS_DOMAIN" >> "$MTPROXY_DIR/.env"
    else
        sed -i "s/^TLS_DOMAIN=.*/TLS_DOMAIN=$TLS_DOMAIN/" "$MTPROXY_DIR/.env"
    fi

    # Обновляем systemd сервис:
    # 1. Добавляем -D $DOMAIN для TLS-режима (fakeTLS) — обязательно для SNI-роутинга
    # 2. Исправляем -S: должен быть SECRET (32 hex), не DISPLAY_SECRET (с dd/ee префиксом)
    SERVICE_FILE="/etc/systemd/system/mtproxy.service"
    if [ -f "$SERVICE_FILE" ]; then
        source "$MTPROXY_DIR/.env"

        # Исправляем -S если используется DISPLAY_SECRET с dd-префиксом (34 символа вместо 32)
        if grep -q "\-S dd$SECRET\b\|\-S ee$SECRET\b" "$SERVICE_FILE" 2>/dev/null; then
            sed -i "s|-S dd${SECRET}|-S ${SECRET}|g; s|-S ee${SECRET}|-S ${SECRET}|g" "$SERVICE_FILE"
            print_success "Исправлен -S: убран dd/ee-префикс (сервер требует ровно 32 hex)"
        fi

        # Устанавливаем -D TLS_DOMAIN (домен маскировки, НЕ сервисный домен).
        # TLS_DOMAIN — внешний сайт, MTProxy соединяется с ним для получения TLS fingerprint.
        # Это предотвращает циклическое подключение MTProxy к самому себе через Nginx.
        if [ -z "$TLS_DOMAIN" ] || [ "$TLS_DOMAIN" = "$MTPROXY_DOMAIN" ]; then
            print_error "TLS_DOMAIN ('${TLS_DOMAIN:-пусто}') не задан или совпадает с сервисным доменом!"
            print_info "MTProxy с -D <свой домен> → исходящее соединение через Nginx → циклический зависон"
            print_info "Исправьте TLS_DOMAIN в $MTPROXY_DIR/.env (например: TLS_DOMAIN=www.google.com)"
            return 1
        fi
        EFFECTIVE_TLS="$TLS_DOMAIN"
        # Удаляем старый -D если есть (может указывать на неверный домен)
        sed -i 's| -D [^ ]*||g' "$SERVICE_FILE"
        sed -i "s|--aes-pwd|-D $EFFECTIVE_TLS --aes-pwd|" "$SERVICE_FILE"
        print_success "Установлен -D $EFFECTIVE_TLS (домен маскировки TLS)"

        systemctl daemon-reload
        print_success "Systemd сервис обновлен"
    else
        print_warning "Файл сервиса не найден: $SERVICE_FILE"
        print_info "Убедитесь что MTProxy установлен через install_official.sh"
    fi

    print_success "Конфигурация MTProxy обновлена"
}

################################################################################
# Перезапуск сервисов
################################################################################

restart_services() {
    print_header "Перезапуск сервисов"

    # Nginx работает в Docker контейнере (network_mode: host).
    # Используем docker exec для управления — НЕ docker compose restart
    # (restart прерывает все соединения, reload — мягкий, без разрыва)

    # Шаг 1: Валидация конфигурации внутри контейнера
    print_info "Проверка конфигурации Nginx в контейнере $NGINX_CONTAINER..."
    if docker exec "$NGINX_CONTAINER" nginx -t 2>/dev/null; then
        print_success "Конфигурация Nginx валидна"
    else
        print_error "Ошибка в конфигурации Nginx!"
        print_info "Детали: docker exec $NGINX_CONTAINER nginx -t"
        print_info "Backup конфигурации: $STREAM_CONF.backup.*"
        return 1
    fi

    # Шаг 2: Мягкий reload Nginx (без разрыва соединений)
    print_info "Перезагрузка Nginx в контейнере $NGINX_CONTAINER..."
    if docker exec "$NGINX_CONTAINER" nginx -s reload; then
        print_success "Nginx успешно перезагружен (graceful reload)"
    else
        print_error "Ошибка перезагрузки Nginx"
        print_info "Попытка через docker compose restart..."
        cd "$REMNANODE_DIR"
        docker compose restart remnawave-nginx 2>/dev/null || \
            docker-compose restart remnawave-nginx 2>/dev/null || true
    fi

    # Шаг 3: Запускаем/перезапускаем MTProxy (системный сервис на хосте)
    print_info "Запуск MTProxy (systemd)..."

    # MTProxy C-код требует PID < 65536 (assert в common/pid.c)
    sysctl -w kernel.pid_max=65535 >/dev/null 2>&1 || true

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

    # Шаг 4: Проверяем порты (network_mode: host — все порты видны с хоста)
    print_info "Проверка портов..."

    if ss -tuln 2>/dev/null | grep -q ":443 " || \
       netstat -tuln 2>/dev/null | grep -q ":443 "; then
        print_success "Порт 443 открыт (Nginx SNI)"
    fi

    RELAY_PORT=$(( BACKEND_PORT + 1000 ))
    if ss -tuln 2>/dev/null | grep -q "127.0.0.1:$RELAY_PORT" || \
       netstat -tuln 2>/dev/null | grep -q "127.0.0.1:$RELAY_PORT"; then
        print_success "Relay порт $RELAY_PORT открыт (nginx → MTProxy)"
    fi

    if ss -tuln 2>/dev/null | grep -q "127.0.0.1:$BACKEND_PORT" || \
       netstat -tuln 2>/dev/null | grep -q "127.0.0.1:$BACKEND_PORT"; then
        print_success "MTProxy backend порт $BACKEND_PORT открыт"
    fi
}

################################################################################
# Вывод итоговой информации
################################################################################

print_final_info() {
    print_header "ИНТЕГРАЦИЯ ЗАВЕРШЕНА"

    source "$MTPROXY_DIR/.env"

    RELAY_PORT=$(( BACKEND_PORT + 1000 ))

    # Для TLS-режима (fakeTLS) клиентский секрет должен иметь префикс 'ee'
    # Сервер использует -S $SECRET (32 hex) и -D $DOMAIN
    # Клиент использует secret=ee$SECRET в ссылке tg://proxy
    EE_SECRET="ee${SECRET}"
    PROXY_LINK="tg://proxy?server=$MTPROXY_DOMAIN&port=443&secret=$EE_SECRET"

    echo
    echo "═══════════════════════════════════════════════════════════"
    echo -e "${GREEN}✓ MTProxy успешно интегрирован с Remnawave!${NC}"
    echo "═══════════════════════════════════════════════════════════"
    echo
    echo -e "${CYAN}📋 КОНФИГУРАЦИЯ:${NC}"
    echo "   Домен сервиса: $MTPROXY_DOMAIN"
    echo "   Домен маскировки: ${TLS_DOMAIN:-$MTPROXY_DOMAIN} (флаг -D)"
    echo "   Внешний порт:   443 (Nginx SNI)"
    echo "   Relay порт:     $RELAY_PORT (nginx relay, снимает proxy_protocol)"
    echo "   MTProxy порт:   $BACKEND_PORT (внутренний)"
    echo "   Секрет сервера: $SECRET (32 hex, используется с -S)"
    echo "   Секрет клиента: $EE_SECRET (ee-префикс = TLS/fakeTLS режим)"
    echo
    echo -e "${CYAN}🔗 ССЫЛКА ДЛЯ ПОДКЛЮЧЕНИЯ:${NC}"
    echo "═══════════════════════════════════════════════════════════"
    echo "$PROXY_LINK"
    echo "═══════════════════════════════════════════════════════════"
    echo
    echo -e "${CYAN}🏗 АРХИТЕКТУРА:${NC}"
    echo "   Internet:443"
    echo "   → Nginx Docker (network_mode:host, ssl_preread, proxy_protocol on)"
    echo "   │    ru3-x.vline.online → nginx_backend:8443  (proxy_protocol ✓)"
    echo "   │    $MTPROXY_DOMAIN → mtproxy_relay:$RELAY_PORT"
    echo "   → Relay:$RELAY_PORT (set_real_ip_from strips PROXY header)"
    echo "   → MTProxy:$BACKEND_PORT (systemd на хосте, -D $MTPROXY_DOMAIN)"
    echo
    echo -e "${CYAN}📁 ФАЙЛЫ КОНФИГУРАЦИИ:${NC}"
    echo "   Stream:   $STREAM_CONF"
    echo "   HTTP:     $SITES_AVAILABLE/80.conf"
    echo "   MTProxy:  $MTPROXY_DIR/.env"
    echo "   Service:  /etc/systemd/system/mtproxy.service"
    echo
    echo -e "${CYAN}🛠 УПРАВЛЕНИЕ:${NC}"
    echo "   MTProxy:         bash manage_mtproxy_official.sh"
    echo "   Nginx проверка:  docker exec $NGINX_CONTAINER nginx -t"
    echo "   Nginx reload:    docker exec $NGINX_CONTAINER nginx -s reload"
    echo "   Nginx логи:      docker logs $NGINX_CONTAINER -f"
    echo

    # Сохраняем информацию
    cat > "$MTPROXY_DIR/remnawave_integration.txt" << EOF
MTProxy + Remnawave Integration
═══════════════════════════════════════════════════════════

Domain:         $MTPROXY_DOMAIN
External Port:  443 (Nginx Docker, network_mode:host)
Relay Port:     $RELAY_PORT (strips proxy_protocol for MTProxy)
MTProxy Port:   $BACKEND_PORT (systemd on host)
Server Secret:  $SECRET  (32 hex, for -S flag)
Client Secret:  $EE_SECRET (ee-prefix = TLS/fakeTLS mode)
Nginx Container: $NGINX_CONTAINER

Connection Link:
$PROXY_LINK

Architecture:
Internet:443
→ Nginx Docker (network_mode:host, ssl_preread, proxy_protocol on)
│    ru3-x.vline.online → nginx_backend:8443  (proxy_protocol required ✓)
│    $MTPROXY_DOMAIN → mtproxy_relay:$RELAY_PORT
→ Relay:$RELAY_PORT (set_real_ip_from strips PROXY header)
→ MTProxy:$BACKEND_PORT systemd (-D $MTPROXY_DOMAIN, fakeTLS)

Management:
  docker exec $NGINX_CONTAINER nginx -t          # validate config
  docker exec $NGINX_CONTAINER nginx -s reload   # graceful reload
  bash manage_mtproxy_official.sh                # MTProxy management

Configuration Files:
- Stream:  $STREAM_CONF
- HTTP:    $SITES_AVAILABLE/80.conf
- MTProxy: $MTPROXY_DIR/.env
- Service: /etc/systemd/system/mtproxy.service

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
    check_nginx_realip_module

    # Установка
    interactive_setup
    obtain_ssl_certificate
    update_stream_conf
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
