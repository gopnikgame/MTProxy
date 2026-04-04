#!/bin/bash
# manage_mtproxy_official.sh — Диспетчер управления MTProxy Official.
# Подключает модули из INSTALL_DIR/modules/ и диспетчеризует команды.
# Использование: mtproxy [команда]  или  sudo bash manage_mtproxy_official.sh [команда]

# Разрешаем симлинки → реальное расположение файла
MANAGER_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
MODULES_DIR="$MANAGER_DIR/modules"

# Все команды (кроме help) требуют root
if [ "$EUID" -ne 0 ]; then
    _cmd="${1:-}"
    if [[ "$_cmd" != "help" && "$_cmd" != "--help" && "$_cmd" != "-h" ]]; then
        echo "MTProxy Manager требует права root. Запустите: sudo mtproxy ${*}"
        exit 1
    fi
fi

# Загружаем все модули в порядке зависимостей
for _mod in lib_common lib_sni lib_config lib_install lib_service lib_manage lib_docker; do
    # shellcheck source=/dev/null
    source "$MODULES_DIR/${_mod}.sh"
done
unset _mod

################################################################################
# Переустановка из менеджера
################################################################################

# clone_and_build_mtproxy делает rm -rf INSTALL_DIR, поэтому до его вызова
# сташим модули во временную директорию и передаём её как src_dir.
_install_from_manager() {
    local tmpdir; tmpdir=$(mktemp -d)
    cp -r "$MANAGER_DIR/modules" "$tmpdir/"
    cp "$MANAGER_DIR/manage_mtproxy_official.sh" "$tmpdir/"
    run_install "$tmpdir"
    rm -rf "$tmpdir"
}

################################################################################
# Определение типа установки
################################################################################

# Возвращает: "binary", "docker", "both" или "none"
_detect_install_type() {
    local has_binary=false has_docker=false
    [ -f "$MTPROXY_BINARY" ] && [ -f "$CONFIG_FILE" ] && has_binary=true
    [ -f "$DOCKER_COMPOSE_FILE" ] && has_docker=true
    if $has_binary && $has_docker; then echo "both"
    elif $has_binary;               then echo "binary"
    elif $has_docker;               then echo "docker"
    else                                 echo "none"
    fi
}

# Предлагает выбор типа установки, если ничего не установлено
_prompt_install_type() {
    while true; do
        clear
        echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}          MTProxy Manager${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
        echo
        echo -e "${YELLOW}MTProxy не установлен. Выберите вариант:${NC}"
        echo
        echo "  1) Binary  — официальный C-бинарник, компилируется из исходников"
        echo "  2) Docker  — zero-configuration контейнер (требует Docker)"
        echo "  0) Выход"
        echo
        read -p "Выберите: " choice
        case $choice in
            1) check_ubuntu; _install_from_manager; return ;;
            2) run_docker_install; return ;;
            0) exit 0 ;;
            *) print_error "Неверный выбор" ;;
        esac
    done
}

# Предлагает выбор, если установлены оба варианта
_prompt_select_type() {
    while true; do
        clear
        echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}          MTProxy Manager${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
        echo
        echo -e "${CYAN}Обнаружены оба варианта установки:${NC}"
        echo
        echo "  1) Binary  — C-бинарник (/opt/MTProxy)"
        echo "  2) Docker  — контейнер (/opt/mtproto-proxy)"
        echo "  0) Выход"
        echo
        read -p "Управлять: " choice
        case $choice in
            1) show_menu; return ;;
            2) show_docker_menu; return ;;
            0) exit 0 ;;
            *) print_error "Неверный выбор" ;;
        esac
    done
}

################################################################################
# Главное меню (Binary)
################################################################################

show_menu() {
    while true; do
        clear
        echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}          MTProxy Binary — Управление${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
        echo

        if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
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
        echo " 12) Переустановить MTProxy"
        echo " 13) Удалить MTProxy"
        echo
        echo "  0) Выход"
        echo
        echo "═══════════════════════════════════════════════════════════"
        read -p "Выберите действие: " choice

        case $choice in
            1)  start_service ;;
            2)  stop_service ;;
            3)  restart_service ;;
            4)  show_status ;;
            5)  show_logs ;;
            6)  follow_logs; continue ;;
            7)  show_connection_info ;;
            8)  show_stats ;;
            9)  config_menu ;;
            10) update_telegram_config ;;
            11) rebuild_binary ;;
            12) _install_from_manager ;;
            13) uninstall; break ;;
            0)  break ;;
            *)  print_error "Неверный выбор" ;;
        esac

        echo
        read -p "Нажмите Enter для продолжения..."
    done
}

################################################################################
# Точка входа
################################################################################

if [ $# -eq 0 ]; then
    case $(_detect_install_type) in
        binary) show_menu ;;
        docker) show_docker_menu ;;
        both)   _prompt_select_type ;;
        none)   _prompt_install_type ;;
    esac
else
    _type=$(_detect_install_type)
    case "$1" in
        install)
            case $_type in
                none)   _prompt_install_type ;;
                binary) check_ubuntu; _install_from_manager ;;
                docker) run_docker_install ;;
                both)   _prompt_select_type ;;
            esac
            ;;
        start)
            case $_type in
                binary|both) check_installation; start_service ;;
                docker)      cd "$DOCKER_DIR" && docker compose up -d && print_success "Запущен" ;;
                none)        print_error "MTProxy не установлен" ;;
            esac
            ;;
        stop)
            case $_type in
                binary|both) check_installation; stop_service ;;
                docker)      cd "$DOCKER_DIR" && docker compose down && print_success "Остановлен" ;;
                none)        print_error "MTProxy не установлен" ;;
            esac
            ;;
        restart)
            case $_type in
                binary|both) check_installation; restart_service ;;
                docker)      cd "$DOCKER_DIR" && docker compose restart && print_success "Перезапущен" ;;
                none)        print_error "MTProxy не установлен" ;;
            esac
            ;;
        status)
            case $_type in
                binary|both) check_installation; show_status ;;
                docker)      show_docker_status ;;
                none)        print_error "MTProxy не установлен" ;;
            esac
            ;;
        logs)
            case $_type in
                binary|both) check_installation; show_logs ;;
                docker)      show_docker_logs ;;
                none)        print_error "MTProxy не установлен" ;;
            esac
            ;;
        follow-logs)
            case $_type in
                binary|both) check_installation; follow_logs ;;
                docker)      follow_docker_logs ;;
                none)        print_error "MTProxy не установлен" ;;
            esac
            ;;
        stats)
            case $_type in
                binary|both) check_installation; show_stats ;;
                docker)      show_docker_status ;;
                none)        print_error "MTProxy не установлен" ;;
            esac
            ;;
        info)
            case $_type in
                binary|both) check_installation; show_connection_info ;;
                docker)      show_docker_info ;;
                none)        print_error "MTProxy не установлен" ;;
            esac
            ;;
        update-config)  check_installation; update_telegram_config ;;
        change-secret)
            case $_type in
                binary|both) check_installation; change_secret ;;
                docker)      docker_change_secret ;;
                none)        print_error "MTProxy не установлен" ;;
            esac
            ;;
        change-ad-tag)
            case $_type in
                binary|both) check_installation; change_ad_tag ;;
                docker)      docker_change_ad_tag ;;
                none)        print_error "MTProxy не установлен" ;;
            esac
            ;;
        change-ports)
            case $_type in
                binary|both) check_installation; change_ports ;;
                docker)      docker_change_port ;;
                none)        print_error "MTProxy не установлен" ;;
            esac
            ;;
        change-workers)
            case $_type in
                binary|both) check_installation; change_workers ;;
                docker)      docker_change_workers ;;
                none)        print_error "MTProxy не установлен" ;;
            esac
            ;;
        rebuild)        check_installation; rebuild_binary ;;
        uninstall)
            case $_type in
                binary|both) check_installation; uninstall ;;
                docker)      docker_uninstall ;;
                none)        print_error "MTProxy не установлен" ;;
            esac
            ;;
        help|--help|-h)
            echo "MTProxy Manager — Управление"
            echo
            echo "Использование: mtproxy [команда]"
            echo
            echo "Команды (Binary и Docker):"
            echo "  install          — Установить / переустановить"
            echo "  start            — Запустить"
            echo "  stop             — Остановить"
            echo "  restart          — Перезапустить"
            echo "  status           — Показать статус"
            echo "  logs             — Показать логи"
            echo "  follow-logs      — Следить за логами (live)"
            echo "  stats            — Статистика прокси"
            echo "  info             — Информация для подключения"
            echo "  change-secret    — Изменить секрет"
            echo "  change-ad-tag    — Изменить AD Tag"
            echo "  change-ports     — Изменить порт"
            echo "  change-workers   — Изменить количество воркеров"
            echo "  uninstall        — Удалить"
            echo
            echo "Команды только для Binary:"
            echo "  update-config    — Обновить конфигурацию Telegram"
            echo "  rebuild          — Пересобрать из исходников"
            echo
            echo "Без аргументов — интерактивное меню (автоопределение типа)"
            ;;
        *)
            print_error "Неизвестная команда: $1"
            echo "Используйте: mtproxy help"
            exit 1
            ;;
    esac
fi
