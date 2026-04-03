#!/bin/bash
# modules/lib_service.sh
# Управление жизненным циклом MTProxy-сервиса:
# запуск, остановка, перезапуск, статус, логи, статистика,
# обновление конфигурационных файлов Telegram.
# Зависимость: lib_common.sh

[[ -n "${_LIB_SERVICE_LOADED:-}" ]] && return 0
_LIB_SERVICE_LOADED=1

# shellcheck source=modules/lib_common.sh
[[ -z "${_LIB_COMMON_LOADED:-}" ]] && source "$(dirname "${BASH_SOURCE[0]}")/lib_common.sh"

################################################################################
# Запуск / Остановка / Перезапуск
################################################################################

start_service() {
    print_header "Запуск MTProxy"

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_warning "Сервис уже запущен"
        return 0
    fi

    systemctl start "$SERVICE_NAME"
    sleep 2

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "MTProxy успешно запущен"
    else
        print_error "Не удалось запустить MTProxy"
        print_info "Логи: journalctl -u $SERVICE_NAME -n 50"
        return 1
    fi
}

stop_service() {
    print_header "Остановка MTProxy"

    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        print_warning "Сервис уже остановлен"
        return 0
    fi

    systemctl stop "$SERVICE_NAME"
    sleep 2

    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "MTProxy остановлен"
    else
        print_error "Не удалось остановить MTProxy"
        return 1
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
        return 1
    fi
}

################################################################################
# Статус
################################################################################

show_status() {
    print_header "Статус MTProxy"

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}● $SERVICE_NAME.service — активен и работает${NC}"
    else
        echo -e "${RED}● $SERVICE_NAME.service — остановлен или неактивен${NC}"
    fi

    echo
    systemctl status "$SERVICE_NAME" --no-pager -l

    echo
    print_info "Подробные логи: journalctl -u $SERVICE_NAME -n 50"
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
    print_info "Логи в реальном времени: journalctl -u $SERVICE_NAME -f"
}

follow_logs() {
    print_header "Логи MTProxy (в реальном времени)"
    echo "Нажмите Ctrl+C для выхода"
    echo
    journalctl -u "$SERVICE_NAME" -f
}

################################################################################
# Статистика
################################################################################

show_stats() {
    print_header "Статистика MTProxy"

    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Файл конфигурации не найден: $CONFIG_FILE"
        return 1
    fi

    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    local stats_port="${STATS_PORT:-8888}"

    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        print_error "Сервис не запущен"
        return 1
    fi

    if ! command -v curl &>/dev/null; then
        print_error "curl не установлен"
        return 1
    fi

    echo "Получение статистики с http://127.0.0.1:$stats_port/stats ..."
    echo

    local stats
    stats=$(curl -s --max-time 5 "http://127.0.0.1:$stats_port/stats" 2>/dev/null)

    if [ -n "$stats" ]; then
        echo "$stats"
    else
        print_error "Не удалось получить статистику"
        print_info "Убедитесь, что сервис запущен и порт $stats_port доступен"
    fi

    echo
    print_info "Обновить вручную: curl http://127.0.0.1:$stats_port/stats"
}

################################################################################
# Обновление конфигурации Telegram
################################################################################

update_telegram_config() {
    print_header "Обновление конфигурации Telegram"

    local run_dir="$MTPROXY_RUN_DIR"

    if [ ! -d "$run_dir" ]; then
        print_error "Директория не найдена: $run_dir"
        return 1
    fi

    print_info "Загрузка proxy-secret..."
    if curl -s --max-time 30 https://core.telegram.org/getProxySecret \
            -o "$run_dir/proxy-secret.new" && [ -s "$run_dir/proxy-secret.new" ]; then
        mv "$run_dir/proxy-secret.new" "$run_dir/proxy-secret"
        print_success "proxy-secret обновлён"
    else
        rm -f "$run_dir/proxy-secret.new"
        print_error "Не удалось загрузить proxy-secret"
        return 1
    fi

    print_info "Загрузка proxy-multi.conf..."
    if curl -s --max-time 30 https://core.telegram.org/getProxyConfig \
            -o "$run_dir/proxy-multi.conf.new" && [ -s "$run_dir/proxy-multi.conf.new" ]; then
        mv "$run_dir/proxy-multi.conf.new" "$run_dir/proxy-multi.conf"
        print_success "proxy-multi.conf обновлён"
    else
        rm -f "$run_dir/proxy-multi.conf.new"
        print_error "Не удалось загрузить proxy-multi.conf"
        return 1
    fi

    print_success "Конфигурация Telegram обновлена"

    echo
    if read_yes_no "Перезапустить MTProxy для применения изменений?" "y"; then
        restart_service
    fi
}
