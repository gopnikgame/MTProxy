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
for _mod in lib_common lib_sni lib_config lib_install lib_service lib_manage; do
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
# Главное меню
################################################################################

show_menu() {
    while true; do
        clear
        echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}          MTProxy Official — Управление${NC}"
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
    check_installation
    show_menu
else
    case "$1" in
        install)
            check_root
            check_ubuntu
            _install_from_manager
            ;;
        start)          check_installation; start_service ;;
        stop)           check_installation; stop_service ;;
        restart)        check_installation; restart_service ;;
        status)         check_installation; show_status ;;
        logs)           check_installation; show_logs ;;
        follow-logs)    check_installation; follow_logs ;;
        stats)          check_installation; show_stats ;;
        info)           check_installation; show_connection_info ;;
        update-config)  check_installation; update_telegram_config ;;
        change-secret)  check_installation; change_secret ;;
        change-ad-tag)  check_installation; change_ad_tag ;;
        change-ports)   check_installation; change_ports ;;
        change-workers) check_installation; change_workers ;;
        rebuild)        check_installation; rebuild_binary ;;
        uninstall)      check_installation; uninstall ;;
        help|--help|-h)
            echo "MTProxy Official — Управление"
            echo
            echo "Использование: mtproxy [команда]"
            echo
            echo "Команды:"
            echo "  install          — Установить / переустановить MTProxy"
            echo "  start            — Запустить"
            echo "  stop             — Остановить"
            echo "  restart          — Перезапустить"
            echo "  status           — Показать статус"
            echo "  logs             — Показать логи"
            echo "  follow-logs      — Следить за логами (live)"
            echo "  stats            — Статистика прокси"
            echo "  info             — Информация для подключения"
            echo "  update-config    — Обновить конфигурацию Telegram"
            echo "  change-secret    — Изменить секрет"
            echo "  change-ad-tag    — Изменить AD Tag"
            echo "  change-ports     — Изменить порты"
            echo "  change-workers   — Изменить количество воркеров"
            echo "  rebuild          — Пересобрать из исходников"
            echo "  uninstall        — Удалить MTProxy"
            echo "  help             — Эта справка"
            echo
            echo "Без аргументов — интерактивное меню"
            ;;
        *)
            print_error "Неизвестная команда: $1"
            echo "Используйте: mtproxy help"
            exit 1
            ;;
    esac
fi
