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
_has_binary=false; _has_docker=false
[ -f "$MTPROXY_BINARY" ] && [ -f "$CONFIG_FILE" ] && _has_binary=true
[ -f "/opt/mtproto-proxy/docker-compose.yml" ] && _has_docker=true

if $_has_binary && $_has_docker; then
    echo -e "${GREEN}  Binary и Docker MTProxy установлены. Управление:${NC}"
    echo
    echo "    sudo mtproxy          # выбор варианта (интерактивное меню)"
    echo "    sudo mtproxy info     # ссылка для подключения"
    echo "    sudo mtproxy status   # статус"
elif $_has_binary; then
    echo -e "${GREEN}  MTProxy Binary установлен. Управление:${NC}"
    echo
    echo "    sudo mtproxy          # интерактивное меню"
    echo "    sudo mtproxy info     # ссылка для подключения"
    echo "    sudo mtproxy status   # статус сервиса"
elif $_has_docker; then
    echo -e "${GREEN}  MTProxy Docker установлен. Управление:${NC}"
    echo
    echo "    sudo mtproxy          # интерактивное меню"
    echo "    sudo mtproxy info     # ссылка для подключения"
    echo "    sudo mtproxy status   # статус контейнера"
else
    echo -e "${CYAN}  Скрипты готовы. Для установки выполните:${NC}"
    echo
    echo "    sudo mtproxy          # мастер установки: Binary или Docker"
fi
echo "═══════════════════════════════════════════════════════════"
echo
