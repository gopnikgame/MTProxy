#!/bin/bash
# modules/lib_manage.sh
# Изменение параметров MTProxy, пересборка и удаление.
# Зависимости: lib_common.sh, lib_service.sh, lib_config.sh

[[ -n "${_LIB_MANAGE_LOADED:-}" ]] && return 0
_LIB_MANAGE_LOADED=1

# shellcheck source=modules/lib_common.sh
[[ -z "${_LIB_COMMON_LOADED:-}" ]]  && source "$(dirname "${BASH_SOURCE[0]}")/lib_common.sh"
# shellcheck source=modules/lib_service.sh
[[ -z "${_LIB_SERVICE_LOADED:-}" ]] && source "$(dirname "${BASH_SOURCE[0]}")/lib_service.sh"
# shellcheck source=modules/lib_config.sh
[[ -z "${_LIB_CONFIG_LOADED:-}" ]]  && source "$(dirname "${BASH_SOURCE[0]}")/lib_config.sh"

################################################################################
# Вспомогательная функция: обновить .env, service, перезапустить
################################################################################

# Применяет изменённую конфигурацию:
#   1. Перезагружает .env
#   2. Строит ExecStart через build_cmd()
#   3. Вписывает его в service-файл через apply_cmd_to_service()
#   4. Перезапускает сервис через restart_service()
_apply_config_changes() {
    print_info "Обновление systemd сервиса..."
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    build_cmd
    apply_cmd_to_service
    restart_service
}

################################################################################
# Изменение секрета
################################################################################

change_secret() {
    print_header "Изменение секрета"

    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Файл конфигурации не найден: $CONFIG_FILE"
        return 1
    fi
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    echo "Текущий секрет: ${DISPLAY_SECRET:-$SECRET}"
    echo
    echo "1) Сгенерировать новый секрет"
    echo "2) Ввести секрет вручную"
    echo "0) Отмена"
    echo
    read -p "Выберите действие: " choice

    local new_secret
    case $choice in
        1)
            new_secret=$(head -c 16 /dev/urandom | xxd -ps)
            print_success "Новый секрет сгенерирован: $new_secret"
            ;;
        2)
            read -p "Введите новый секрет (32 hex символа): " new_secret
            if [ ${#new_secret} -ne 32 ]; then
                print_error "Секрет должен содержать ровно 32 hex-символа"
                return 1
            fi
            ;;
        0|*)
            print_info "Отмена"
            return 0
            ;;
    esac

    echo
    local new_display new_dd
    if [ "${USE_DOMAIN:-no}" = "yes" ]; then
        # TLS-режим: dd-префикс несовместим с fakeTLS-рукопожатием
        new_display="ee$new_secret"
        new_dd="no"
        print_info "Random Padding отключён (несовместим с TLS-режимом)"
    else
        if read_yes_no "Включить Random Padding (dd-префикс)?" "y"; then
            new_display="dd$new_secret"
            new_dd="yes"
        else
            new_display="$new_secret"
            new_dd="no"
        fi
    fi

    sed -i "s/^SECRET=.*/SECRET=$new_secret/"               "$CONFIG_FILE"
    sed -i "s/^USE_DD_PREFIX=.*/USE_DD_PREFIX=$new_dd/"     "$CONFIG_FILE"
    sed -i "s/^DISPLAY_SECRET=.*/DISPLAY_SECRET=$new_display/" "$CONFIG_FILE"
    echo "$new_secret" > "$MTPROXY_RUN_DIR/secret.txt"

    print_success "Секрет обновлён: $new_display"

    _apply_config_changes

    echo
    show_connection_info
}

################################################################################
# Изменение AD Tag
################################################################################

change_ad_tag() {
    print_header "Изменение AD Tag"

    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Файл конфигурации не найден: $CONFIG_FILE"
        return 1
    fi
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    if [ -n "${AD_TAG:-}" ]; then
        echo "Текущий AD Tag: $AD_TAG"
    else
        echo "AD Tag не установлен"
    fi
    echo
    print_info "Получите AD Tag у @MTProxybot в Telegram"
    print_info "Оставьте пустым для удаления"
    echo
    read -p "Введите новый AD Tag: " new_tag

    if [ -n "$new_tag" ]; then
        if grep -q "^AD_TAG=" "$CONFIG_FILE"; then
            sed -i "s/^AD_TAG=.*/AD_TAG=$new_tag/" "$CONFIG_FILE"
        else
            echo "AD_TAG=$new_tag" >> "$CONFIG_FILE"
        fi
        print_success "AD Tag установлен: $new_tag"
    else
        sed -i "s/^AD_TAG=.*/AD_TAG=/" "$CONFIG_FILE"
        print_success "AD Tag удалён"
    fi

    _apply_config_changes
}

################################################################################
# Изменение портов
################################################################################

change_ports() {
    print_header "Изменение портов"

    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Файл конфигурации не найден: $CONFIG_FILE"
        return 1
    fi
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    echo "Текущая конфигурация портов:"
    echo "  Внешний порт (клиенты): $EXTERNAL_PORT"
    echo "  Порт статистики:        $STATS_PORT"
    echo

    local old_ext="$EXTERNAL_PORT"
    local new_ext new_stats

    _show_port_recommendations
    echo
    while true; do
        read -p "Новый внешний порт [$EXTERNAL_PORT]: " new_ext
        new_ext="${new_ext:-$EXTERNAL_PORT}"
        if [ "$new_ext" = "$old_ext" ] || is_port_available "$new_ext"; then
            break
        fi
        print_warning "Порт $new_ext уже занят, введите другой"
    done

    read -p "Новый порт статистики [$STATS_PORT]: " new_stats
    new_stats="${new_stats:-$STATS_PORT}"

    sed -i "s/^EXTERNAL_PORT=.*/EXTERNAL_PORT=$new_ext/"   "$CONFIG_FILE"
    sed -i "s/^STATS_PORT=.*/STATS_PORT=$new_stats/"       "$CONFIG_FILE"
    print_success "Порты обновлены: внешний=$new_ext статистика=$new_stats"

    # UFW: обновляем только если внешний порт изменился
    if [ "$new_ext" != "$old_ext" ]; then
        close_ufw_port "$old_ext"
        open_ufw_port  "$new_ext"
    fi

    _apply_config_changes

    echo
    show_connection_info
}

################################################################################
# Изменение количества воркеров
################################################################################

change_workers() {
    print_header "Изменение количества воркеров"

    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Файл конфигурации не найден: $CONFIG_FILE"
        return 1
    fi
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    local cpu_cores; cpu_cores=$(nproc)
    echo "Текущее количество воркеров: $WORKERS"
    echo "Доступно CPU ядер: $cpu_cores"
    echo
    read -p "Новое количество воркеров [$WORKERS]: " new_workers
    new_workers="${new_workers:-$WORKERS}"

    sed -i "s/^WORKERS=.*/WORKERS=$new_workers/" "$CONFIG_FILE"
    print_success "Количество воркеров обновлено: $new_workers"

    _apply_config_changes
}

################################################################################
# Пересборка бинарного файла
################################################################################

rebuild_binary() {
    print_header "Пересборка MTProxy"

    print_warning "Будет выполнена пересборка бинарного файла из исходников"
    echo
    if ! read_yes_no "Продолжить?" "n"; then
        print_info "Отмена"
        return 0
    fi

    # Останавливаем сервис перед пересборкой
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_info "Остановка сервиса..."
        systemctl stop "$SERVICE_NAME"
    fi

    cd "$INSTALL_DIR" || { print_error "Не удалось перейти в $INSTALL_DIR"; return 1; }

    print_info "Обновление исходников из репозитория..."
    git fetch origin
    git reset --hard origin/master

    print_info "Очистка старых объектных файлов..."
    make clean

    print_info "Компиляция MTProxy..."
    make -j"$(nproc)"

    if [ ! -f "$MTPROXY_BINARY" ]; then
        print_error "Ошибка компиляции: бинарный файл не создан"
        return 1
    fi

    print_success "MTProxy успешно пересобран"

    print_info "Запуск сервиса..."
    systemctl start "$SERVICE_NAME"
    sleep 2

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "Сервис запущен"
    else
        print_error "Ошибка запуска сервиса"
        print_info "Логи: journalctl -u $SERVICE_NAME -n 50"
        return 1
    fi
}

################################################################################
# Удаление MTProxy
################################################################################

uninstall() {
    print_header "Удаление MTProxy"

    print_warning "ВНИМАНИЕ! Будут удалены:"
    echo "  • Systemd сервис ($SERVICE_NAME)"
    echo "  • Все файлы из $INSTALL_DIR"
    echo "  • Cron задача обновления конфигурации"
    echo "  • Симлинки /usr/local/bin/mtproxy, /usr/local/bin/MTProxy"
    echo

    if ! read_yes_no "Вы уверены?" "n"; then
        print_info "Отмена"
        return 0
    fi

    # Закрываем порт до удаления конфига
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE" 2>/dev/null
        [ -n "${EXTERNAL_PORT:-}" ] && close_ufw_port "$EXTERNAL_PORT"
    fi

    # Останавливаем и удаляем сервис
    if systemctl list-unit-files 2>/dev/null | grep -q "^${SERVICE_NAME}.service"; then
        print_info "Остановка и удаление сервиса..."
        systemctl stop    "$SERVICE_NAME" 2>/dev/null || true
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        rm -f "/etc/systemd/system/$SERVICE_NAME.service"
        systemctl daemon-reload
        print_success "Сервис удалён"
    fi

    # Удаляем cron задачу
    if crontab -l 2>/dev/null | grep -q "update-configs.sh"; then
        print_info "Удаление cron задачи..."
        crontab -l 2>/dev/null | grep -v "update-configs.sh" | crontab -
        print_success "Cron задача удалена"
    fi

    # Удаляем симлинки
    for symlink in /usr/local/bin/mtproxy /usr/local/bin/MTProxy; do
        if [ -L "$symlink" ]; then
            rm -f "$symlink"
            print_success "Симлинк удалён: $symlink"
        fi
    done

    # Удаляем sysctl файл
    if [ -f /etc/sysctl.d/99-mtproxy-pid.conf ]; then
        rm -f /etc/sysctl.d/99-mtproxy-pid.conf
        sysctl -p /etc/sysctl.d/99-mtproxy-pid.conf 2>/dev/null || true
        print_success "Удалён файл sysctl: /etc/sysctl.d/99-mtproxy-pid.conf"
    fi

    # Удаляем каталог установки
    if [ -d "$INSTALL_DIR" ]; then
        print_info "Удаление файлов из $INSTALL_DIR..."
        rm -rf "$INSTALL_DIR"
        print_success "Файлы удалены"
    fi

    echo
    print_success "MTProxy полностью удалён"
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
            1) change_secret  ;;
            2) change_ad_tag  ;;
            3) change_ports   ;;
            4) change_workers ;;
            5) show_connection_info ;;
            0) break ;;
            *) print_error "Неверный выбор" ;;
        esac

        echo
        read -p "Нажмите Enter для продолжения..."
    done
}
