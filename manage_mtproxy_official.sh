#!/bin/bash

################################################################################
# MTProxy Official - Управление
# Скрипт для управления официальным MTProxy от Telegram
# Использование: bash manage_mtproxy_official.sh [команда]
################################################################################

# Константы
INSTALL_DIR="/opt/MTProxy"
SERVICE_NAME="mtproxy"
CONFIG_FILE="$INSTALL_DIR/.env"

# Цвета
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
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

# Проверка установки
check_installation() {
    if [ ! -d "$INSTALL_DIR" ]; then
        print_error "MTProxy не установлен"
        print_info "Запустите установку: sudo bash install_official.sh"
        exit 1
    fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Файл конфигурации не найден: $CONFIG_FILE"
        exit 1
    fi
    
    if ! systemctl list-unit-files | grep -q "^$SERVICE_NAME.service"; then
        print_error "Systemd сервис не найден"
        exit 1
    fi
}

################################################################################
# Статус сервиса
################################################################################

show_status() {
    print_header "Статус MTProxy"
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}● $SERVICE_NAME.service - активен и работает${NC}"
    else
        echo -e "${RED}● $SERVICE_NAME.service - остановлен или неактивен${NC}"
    fi
    
    echo
    systemctl status "$SERVICE_NAME" --no-pager -l
    
    echo
    print_info "Подробные логи: journalctl -u $SERVICE_NAME -n 50"
}

################################################################################
# Статистика
################################################################################

show_stats() {
    print_header "Статистика MTProxy"
    
    # Загружаем конфигурацию
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        STATS_PORT=8888
    fi
    
    # Проверяем доступность статистики
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        print_error "Сервис не запущен"
        return 1
    fi
    
    # Получаем статистику
    if command -v curl &> /dev/null; then
        echo "Получение статистики с http://127.0.0.1:$STATS_PORT/stats ..."
        echo
        
        STATS=$(curl -s "http://127.0.0.1:$STATS_PORT/stats" 2>/dev/null)
        
        if [ -n "$STATS" ]; then
            echo "$STATS"
        else
            print_error "Не удалось получить статистику"
            print_info "Проверьте что порт $STATS_PORT открыт"
        fi
    else
        print_error "curl не установлен"
    fi
    
    echo
    print_info "Обновление статистики: curl http://127.0.0.1:$STATS_PORT/stats"
}

################################################################################
# Запуск/Остановка/Перезапуск
################################################################################

start_service() {
    print_header "Запуск MTProxy"
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_warning "Сервис уже запущен"
        return
    fi
    
    systemctl start "$SERVICE_NAME"
    sleep 2
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "MTProxy успешно запущен"
    else
        print_error "Не удалось запустить MTProxy"
        print_info "Логи: journalctl -u $SERVICE_NAME -n 50"
    fi
}

stop_service() {
    print_header "Остановка MTProxy"
    
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        print_warning "Сервис уже остановлен"
        return
    fi
    
    systemctl stop "$SERVICE_NAME"
    sleep 2
    
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "MTProxy остановлен"
    else
        print_error "Не удалось остановить MTProxy"
    fi
}

restart_service() {
    print_header "Перезапуск MTProxy"
    
    systemctl restart "$SERVICE_NAME"
    sleep 2
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "MTProxy успешно перезапущен"
    else
        print_error "Не удалось перезапустить MTProxy"
        print_info "Логи: journalctl -u $SERVICE_NAME -n 50"
    fi
}

################################################################################
# Логи
################################################################################

show_logs() {
    print_header "Логи MTProxy"
    
    echo -e "${CYAN}Последние 50 строк:${NC}"
    echo
    journalctl -u "$SERVICE_NAME" -n 50 --no-pager
    
    echo
    print_info "Для просмотра логов в реальном времени:"
    echo "        journalctl -u $SERVICE_NAME -f"
}

follow_logs() {
    print_header "Логи MTProxy (в реальном времени)"
    echo "Нажмите Ctrl+C для выхода"
    echo
    
    journalctl -u "$SERVICE_NAME" -f
}

################################################################################
# Обновление конфигурации Telegram
################################################################################

update_telegram_config() {
    print_header "Обновление конфигурации Telegram"
    
    cd "$INSTALL_DIR/run" || exit 1
    
    print_info "Загрузка proxy-secret..."
    curl -s https://core.telegram.org/getProxySecret -o proxy-secret.new
    
    if [ -s proxy-secret.new ]; then
        mv proxy-secret.new proxy-secret
        print_success "proxy-secret обновлен"
    else
        print_error "Не удалось загрузить proxy-secret"
        rm -f proxy-secret.new
        return 1
    fi
    
    print_info "Загрузка proxy-multi.conf..."
    curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf.new
    
    if [ -s proxy-multi.conf.new ]; then
        mv proxy-multi.conf.new proxy-multi.conf
        print_success "proxy-multi.conf обновлен"
    else
        print_error "Не удалось загрузить proxy-multi.conf"
        rm -f proxy-multi.conf.new
        return 1
    fi
    
    print_success "Конфигурация Telegram обновлена"
    
    read -p "Перезапустить MTProxy для применения изменений? [Y/n]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        restart_service
    fi
}

################################################################################
# Показать информацию о подключении
################################################################################

show_connection_info() {
    print_header "Информация для подключения"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Файл конфигурации не найден"
        return 1
    fi
    
    source "$CONFIG_FILE"
    
    # Определяем адрес сервера
    if [ "$USE_DOMAIN" = "yes" ] && [ -n "$DOMAIN_NAME" ]; then
        SERVER_ADDR="$DOMAIN_NAME"
    elif [ "$USE_NAT" = "yes" ] && [ -n "$NAT_IP" ]; then
        SERVER_ADDR="$NAT_IP"
    else
        SERVER_ADDR=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')
    fi
    
    # Определяем секрет для клиентской ссылки:
    # - TLS/fakeTLS режим (USE_DOMAIN=yes): ee-префикс (ee + 32 hex)
    # - Random Padding (USE_DD_PREFIX=yes): dd-префикс
    # - Иначе: plain 32 hex
    if [ "$USE_DOMAIN" = "yes" ] && [ -n "$DOMAIN_NAME" ]; then
        CLIENT_SECRET="ee${SECRET}"
    elif [ "$USE_DD_PREFIX" = "yes" ]; then
        CLIENT_SECRET="dd${SECRET}"
    else
        CLIENT_SECRET="$SECRET"
    fi

    # Определяем порт для клиентской ссылки:
    # - Nginx режим (NGINX_MODE=yes): клиенты подключаются через Nginx на порт 443
    # - Иначе: прямое подключение к MTProxy на EXTERNAL_PORT
    if [ "$NGINX_MODE" = "yes" ]; then
        CLIENT_PORT=443
    else
        CLIENT_PORT="$EXTERNAL_PORT"
    fi

    PROXY_LINK="tg://proxy?server=$SERVER_ADDR&port=$CLIENT_PORT&secret=$CLIENT_SECRET"

    echo
    echo "═══════════════════════════════════════════════════════════"
    echo -e "${CYAN}📋 КОНФИГУРАЦИЯ:${NC}"
    echo "   Сервер:     $SERVER_ADDR"
    echo "   Порт:       $CLIENT_PORT"
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
    
    if [ -f "$INSTALL_DIR/proxy_link.txt" ]; then
        print_info "Ссылка сохранена: $INSTALL_DIR/proxy_link.txt"
    fi
}

################################################################################
# Изменение секрета
################################################################################

change_secret() {
    print_header "Изменение секрета"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Файл конфигурации не найден"
        return 1
    fi
    
    source "$CONFIG_FILE"
    
    echo "Текущий секрет: $DISPLAY_SECRET"
    echo
    
    echo "1) Сгенерировать новый секрет"
    echo "2) Ввести секрет вручную"
    echo "0) Отмена"
    echo
    read -p "Выберите действие: " choice
    
    case $choice in
        1)
            NEW_SECRET=$(head -c 16 /dev/urandom | xxd -ps)
            print_success "Новый секрет сгенерирован: $NEW_SECRET"
            ;;
        2)
            read -p "Введите новый секрет (32 hex символа): " NEW_SECRET
            
            if [ ${#NEW_SECRET} -ne 32 ]; then
                print_error "Секрет должен содержать 32 hex символа"
                return 1
            fi
            ;;
        0|*)
            print_info "Отмена"
            return 0
            ;;
    esac
    
    echo
    read -p "Включить Random Padding (dd префикс)? [Y/n]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        DISPLAY_SECRET="dd$NEW_SECRET"
        USE_DD_PREFIX="yes"
    else
        DISPLAY_SECRET="$NEW_SECRET"
        USE_DD_PREFIX="no"
    fi
    
    # Обновляем конфигурацию
    sed -i "s/^SECRET=.*/SECRET=$NEW_SECRET/" "$CONFIG_FILE"
    sed -i "s/^USE_DD_PREFIX=.*/USE_DD_PREFIX=$USE_DD_PREFIX/" "$CONFIG_FILE"
    sed -i "s/^DISPLAY_SECRET=.*/DISPLAY_SECRET=$DISPLAY_SECRET/" "$CONFIG_FILE"
    
    echo "$NEW_SECRET" > "$INSTALL_DIR/run/secret.txt"
    
    print_success "Секрет обновлен: $DISPLAY_SECRET"
    
    # Пересоздаем systemd сервис
    print_info "Обновление systemd сервиса..."
    
    # Загружаем обновленную конфигурацию
    source "$CONFIG_FILE"
    
    # Формируем команду
    CMD="/opt/MTProxy/objs/bin/mtproto-proxy"
    CMD="$CMD -u nobody"
    CMD="$CMD -p $STATS_PORT"
    CMD="$CMD -H $EXTERNAL_PORT"
    # -S принимает ровно 32 hex-символа (без dd/ee префикса)
    CMD="$CMD -S $SECRET"
    CMD="$CMD -M $WORKERS"

    if [ -n "$AD_TAG" ] && [ "$AD_TAG" != "пропустить" ]; then
        CMD="$CMD -P $AD_TAG"
    fi

    # Формат --nat-info: <local-addr>:<global-addr>
    if [ "$USE_NAT" = "yes" ] && [ -n "$NAT_IP" ] && [ -n "$NAT_LOCAL_IP" ]; then
        CMD="$CMD --nat-info $NAT_LOCAL_IP:$NAT_IP"
    fi

    # TLS-режим для SNI-роутинга через Nginx
    # TLS_DOMAIN — домен маскировки (внешний сайт), НЕ сервисный домен
    if [ "$USE_DOMAIN" = "yes" ] && [ -n "${TLS_DOMAIN:-$DOMAIN_NAME}" ]; then
        CMD="$CMD -D ${TLS_DOMAIN:-$DOMAIN_NAME}"
    fi

    CMD="$CMD --aes-pwd /opt/MTProxy/run/proxy-secret /opt/MTProxy/run/proxy-multi.conf"

    # Обновляем service файл
    sed -i "s|^ExecStart=.*|ExecStart=$CMD|" "/etc/systemd/system/$SERVICE_NAME.service"
    
    systemctl daemon-reload
    
    restart_service
    
    echo
    show_connection_info
}

################################################################################
# Изменение AD Tag
################################################################################

change_ad_tag() {
    print_header "Изменение AD Tag"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Файл конфигурации не найден"
        return 1
    fi
    
    source "$CONFIG_FILE"
    
    if [ -n "$AD_TAG" ]; then
        echo "Текущий AD Tag: $AD_TAG"
    else
        echo "AD Tag не установлен"
    fi
    echo
    
    print_info "Получите AD Tag у @MTProxybot в Telegram"
    print_info "Или оставьте пустым для удаления"
    echo
    
    read -p "Введите новый AD Tag: " NEW_AD_TAG
    
    # Обновляем конфигурацию
    if [ -n "$NEW_AD_TAG" ]; then
        if grep -q "^AD_TAG=" "$CONFIG_FILE"; then
            sed -i "s/^AD_TAG=.*/AD_TAG=$NEW_AD_TAG/" "$CONFIG_FILE"
        else
            echo "AD_TAG=$NEW_AD_TAG" >> "$CONFIG_FILE"
        fi
        print_success "AD Tag установлен: $NEW_AD_TAG"
    else
        sed -i "s/^AD_TAG=.*/AD_TAG=/" "$CONFIG_FILE"
        print_success "AD Tag удален"
    fi
    
    # Загружаем обновленную конфигурацию
    source "$CONFIG_FILE"

    # Обновляем systemd сервис
    print_info "Обновление systemd сервиса..."

    CMD="/opt/MTProxy/objs/bin/mtproto-proxy"
    CMD="$CMD -u nobody"
    CMD="$CMD -p $STATS_PORT"
    CMD="$CMD -H $EXTERNAL_PORT"
    CMD="$CMD -S $SECRET"
    CMD="$CMD -M $WORKERS"

    if [ -n "$AD_TAG" ] && [ "$AD_TAG" != "пропустить" ]; then
        CMD="$CMD -P $AD_TAG"
    fi

    if [ "$USE_NAT" = "yes" ] && [ -n "$NAT_IP" ] && [ -n "$NAT_LOCAL_IP" ]; then
        CMD="$CMD --nat-info $NAT_LOCAL_IP:$NAT_IP"
    fi

    if [ "$USE_DOMAIN" = "yes" ] && [ -n "${TLS_DOMAIN:-$DOMAIN_NAME}" ]; then
        CMD="$CMD -D ${TLS_DOMAIN:-$DOMAIN_NAME}"
    fi

    CMD="$CMD --aes-pwd /opt/MTProxy/run/proxy-secret /opt/MTProxy/run/proxy-multi.conf"

    sed -i "s|^ExecStart=.*|ExecStart=$CMD|" "/etc/systemd/system/$SERVICE_NAME.service"
    systemctl daemon-reload

    restart_service
}

################################################################################
# Изменение портов
################################################################################

change_ports() {
    print_header "Изменение портов"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Файл конфигурации не найден"
        return 1
    fi
    
    source "$CONFIG_FILE"
    
    echo "Текущая конфигурация портов:"
    echo "  Внешний порт (клиенты):  $EXTERNAL_PORT"
    echo "  Порт статистики:         $STATS_PORT"
    echo
    
    read -p "Новый внешний порт [$EXTERNAL_PORT]: " NEW_EXTERNAL_PORT
    NEW_EXTERNAL_PORT=${NEW_EXTERNAL_PORT:-$EXTERNAL_PORT}
    
    read -p "Новый порт статистики [$STATS_PORT]: " NEW_STATS_PORT
    NEW_STATS_PORT=${NEW_STATS_PORT:-$STATS_PORT}
    
    # Обновляем конфигурацию
    sed -i "s/^EXTERNAL_PORT=.*/EXTERNAL_PORT=$NEW_EXTERNAL_PORT/" "$CONFIG_FILE"
    sed -i "s/^STATS_PORT=.*/STATS_PORT=$NEW_STATS_PORT/" "$CONFIG_FILE"
    
    print_success "Порты обновлены"
    
    # Обновляем systemd сервис
    print_info "Обновление systemd сервиса..."
    
    source "$CONFIG_FILE"
    
    CMD="/opt/MTProxy/objs/bin/mtproto-proxy"
    CMD="$CMD -u nobody"
    CMD="$CMD -p $STATS_PORT"
    CMD="$CMD -H $EXTERNAL_PORT"
    CMD="$CMD -S $SECRET"
    CMD="$CMD -M $WORKERS"

    if [ -n "$AD_TAG" ] && [ "$AD_TAG" != "пропустить" ]; then
        CMD="$CMD -P $AD_TAG"
    fi

    if [ "$USE_NAT" = "yes" ] && [ -n "$NAT_IP" ] && [ -n "$NAT_LOCAL_IP" ]; then
        CMD="$CMD --nat-info $NAT_LOCAL_IP:$NAT_IP"
    fi

    if [ "$USE_DOMAIN" = "yes" ] && [ -n "${TLS_DOMAIN:-$DOMAIN_NAME}" ]; then
        CMD="$CMD -D ${TLS_DOMAIN:-$DOMAIN_NAME}"
    fi

    CMD="$CMD --aes-pwd /opt/MTProxy/run/proxy-secret /opt/MTProxy/run/proxy-multi.conf"

    sed -i "s|^ExecStart=.*|ExecStart=$CMD|" "/etc/systemd/system/$SERVICE_NAME.service"
    systemctl daemon-reload

    restart_service

    echo
    show_connection_info
}

################################################################################
# Изменение количества воркеров
################################################################################

change_workers() {
    print_header "Изменение количества воркеров"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Файл конфигурации не найден"
        return 1
    fi
    
    source "$CONFIG_FILE"
    
    CPU_CORES=$(nproc)
    
    echo "Текущее количество воркеров: $WORKERS"
    echo "Доступно CPU ядер: $CPU_CORES"
    echo
    
    read -p "Новое количество воркеров [$WORKERS]: " NEW_WORKERS
    NEW_WORKERS=${NEW_WORKERS:-$WORKERS}
    
    # Обновляем конфигурацию
    sed -i "s/^WORKERS=.*/WORKERS=$NEW_WORKERS/" "$CONFIG_FILE"
    
    print_success "Количество воркеров обновлено: $NEW_WORKERS"

    # Обновляем systemd сервис
    print_info "Обновление systemd сервиса..."

    source "$CONFIG_FILE"

    CMD="/opt/MTProxy/objs/bin/mtproto-proxy"
    CMD="$CMD -u nobody"
    CMD="$CMD -p $STATS_PORT"
    CMD="$CMD -H $EXTERNAL_PORT"
    CMD="$CMD -S $SECRET"
    CMD="$CMD -M $WORKERS"

    if [ -n "$AD_TAG" ] && [ "$AD_TAG" != "пропустить" ]; then
        CMD="$CMD -P $AD_TAG"
    fi

    if [ "$USE_NAT" = "yes" ] && [ -n "$NAT_IP" ] && [ -n "$NAT_LOCAL_IP" ]; then
        CMD="$CMD --nat-info $NAT_LOCAL_IP:$NAT_IP"
    fi

    if [ "$USE_DOMAIN" = "yes" ] && [ -n "${TLS_DOMAIN:-$DOMAIN_NAME}" ]; then
        CMD="$CMD -D ${TLS_DOMAIN:-$DOMAIN_NAME}"
    fi

    CMD="$CMD --aes-pwd /opt/MTProxy/run/proxy-secret /opt/MTProxy/run/proxy-multi.conf"

    sed -i "s|^ExecStart=.*|ExecStart=$CMD|" "/etc/systemd/system/$SERVICE_NAME.service"
    systemctl daemon-reload

    restart_service
}

################################################################################
# Переустановка
################################################################################

rebuild_binary() {
    print_header "Пересборка MTProxy"
    
    print_warning "Будет выполнена пересборка бинарного файла из исходников"
    echo
    read -p "Продолжить? [y/N]: " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Отмена"
        return
    fi
    
    # Останавливаем сервис
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_info "Остановка сервиса..."
        systemctl stop "$SERVICE_NAME"
    fi
    
    cd "$INSTALL_DIR" || exit 1
    
    # Обновляем исходники
    print_info "Обновление исходников из репозитория..."
    git fetch origin
    git reset --hard origin/master
    
    # Чистим старые объектные файлы
    print_info "Очистка старых объектных файлов..."
    make clean
    
    # Компилируем заново
    print_info "Компиляция MTProxy..."
    make -j$(nproc)
    
    if [ ! -f "objs/bin/mtproto-proxy" ]; then
        print_error "Ошибка компиляции"
        return 1
    fi
    
    print_success "MTProxy успешно пересобран"
    
    # Запускаем сервис
    print_info "Запуск сервиса..."
    systemctl start "$SERVICE_NAME"
    
    sleep 2
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "Сервис запущен"
    else
        print_error "Ошибка запуска сервиса"
        print_info "Логи: journalctl -u $SERVICE_NAME -n 50"
    fi
}

################################################################################
# Удаление
################################################################################

uninstall() {
    print_header "Удаление MTProxy"
    
    print_warning "ВНИМАНИЕ! Будут удалены:"
    echo "  • Systemd сервис"
    echo "  • Все файлы из $INSTALL_DIR"
    echo "  • Cron задача обновления конфигурации"
    echo
    read -p "Вы уверены? [y/N]: " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Отмена"
        return
    fi
    
    # Останавливаем и удаляем сервис
    if systemctl list-unit-files | grep -q "^$SERVICE_NAME.service"; then
        print_info "Остановка и удаление сервиса..."
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        rm -f "/etc/systemd/system/$SERVICE_NAME.service"
        systemctl daemon-reload
        print_success "Сервис удален"
    fi
    
    # Удаляем cron задачу
    if crontab -l 2>/dev/null | grep -q "update-configs.sh"; then
        print_info "Удаление cron задачи..."
        crontab -l | grep -v "update-configs.sh" | crontab -
        print_success "Cron задача удалена"
    fi
    
    # Удаляем симлинк
    if [ -L /usr/local/bin/mtproxy ]; then
        print_info "Удаление симлинка /usr/local/bin/mtproxy..."
        rm -f /usr/local/bin/mtproxy
        print_success "Симлинк удален"
    fi

    # Удаляем файлы
    if [ -d "$INSTALL_DIR" ]; then
        print_info "Удаление файлов..."
        rm -rf "$INSTALL_DIR"
        print_success "Файлы удалены"
    fi
    
    echo
    print_success "MTProxy полностью удален"
}

################################################################################
# Интеграция с Remnawave
################################################################################

run_remnawave_integration() {
    print_header "Интеграция с Remnawave (Nginx SNI)"

    local INTEGRATION_SCRIPT="$INSTALL_DIR/setup_remnawave_integration.sh"

    if [ ! -f "$INTEGRATION_SCRIPT" ]; then
        print_error "Скрипт интеграции не найден: $INTEGRATION_SCRIPT"
        print_info "Скопируйте setup_remnawave_integration.sh в $INSTALL_DIR/ и повторите"
        return 1
    fi

    if [ "$EUID" -ne 0 ]; then
        print_error "Интеграция требует прав root"
        print_info "Запустите: sudo mtproxy  или  sudo bash $INTEGRATION_SCRIPT"
        return 1
    fi

    bash "$INTEGRATION_SCRIPT"
}

################################################################################
# Меню конфигурации
################################################################################

config_menu() {
    while true; do
        print_header "Конфигурация MTProxy"
        
        echo "1) Изменить секрет"
        echo "2) Изменить AD Tag"
        echo "3) Изменить порты"
        echo "4) Изменить количество воркеров"
        echo "5) Показать текущую конфигурацию"
        echo "0) Назад"
        echo
        read -p "Выберите действие: " choice
        
        case $choice in
            1) change_secret ;;
            2) change_ad_tag ;;
            3) change_ports ;;
            4) change_workers ;;
            5) show_connection_info ;;
            0) break ;;
            *) print_error "Неверный выбор" ;;
        esac
        
        echo
        read -p "Нажмите Enter для продолжения..."
    done
}

################################################################################
# Главное меню
################################################################################

show_menu() {
    while true; do
        clear
        echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}          MTProxy Official - Управление${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
        echo
        
        # Статус сервиса
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            echo -e "Статус: ${GREEN}● Работает${NC}"
        else
            echo -e "Статус: ${RED}○ Остановлен${NC}"
        fi
        
        echo
        echo "═══════════════════════════════════════════════════════════"
        echo " УПРАВЛЕНИЕ СЕРВИСОМ"
        echo "═══════════════════════════════════════════════════════════"
        echo "  1) Запустить MTProxy"
        echo "  2) Остановить MTProxy"
        echo "  3) Перезапустить MTProxy"
        echo "  4) Статус сервиса"
        echo "  5) Просмотр логов"
        echo "  6) Следить за логами (live)"
        echo
        echo "═══════════════════════════════════════════════════════════"
        echo " ИНФОРМАЦИЯ И СТАТИСТИКА"
        echo "═══════════════════════════════════════════════════════════"
        echo "  7) Показать ссылку для подключения"
        echo "  8) Статистика прокси"
        echo
        echo "═══════════════════════════════════════════════════════════"
        echo " НАСТРОЙКА"
        echo "═══════════════════════════════════════════════════════════"
        echo "  9) Конфигурация (секрет, порты, AD Tag...)"
        echo " 10) Обновить конфигурацию Telegram"
        echo
        echo "═══════════════════════════════════════════════════════════"
        echo " ОБСЛУЖИВАНИЕ"
        echo "═══════════════════════════════════════════════════════════"
        echo " 11) Пересобрать MTProxy"
        echo " 12) Удалить MTProxy"
        echo
        echo "═══════════════════════════════════════════════════════════"
        echo " ИНТЕГРАЦИЯ"
        echo "═══════════════════════════════════════════════════════════"
        echo " 13) Настроить интеграцию с Remnawave (Nginx SNI)"
        echo
        echo "  0) Выход"
        echo
        echo "═══════════════════════════════════════════════════════════"
        read -p "Выберите действие: " choice
        
        case $choice in
            1) start_service ;;
            2) stop_service ;;
            3) restart_service ;;
            4) show_status ;;
            5) show_logs ;;
            6) follow_logs ;;
            7) show_connection_info ;;
            8) show_stats ;;
            9) config_menu ;;
            10) update_telegram_config ;;
            11) rebuild_binary ;;
            12) uninstall; break ;;
            13) run_remnawave_integration ;;
            0) break ;;
            *) print_error "Неверный выбор" ;;
        esac
        
        if [ "$choice" != "6" ]; then
            echo
            read -p "Нажмите Enter для продолжения..."
        fi
    done
}

################################################################################
# Обработка аргументов командной строки
################################################################################

if [ $# -eq 0 ]; then
    # Проверка установки
    check_installation
    
    # Интерактивное меню
    show_menu
else
    # Проверка установки для всех команд кроме help
    if [ "$1" != "help" ] && [ "$1" != "--help" ] && [ "$1" != "-h" ]; then
        check_installation
    fi
    
    # Обработка команд
    case "$1" in
        start)
            start_service
            ;;
        stop)
            stop_service
            ;;
        restart)
            restart_service
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs
            ;;
        follow-logs)
            follow_logs
            ;;
        stats)
            show_stats
            ;;
        info)
            show_connection_info
            ;;
        update-config)
            update_telegram_config
            ;;
        change-secret)
            change_secret
            ;;
        change-ad-tag)
            change_ad_tag
            ;;
        change-ports)
            change_ports
            ;;
        change-workers)
            change_workers
            ;;
        rebuild)
            rebuild_binary
            ;;
        setup-remnawave)
            run_remnawave_integration
            ;;
        uninstall)
            uninstall
            ;;
        help|--help|-h)
            echo "MTProxy Official - Управление"
            echo
            echo "Использование: bash $0 [команда]"
            echo
            echo "Команды:"
            echo "  start            - Запустить MTProxy"
            echo "  stop             - Остановить MTProxy"
            echo "  restart          - Перезапустить MTProxy"
            echo "  status           - Показать статус"
            echo "  logs             - Показать логи"
            echo "  follow-logs      - Следить за логами (live)"
            echo "  stats            - Показать статистику"
            echo "  info             - Показать информацию для подключения"
            echo "  update-config    - Обновить конфигурацию Telegram"
            echo "  change-secret    - Изменить секрет"
            echo "  change-ad-tag    - Изменить AD Tag"
            echo "  change-ports     - Изменить порты"
            echo "  change-workers   - Изменить количество воркеров"
            echo "  rebuild          - Пересобрать MTProxy"
            echo "  setup-remnawave  - Настроить интеграцию с Remnawave (Nginx SNI)"
            echo "  uninstall        - Удалить MTProxy"
            echo "  help             - Показать эту справку"
            echo
            echo "Без аргументов запускается интерактивное меню"
            ;;
        *)
            print_error "Неизвестная команда: $1"
            echo "Используйте: bash $0 help"
            exit 1
            ;;
    esac
fi
