#!/bin/bash
# modules/lib_install.sh
# Функции полного установочного pipeline MTProxy.
# Зависимость: lib_common.sh должен быть подключён первым.

[[ -n "${_LIB_INSTALL_LOADED:-}" ]] && return 0
_LIB_INSTALL_LOADED=1

# shellcheck source=modules/lib_common.sh
[[ -z "${_LIB_COMMON_LOADED:-}" ]] && source "$(dirname "${BASH_SOURCE[0]}")/lib_common.sh"

################################################################################
# Зависимости
################################################################################

install_dependencies() {
    print_header "Проверка зависимостей"
    print_info "Проверка необходимых инструментов..."

    local ALL_OK=true
    local MISSING_PACKAGES=""

    if ! command -v git &>/dev/null; then
        print_warning "git не найден"
        MISSING_PACKAGES="$MISSING_PACKAGES git"
        ALL_OK=false
    else
        print_success "git установлен"
    fi

    if ! command -v curl &>/dev/null; then
        print_warning "curl не найден"
        MISSING_PACKAGES="$MISSING_PACKAGES curl"
        ALL_OK=false
    else
        print_success "curl установлен"
    fi

    if ! command -v make &>/dev/null; then
        print_warning "make не найден"
        MISSING_PACKAGES="$MISSING_PACKAGES build-essential"
        ALL_OK=false
    else
        print_success "make установлен"
    fi

    if ! command -v gcc &>/dev/null; then
        print_warning "gcc не найден"
        MISSING_PACKAGES="$MISSING_PACKAGES build-essential"
        ALL_OK=false
    else
        print_success "gcc установлен"
    fi

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

    if ! command -v xxd &>/dev/null; then
        print_warning "xxd не найден"
        MISSING_PACKAGES="$MISSING_PACKAGES xxd"
        ALL_OK=false
    else
        print_success "xxd установлен"
    fi

    if [ "$ALL_OK" = false ]; then
        echo
        print_warning "Обнаружены отсутствующие зависимости"
        print_info "Попытка установки:$MISSING_PACKAGES"
        echo
        apt-get update -qq 2>/dev/null || true
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

    echo
    print_info "Финальная проверка критичных инструментов..."

    if ! command -v git &>/dev/null; then
        print_error "Git не установлен. Установка невозможна."
        echo "Выполните вручную: sudo apt-get install git"
        exit 1
    fi

    if ! command -v make &>/dev/null || ! command -v gcc &>/dev/null; then
        print_error "Компилятор (gcc/make) не установлен. Установка невозможна."
        echo "Выполните вручную: sudo apt-get install build-essential"
        exit 1
    fi

    if ! command -v curl &>/dev/null; then
        print_error "curl не установлен. Установка невозможна."
        echo "Выполните вручную: sudo apt-get install curl"
        exit 1
    fi

    print_success "Все необходимые инструменты доступны!"
}

################################################################################
# Клонирование и сборка
################################################################################

clone_and_build_mtproxy() {
    print_header "Клонирование и сборка MTProxy"

    if [ -d "$INSTALL_DIR" ]; then
        print_warning "Обнаружена существующая установка в $INSTALL_DIR"

        if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            print_info "Остановка существующего сервиса..."
            systemctl stop "$SERVICE_NAME"
        fi

        if [ -f "$CONFIG_FILE" ]; then
            # Бекап вне INSTALL_DIR — иначе rm -rf удалит его вместе с директорией
            local backup="/root/.mtproxy.env.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$CONFIG_FILE" "$backup"
            print_success "Конфигурация сохранена: $backup"
        fi

        print_info "Удаление старой установки..."
        rm -rf "$INSTALL_DIR"
    fi

    print_info "Клонирование официального репозитория Telegram..."
    git clone "$MTPROXY_REPO" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    print_success "Репозиторий клонирован"

    print_info "Компиляция MTProxy (может занять несколько минут)..."
    make -j"$(nproc)"

    if [ ! -f "$MTPROXY_BINARY" ]; then
        print_error "Ошибка компиляции: бинарный файл не создан"
        exit 1
    fi

    print_success "MTProxy успешно скомпилирован"
    mkdir -p "$MTPROXY_RUN_DIR"
}

################################################################################
# Копирование модулей и менеджера в INSTALL_DIR
################################################################################

# Вызывать ПОСЛЕ clone_and_build_mtproxy (она пересоздаёт INSTALL_DIR).
# src_dir — директория, где лежат modules/ и manage_mtproxy_official.sh.
copy_modules() {
    local src_dir="$1"

    print_header "Установка модулей управления"

    if [ -d "$src_dir/modules" ]; then
        mkdir -p "$INSTALL_DIR/modules"
        cp "$src_dir/modules/"*.sh "$INSTALL_DIR/modules/"
        chmod +x "$INSTALL_DIR/modules/"*.sh
        print_success "Модули скопированы: $INSTALL_DIR/modules/"
    else
        print_warning "Директория модулей не найдена: $src_dir/modules"
    fi

    if [ -f "$src_dir/manage_mtproxy_official.sh" ]; then
        cp "$src_dir/manage_mtproxy_official.sh" "$INSTALL_DIR/manage_mtproxy_official.sh"
        chmod +x "$INSTALL_DIR/manage_mtproxy_official.sh"
        print_success "Менеджер установлен: $INSTALL_DIR/manage_mtproxy_official.sh"
    else
        print_warning "Скрипт менеджера не найден: $src_dir/manage_mtproxy_official.sh"
    fi

    # Симлинки для быстрого доступа из любой директории
    ln -sf "$INSTALL_DIR/manage_mtproxy_official.sh" /usr/local/bin/mtproxy
    ln -sf "$INSTALL_DIR/manage_mtproxy_official.sh" /usr/local/bin/MTProxy
    print_success "Симлинки созданы: mtproxy и MTProxy → $INSTALL_DIR/manage_mtproxy_official.sh"
    print_info "Управление MTProxy: mtproxy  или  MTProxy"
}

################################################################################
# Конфигурация Telegram
################################################################################

download_telegram_configs() {
    print_header "Получение конфигурации Telegram"

    cd "$MTPROXY_RUN_DIR"

    print_info "Загрузка proxy-secret..."
    curl -s https://core.telegram.org/getProxySecret -o proxy-secret
    if [ ! -s "proxy-secret" ]; then
        print_error "Не удалось загрузить proxy-secret"
        exit 1
    fi
    print_success "proxy-secret получен"

    print_info "Загрузка proxy-multi.conf..."
    curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf
    if [ ! -s "proxy-multi.conf" ]; then
        print_error "Не удалось загрузить proxy-multi.conf"
        exit 1
    fi
    print_success "proxy-multi.conf получен"

    print_info "Эти файлы рекомендуется обновлять раз в день"
}

################################################################################
# Systemd сервис
################################################################################

create_systemd_service() {
    print_header "Создание systemd сервиса"

    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    # MTProxy C-код требует PID < 65536 (assert в common/pid.c)
    print_info "Применение воркараунда PID: kernel.pid_max=65535..."
    sysctl -w kernel.pid_max=65535
    echo "kernel.pid_max = 65535" > /etc/sysctl.d/99-mtproxy-pid.conf
    print_success "kernel.pid_max=65535 установлен"

    # Формируем ExecStart через lib_common::build_cmd
    build_cmd

    cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=MTProxy - Official Telegram MTProto Proxy
After=network.target
Documentation=https://github.com/TelegramMessenger/MTProxy

[Service]
Type=simple
WorkingDirectory=$MTPROXY_RUN_DIR
# MTProxy C-код требует PID < 65536 (assert в common/pid.c)
ExecStartPre=/sbin/sysctl -w kernel.pid_max=65535
ExecStartPre=/bin/bash -c 'curl -s https://core.telegram.org/getProxySecret -o $MTPROXY_RUN_DIR/proxy-secret'
ExecStartPre=/bin/bash -c 'curl -s https://core.telegram.org/getProxyConfig -o $MTPROXY_RUN_DIR/proxy-multi.conf'
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
ReadWritePaths=$MTPROXY_RUN_DIR

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    print_success "Systemd сервис создан и перезагружен"

    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow "${EXTERNAL_PORT}/tcp" >/dev/null 2>&1
        print_success "UFW: порт $EXTERNAL_PORT/tcp открыт"
    else
        print_info "UFW не активен. Откройте порт вручную: sudo ufw allow $EXTERNAL_PORT/tcp"
    fi
}

################################################################################
# Автообновление конфигурации (cron)
################################################################################

setup_config_updater() {
    print_header "Настройка автообновления конфигурации Telegram"

    cat > "$INSTALL_DIR/update-configs.sh" << 'UPDATER'
#!/bin/bash
# Автоматическое обновление конфигурации Telegram
cd /opt/MTProxy/run

curl -s https://core.telegram.org/getProxySecret -o proxy-secret.new
curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf.new

if [ -s proxy-secret.new ] && [ -s proxy-multi.conf.new ]; then
    mv proxy-secret.new proxy-secret
    mv proxy-multi.conf.new proxy-multi.conf
    systemctl restart mtproxy
    logger "MTProxy configs updated successfully"
else
    logger "MTProxy configs update failed"
    rm -f proxy-secret.new proxy-multi.conf.new
fi
UPDATER

    chmod +x "$INSTALL_DIR/update-configs.sh"
    print_success "Скрипт обновления создан"

    # Обновляет proxy-secret и proxy-multi.conf и перезапускает сервис.
    # Раз в сутки — рекомендация Telegram для получения свежих
    # IP-адресов ядра Telegram (из proxy-multi.conf).
    local cron_cmd="0 3 * * * $INSTALL_DIR/update-configs.sh >/dev/null 2>&1"
    if crontab -l 2>/dev/null | grep -q "update-configs.sh"; then
        print_info "Cron задача уже существует"
    else
        (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
        print_success "Cron задача добавлена (обновление в 3:00 каждый день)"
    fi
}

################################################################################
# Запуск и проверка
################################################################################

start_and_verify() {
    print_header "Запуск MTProxy"

    systemctl enable "$SERVICE_NAME"
    print_success "Автозапуск включен"

    systemctl start "$SERVICE_NAME"
    sleep 3

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "MTProxy успешно запущен!"
    else
        print_error "Ошибка запуска MTProxy"
        echo
        print_info "Просмотр логов: journalctl -u $SERVICE_NAME -n 50"
        systemctl status "$SERVICE_NAME" --no-pager
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    echo
    print_info "Проверка портов..."

    if ss -tuln 2>/dev/null | grep -q ":$EXTERNAL_PORT " || \
       netstat -tuln 2>/dev/null | grep -q ":$EXTERNAL_PORT "; then
        print_success "Порт $EXTERNAL_PORT слушается"
    else
        print_warning "Порт $EXTERNAL_PORT не прослушивается (сервис может ещё стартовать)"
    fi

    if ss -tuln 2>/dev/null | grep -q "127.0.0.1:$STATS_PORT" || \
       netstat -tuln 2>/dev/null | grep -q "127.0.0.1:$STATS_PORT"; then
        print_success "Порт статистики $STATS_PORT доступен"
    fi
}

################################################################################
# Итоговая информация
################################################################################

print_connection_info() {
    print_header "УСТАНОВКА ЗАВЕРШЕНА"

    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    get_server_addr    # → $SERVER_ADDR  (lib_common)
    get_client_secret  # → $CLIENT_SECRET (lib_common)

    local proxy_link="tg://proxy?server=$SERVER_ADDR&port=$EXTERNAL_PORT&secret=$CLIENT_SECRET"

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
    if [ "${USE_DOMAIN:-no}" = "yes" ] && [ -n "$TLS_DOMAIN" ]; then
        echo "   SNI домен:  $TLS_DOMAIN"
    fi
    echo
    echo -e "${CYAN}🔗 ССЫЛКА ДЛЯ ПОДКЛЮЧЕНИЯ:${NC}"
    echo "═══════════════════════════════════════════════════════════"
    echo "$proxy_link"
    echo "═══════════════════════════════════════════════════════════"
    echo
    echo -e "${YELLOW}🤖 РЕГИСТРАЦИЯ В @MTProxybot:${NC}"
    echo "   Секрет для бота: $SECRET"
    print_info "Голый секрет (без ee/dd-префикса) — используйте при регистрации в @MTProxybot"
    echo
    echo -e "${CYAN}📱 ИНСТРУКЦИЯ:${NC}"
    echo "   1. Откройте ссылку на устройстве с Telegram"
    echo "   2. Нажмите 'Connect Proxy'"
    echo "   3. Прокси автоматически добавится"
    echo
    echo -e "${CYAN}🛠 УПРАВЛЕНИЕ:${NC}"
    echo "   Менеджер:   mtproxy"
    echo "   Статус:     systemctl status $SERVICE_NAME"
    echo "   Логи:       journalctl -u $SERVICE_NAME -f"
    echo "   Статистика: curl http://127.0.0.1:$STATS_PORT/stats"
    echo
    echo -e "${CYAN}📁 ФАЙЛЫ:${NC}"
    echo "   Конфигурация: $CONFIG_FILE"
    echo "   Бинарник:     $MTPROXY_BINARY"
    echo "   Рабочая папка: $MTPROXY_RUN_DIR"
    echo "   Service:      /etc/systemd/system/$SERVICE_NAME.service"
    echo

    # Сохраняем ссылку в файл
    cat > "$INSTALL_DIR/proxy_link.txt" << EOF
MTProxy Connection Link
═══════════════════════════════════════════════════════════

Server:  $SERVER_ADDR
Port:    $EXTERNAL_PORT

Connection Link:
$proxy_link

═══════════════════════════════════════════════════════════
Секрет для @MTProxybot: $SECRET
Generated: $(date)
EOF

    print_success "Ссылка сохранена: $INSTALL_DIR/proxy_link.txt"
    echo
}

################################################################################
# Точка входа установки
################################################################################

# Главный оркестратор установки. Вызывается из install_official.sh или
# из manage_mtproxy_official.sh (команда install).
# $1 — директория с modules/ и manage_mtproxy_official.sh (исходник для копирования).
#      По умолчанию: родительская директория данного модуля.
run_install() {
    local src_dir="${1:-$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")}"

    clear
    print_header "MTProxy Official - Установка"
    echo -e "${CYAN}Официальная реализация от Telegram (C)${NC}"
    echo -e "${CYAN}Система: Ubuntu 20.04+${NC}"
    echo

    install_dependencies
    clone_and_build_mtproxy
    copy_modules "$src_dir"
    download_telegram_configs
    interactive_configuration    # определена в lib_config.sh
    create_systemd_service
    setup_config_updater
    start_and_verify
    print_connection_info

    echo
    print_success "Установка успешно завершена!"
    echo
}
