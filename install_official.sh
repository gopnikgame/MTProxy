#!/bin/bash
# install_official.sh — Бутстраппер MTProxy Manager.
# Копирует модули управления в /opt/MTProxy, создаёт симлинк /usr/local/bin/mtproxy.
# Безопасен для повторного запуска: .env, run/ и objs/ не затрагиваются.
#
#   Первый запуск:           sudo bash install_official.sh
#   Затем установить прокси: sudo mtproxy install
#   Обновить только скрипты: sudo bash install_official.sh  (повторно)

set -e

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

if [ "$EUID" -ne 0 ]; then
    echo "Требуются права root. Запустите: sudo bash $0"
    exit 1
fi

# shellcheck source=modules/lib_common.sh
source "$SCRIPT_DIR/modules/lib_common.sh"

print_header "MTProxy Manager — Инициализация"

# Создаём директорию если нет (не трогаем run/, objs/, .env)
mkdir -p "$INSTALL_DIR/modules"

# Копируем модули управления
print_info "Копирование модулей управления..."
cp "$SCRIPT_DIR/modules/"*.sh "$INSTALL_DIR/modules/"
chmod +x "$INSTALL_DIR/modules/"*.sh
print_success "Модули: $INSTALL_DIR/modules/"

# Копируем диспетчер
cp "$SCRIPT_DIR/manage_mtproxy_official.sh" "$INSTALL_DIR/manage_mtproxy_official.sh"
chmod +x "$INSTALL_DIR/manage_mtproxy_official.sh"
print_success "Менеджер: $INSTALL_DIR/manage_mtproxy_official.sh"

# Создаём симлинки
ln -sf "$INSTALL_DIR/manage_mtproxy_official.sh" /usr/local/bin/mtproxy
ln -sf "$INSTALL_DIR/manage_mtproxy_official.sh" /usr/local/bin/MTProxy
print_success "Симлинки: /usr/local/bin/mtproxy → $INSTALL_DIR/manage_mtproxy_official.sh"

echo
echo "═══════════════════════════════════════════════════════════"
if [ -f "$MTPROXY_BINARY" ] && [ -f "$CONFIG_FILE" ]; then
    echo -e "${GREEN}  MTProxy уже установлен. Управление:${NC}"
    echo
    echo "    sudo mtproxy          # интерактивное меню"
    echo "    sudo mtproxy info     # ссылка для подключения"
    echo "    sudo mtproxy status   # статус сервиса"
else
    echo -e "${CYAN}  Скрипты готовы. Для установки MTProxy выполните:${NC}"
    echo
    echo "    sudo mtproxy install"
fi
echo "═══════════════════════════════════════════════════════════"
echo
