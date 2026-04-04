#!/bin/bash
# modules/lib_docker.sh
# Управление MTProxy через официальный Docker-контейнер (telegrammessenger/proxy).
# Zero-configuration вариант: не требует компиляции, конфигурирует себя сам.
# Зависимость: lib_common.sh

[[ -n "${_LIB_DOCKER_LOADED:-}" ]] && return 0
_LIB_DOCKER_LOADED=1

# shellcheck source=modules/lib_common.sh
[[ -z "${_LIB_COMMON_LOADED:-}" ]] && source "$(dirname "${BASH_SOURCE[0]}")/lib_common.sh"

################################################################################
# Константы
################################################################################

DOCKER_DIR="/opt/mtproto-proxy"
DOCKER_COMPOSE_FILE="$DOCKER_DIR/docker-compose.yml"
DOCKER_IMAGE="telegrammessenger/proxy"
DOCKER_CONTAINER="mtproto-proxy"

################################################################################
# Обнаружение
################################################################################

# Возвращает 0 если Docker-вариант установлен (docker-compose.yml существует)
detect_docker_installation() {
    [ -f "$DOCKER_COMPOSE_FILE" ]
}

################################################################################
# Вспомогательные
################################################################################

# Читает значение переменной среды из docker-compose.yml
_docker_get_env() {
    local key="$1"
    grep -oP "(?<=- ${key}=)\S+" "$DOCKER_COMPOSE_FILE" 2>/dev/null | head -1
}

# Устанавливает / обновляет переменную среды в docker-compose.yml
_docker_set_env() {
    local key="$1" value="$2"
    if grep -q "- ${key}=" "$DOCKER_COMPOSE_FILE"; then
        sed -i "s|- ${key}=.*|- ${key}=${value}|" "$DOCKER_COMPOSE_FILE"
    else
        # Добавляем строку после SECRET= (или WORKERS= если SECRET= нет)
        if grep -q "- SECRET=" "$DOCKER_COMPOSE_FILE"; then
            sed -i "/- SECRET=/a\\      - ${key}=${value}" "$DOCKER_COMPOSE_FILE"
        else
            sed -i "/- WORKERS=/a\\      - ${key}=${value}" "$DOCKER_COMPOSE_FILE"
        fi
    fi
}

# Перезапускает Docker-контейнер
_docker_restart() {
    print_info "Перезапуск контейнера..."
    cd "$DOCKER_DIR"
    docker compose restart
    print_success "Контейнер перезапущен"
}

################################################################################
# Выбор версии образа
################################################################################

_docker_select_image_tag() {
    print_info "Получение списка версий образа..."
    local raw
    raw=$(curl -s --max-time 10 \
        "https://hub.docker.com/v2/repositories/telegrammessenger/proxy/tags?page_size=20" \
        2>/dev/null | grep -oP '"name":"\K[^"]+' | grep -E '^[a-z0-9.]+$')

    local tags=()
    if [ -z "$raw" ]; then
        print_warning "Не удалось получить теги с Docker Hub"
        tags=("latest" "2.0beta")
    else
        while IFS= read -r t; do tags+=("$t"); done <<< "$raw"
    fi

    echo
    echo -e "  ${CYAN}Доступные версии:${NC}"
    local i=1 default_num=1
    for t in "${tags[@]}"; do
        if [ "$t" = "latest" ]; then
            echo "    $i) $t  ← рекомендуется"
            default_num=$i
        else
            echo "    $i) $t"
        fi
        ((i++))
    done

    read -p "Выберите версию [$default_num]: " pick
    pick="${pick:-$default_num}"
    if [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= ${#tags[@]} )); then
        DOCKER_IMAGE_TAG="${tags[$((pick-1))]}"
    else
        DOCKER_IMAGE_TAG="${tags[$((default_num-1))]}"
    fi
    print_success "Версия образа: $DOCKER_IMAGE_TAG"
}

################################################################################
# Установка
################################################################################

_docker_install_engine() {
    if ! command -v docker &>/dev/null; then
        print_info "Установка Docker Engine..."
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sh /tmp/get-docker.sh --quiet
        rm -f /tmp/get-docker.sh
        systemctl enable --now docker
        print_success "Docker установлен"
    else
        print_success "Docker: $(docker --version 2>/dev/null)"
    fi

    if ! docker compose version &>/dev/null 2>&1; then
        print_error "Плагин docker compose не найден (требуется Docker Engine >= 20.10)"
        return 1
    fi
    print_success "Docker Compose: $(docker compose version --short 2>/dev/null || echo 'ok')"
}

_docker_create_compose() {
    local port="$1" secret="$2" workers="$3" tag="$4"

    # Определяем внутренний IP хоста для передачи в контейнер.
    local internal_ip
    internal_ip=$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' | head -1)
    [ -z "$internal_ip" ] && internal_ip=$(ip -4 addr 2>/dev/null \
        | awk '/inet / {gsub(/\/.*/, "", $2); if ($2 != "127.0.0.1") {print $2; exit}}')
    [ -z "$internal_ip" ] && internal_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$internal_ip" ] && internal_ip="0.0.0.0"

    mkdir -p "$DOCKER_DIR"

    # Dockerfile: добавляем iproute2, которого нет в официальном образе.
    # run.sh требует ip(8) для определения внутреннего IP.
    # Поддерживаем оба пакетных менеджера: apt-get (Debian) и apk (Alpine).
    cat > "$DOCKER_DIR/Dockerfile" << EOF
FROM ${DOCKER_IMAGE}:${tag}
RUN if command -v apt-get > /dev/null 2>&1; then \
        apt-get update -qq && apt-get install -y -qq --no-install-recommends iproute2 && rm -rf /var/lib/apt/lists/*; \
    elif command -v apk > /dev/null 2>&1; then \
        apk add --no-cache iproute2; \
    fi
EOF

    cat > "$DOCKER_COMPOSE_FILE" << EOF
services:
  mtproto-proxy:
    build:
      context: ${DOCKER_DIR}
    image: mtproto-proxy-local
    container_name: ${DOCKER_CONTAINER}
    restart: unless-stopped
    ports:
      - "${port}:443"
    environment:
      - SECRET=${secret}
      - WORKERS=${workers}
      - INTERNAL_IP=${internal_ip}
    volumes:
      - proxy-data:/data
      - /etc/localtime:/etc/localtime:ro
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  proxy-data:
    name: mtproto-proxy-data
EOF

    print_success "docker-compose.yml создан: $DOCKER_COMPOSE_FILE"

    cd "$DOCKER_DIR"
    print_info "Сборка образа (добавление iproute2)..."
    docker compose build
    docker compose up -d
    print_success "Контейнер запущен"

    # Ежедневный перезапуск — рекомендация Telegram для обновления IP ядра
    local cron_cmd="0 4 * * * cd ${DOCKER_DIR} && docker compose restart >> /var/log/mtproto-restart.log 2>&1"
    if crontab -l 2>/dev/null | grep -q "mtproto-proxy"; then
        print_info "Cron задача уже существует"
    else
        (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
        print_success "Cron задача: перезапуск в 4:00 ежедневно"
    fi
}

run_docker_install() {
    print_header "Установка MTProxy (Docker)"

    check_ubuntu

    # ── Адрес сервера ─────────────────────────────────────────────────────
    local detected_ip; detected_ip=$(get_external_ip)
    [ -n "$detected_ip" ] && print_info "Обнаружен внешний IP: $detected_ip"

    read -p "Адрес сервера для ссылки (IP или домен) [${detected_ip}]: " input_addr
    local server_addr="${input_addr:-$detected_ip}"
    if [ -z "$server_addr" ]; then
        print_error "Адрес сервера обязателен"
        return 1
    fi

    # ── Порт ──────────────────────────────────────────────────────────────
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}Порт для клиентов:${NC}"
    _show_port_recommendations
    echo

    local default_port="${SUGGESTED_PORT:-443}"
    local mtproto_port
    while true; do
        read -p "Порт MTProxy [$default_port]: " mtproto_port
        mtproto_port="${mtproto_port:-$default_port}"
        if is_port_available "$mtproto_port"; then
            break
        fi
        if read_yes_no "Порт $mtproto_port занят. Всё равно использовать?" "n"; then
            break
        fi
    done

    # ── Секрет ────────────────────────────────────────────────────────────
    read -p "Секрет (оставьте пустым для генерации): " input_secret
    local secret
    if [ -z "$input_secret" ]; then
        secret=$(head -c 16 /dev/urandom | xxd -ps)
        print_success "Сгенерирован секрет: $secret"
    else
        secret="$input_secret"
    fi

    # ── Воркеры ───────────────────────────────────────────────────────────
    local cpu_cores; cpu_cores=$(nproc)
    read -p "Количество воркеров (ядер CPU: $cpu_cores) [2]: " input_workers
    local workers="${input_workers:-2}"

    # ── Версия образа ─────────────────────────────────────────────────────
    _docker_select_image_tag

    # ── Установка ─────────────────────────────────────────────────────────
    print_header "Выполнение установки"

    print_info "Установка зависимостей..."
    apt-get update -qq
    apt-get install -y -qq curl ntp 2>/dev/null || true
    systemctl enable --now ntp 2>/dev/null || true
    timedatectl set-ntp true 2>/dev/null || true

    _docker_install_engine
    _docker_create_compose "$mtproto_port" "$secret" "$workers" "$DOCKER_IMAGE_TAG"
    open_ufw_port "$mtproto_port"

    sleep 5

    local proxy_link="tg://proxy?server=${server_addr}&port=${mtproto_port}&secret=${secret}"

    echo
    echo "═══════════════════════════════════════════════════════════"
    echo -e "${GREEN}✓ MTProxy Docker успешно установлен и запущен!${NC}"
    echo "═══════════════════════════════════════════════════════════"
    echo
    echo -e "${CYAN}📋 КОНФИГУРАЦИЯ:${NC}"
    echo "   Сервер:     $server_addr"
    echo "   Порт:       $mtproto_port"
    echo "   Образ:      ${DOCKER_IMAGE}:${DOCKER_IMAGE_TAG}"
    echo "   Воркеры:    $workers"
    echo
    echo -e "${CYAN}🔗 ССЫЛКА ДЛЯ ПОДКЛЮЧЕНИЯ:${NC}"
    echo "═══════════════════════════════════════════════════════════"
    echo "$proxy_link"
    echo "═══════════════════════════════════════════════════════════"
    echo
    echo -e "${YELLOW}🤖 РЕГИСТРАЦИЯ В @MTProxybot:${NC}"
    echo "   Секрет для бота: $secret"
    print_info "Используйте этот секрет при регистрации в @MTProxybot"
    echo
    print_info "Логи:        docker logs $DOCKER_CONTAINER"
    print_info "Статистика:  docker exec $DOCKER_CONTAINER curl http://localhost:2398/stats"
    echo
    print_info "Управление:  mtproxy  (интерактивное меню)"
    echo

    # Сохраняем данные
    {
        echo "$proxy_link"
        echo ""
        echo "Секрет для @MTProxybot: $secret"
    } > "$DOCKER_DIR/proxy_link.txt"
    print_success "Данные сохранены: $DOCKER_DIR/proxy_link.txt"
}

################################################################################
# Статус и информация
################################################################################

show_docker_status() {
    print_header "Статус MTProxy (Docker)"

    if ! detect_docker_installation; then
        print_error "Docker-вариант не установлен"
        return 1
    fi

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${DOCKER_CONTAINER}$"; then
        echo -e "${GREEN}● ${DOCKER_CONTAINER} — активен и работает${NC}"
    else
        echo -e "${RED}● ${DOCKER_CONTAINER} — остановлен или не найден${NC}"
    fi

    echo
    docker compose -f "$DOCKER_COMPOSE_FILE" ps 2>/dev/null

    echo
    print_info "Статистика подключений:"
    docker exec "$DOCKER_CONTAINER" curl -s --max-time 3 http://localhost:2398/stats 2>/dev/null \
        | grep -E "(total_special_connections|total_max_special_connections|active_targets|ready_targets)" \
        || print_warning "Статистика временно недоступна"

    echo
    print_info "Подробные логи: docker logs $DOCKER_CONTAINER"
}

show_docker_info() {
    print_header "Информация для подключения (Docker)"

    if ! detect_docker_installation; then
        print_error "Docker-вариант не установлен"
        return 1
    fi

    local secret; secret=$(_docker_get_env "SECRET")
    local port; port=$(grep -oP '"\K\d+(?=:443")' "$DOCKER_COMPOSE_FILE" | head -1)
    local server_addr; server_addr=$(get_external_ip)

    local proxy_link="tg://proxy?server=${server_addr}&port=${port}&secret=${secret}"

    echo
    echo "═══════════════════════════════════════════════════════════"
    echo -e "${CYAN}📋 КОНФИГУРАЦИЯ:${NC}"
    echo "   Сервер:  $server_addr"
    echo "   Порт:    $port"
    echo "   Образ:   ${DOCKER_IMAGE}:$(grep -oP "(?<=FROM ${DOCKER_IMAGE}:)\S+" "$DOCKER_DIR/Dockerfile" 2>/dev/null | head -1)"
    echo
    echo -e "${CYAN}🔗 ССЫЛКА ДЛЯ ПОДКЛЮЧЕНИЯ:${NC}"
    echo "═══════════════════════════════════════════════════════════"
    echo "$proxy_link"
    echo "═══════════════════════════════════════════════════════════"
    echo
    echo -e "${YELLOW}🤖 РЕГИСТРАЦИЯ В @MTProxybot:${NC}"
    echo "   Секрет для бота: $secret"
    print_info "Голый секрет (без префиксов) — используйте при регистрации в @MTProxybot"
    echo
    print_info "Ссылка из логов контейнера:"
    docker logs "$DOCKER_CONTAINER" 2>&1 | grep -E "tg://proxy" | tail -3 \
        || print_info "Запустите контейнер для получения ссылки из логов"
}

show_docker_logs() {
    print_header "Логи MTProxy (Docker)"
    docker logs "$DOCKER_CONTAINER" --tail 50 2>/dev/null \
        || print_error "Контейнер '$DOCKER_CONTAINER' не найден"
}

follow_docker_logs() {
    print_header "Логи MTProxy Docker (live)"
    echo "Нажмите Ctrl+C для выхода"
    echo
    docker logs "$DOCKER_CONTAINER" -f 2>/dev/null \
        || print_error "Контейнер '$DOCKER_CONTAINER' не найден"
}

################################################################################
# Изменение конфигурации
################################################################################

docker_change_secret() {
    print_header "Изменение секрета (Docker)"

    local current; current=$(_docker_get_env "SECRET")
    echo "Текущий секрет: $current"
    echo

    read -p "Новый секрет (оставьте пустым для генерации): " input
    local new_secret="${input}"
    [ -z "$new_secret" ] && new_secret=$(head -c 16 /dev/urandom | xxd -ps)

    _docker_set_env "SECRET" "$new_secret"
    _docker_restart

    local port; port=$(grep -oP '"\K\d+(?=:443")' "$DOCKER_COMPOSE_FILE" | head -1)
    local server_addr; server_addr=$(get_external_ip)

    print_success "Секрет обновлён: $new_secret"
    echo
    echo -e "${CYAN}Новая ссылка:${NC}"
    echo "tg://proxy?server=${server_addr}&port=${port}&secret=${new_secret}"
}

docker_change_ad_tag() {
    print_header "Изменение AD Tag (Docker)"

    local current; current=$(_docker_get_env "TAG")
    [ -n "$current" ] && echo "Текущий тег: $current" || echo "AD Tag не установлен"
    echo
    print_info "Тег выдаётся ботом @MTProxybot после регистрации прокси"
    read -p "Рекламный тег (оставьте пустым для удаления): " new_tag

    if [ -z "$new_tag" ]; then
        sed -i '/- TAG=/d' "$DOCKER_COMPOSE_FILE"
        print_info "AD Tag удалён"
    else
        _docker_set_env "TAG" "$new_tag"
        print_success "AD Tag установлен: $new_tag"
    fi
    _docker_restart
}

docker_change_workers() {
    print_header "Изменение воркеров (Docker)"

    local current; current=$(_docker_get_env "WORKERS")
    local cpu_cores; cpu_cores=$(nproc)
    echo "Текущее значение: $current  |  Доступно ядер CPU: $cpu_cores"
    echo

    read -p "Новое количество воркеров [$current]: " input
    local new_workers="${input:-$current}"

    _docker_set_env "WORKERS" "$new_workers"
    _docker_restart
    print_success "Воркеры: $new_workers"
}

docker_change_port() {
    print_header "Изменение порта (Docker)"

    local old_port; old_port=$(grep -oP '"\K\d+(?=:443")' "$DOCKER_COMPOSE_FILE" | head -1)
    echo "Текущий порт: $old_port"
    echo
    _show_port_recommendations
    echo

    local new_port
    while true; do
        read -p "Новый порт [$old_port]: " new_port
        new_port="${new_port:-$old_port}"
        [ "$new_port" = "$old_port" ] && break
        if is_port_available "$new_port"; then
            break
        fi
        print_warning "Порт $new_port занят, введите другой"
    done

    if [ "$new_port" != "$old_port" ]; then
        sed -i "s|\"${old_port}:443\"|\"${new_port}:443\"|" "$DOCKER_COMPOSE_FILE"
        close_ufw_port "$old_port"
        open_ufw_port "$new_port"
        _docker_restart

        local secret; secret=$(_docker_get_env "SECRET")
        local server_addr; server_addr=$(get_external_ip)
        print_success "Порт изменён: $old_port → $new_port"
        echo
        echo -e "${CYAN}Новая ссылка:${NC}"
        echo "tg://proxy?server=${server_addr}&port=${new_port}&secret=${secret}"
    else
        print_info "Порт не изменён"
    fi
}

docker_change_image_tag() {
    print_header "Обновление версии образа (Docker)"

    local current_tag; current_tag=$(grep -oP "(?<=FROM ${DOCKER_IMAGE}:)\S+" "$DOCKER_DIR/Dockerfile" 2>/dev/null | head -1)
    echo "Текущая версия: $current_tag"
    echo

    _docker_select_image_tag
    sed -i "s|FROM ${DOCKER_IMAGE}:.*|FROM ${DOCKER_IMAGE}:${DOCKER_IMAGE_TAG}|" "$DOCKER_DIR/Dockerfile"

    print_info "Загрузка и пересборка образа..."
    cd "$DOCKER_DIR" && docker compose build --pull
    _docker_restart

    print_success "Образ обновлён: $current_tag → $DOCKER_IMAGE_TAG"
}

docker_config_menu() {
    while true; do
        echo
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "${CYAN}  Конфигурация Docker MTProxy${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  1) Сменить секрет"
        echo "  2) Изменить AD Tag"
        echo "  3) Изменить количество воркеров"
        echo "  4) Сменить порт"
        echo "  5) Обновить версию образа"
        echo "  0) Назад"
        echo
        read -p "Выберите: " cfg_choice
        case $cfg_choice in
            1) docker_change_secret ;;
            2) docker_change_ad_tag ;;
            3) docker_change_workers ;;
            4) docker_change_port ;;
            5) docker_change_image_tag ;;
            0) return ;;
            *) print_error "Неверный выбор" ;;
        esac
        echo
        read -p "Нажмите Enter для продолжения..."
    done
}

################################################################################
# Удаление
################################################################################

docker_uninstall() {
    print_header "Удаление MTProxy (Docker)"

    if ! read_yes_no "Удалить контейнер, тома и конфигурацию?" "n"; then
        print_info "Отмена"
        return 0
    fi

    local port
    port=$(grep -oP '"\K\d+(?=:443")' "$DOCKER_COMPOSE_FILE" 2>/dev/null | head -1)

    cd "$DOCKER_DIR" 2>/dev/null && docker compose down -v 2>/dev/null || true
    docker rm -f "$DOCKER_CONTAINER" 2>/dev/null || true
    docker volume rm mtproto-proxy-data 2>/dev/null || true
    rm -rf "$DOCKER_DIR"

    crontab -l 2>/dev/null | grep -v 'mtproto-proxy' | crontab - 2>/dev/null || true
    rm -f /var/log/mtproto-restart.log

    [ -n "$port" ] && close_ufw_port "$port"

    print_success "Docker MTProxy удалён"
}

################################################################################
# Главное меню Docker
################################################################################

show_docker_menu() {
    while true; do
        clear
        echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}          MTProxy Docker — Управление${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
        echo

        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${DOCKER_CONTAINER}$"; then
            echo -e "Статус: ${GREEN}● Работает${NC}"
        else
            echo -e "Статус: ${RED}○ Остановлен${NC}"
        fi

        echo
        echo "═══════════════════════════════════════════════════════════"
        echo " УПРАВЛЕНИЕ КОНТЕЙНЕРОМ"
        echo "═══════════════════════════════════════════════════════════"
        echo "  1) Запустить"
        echo "  2) Остановить"
        echo "  3) Перезапустить"
        echo "  4) Статус и статистика"
        echo "  5) Просмотр логов"
        echo "  6) Следить за логами (live)"
        echo
        echo "═══════════════════════════════════════════════════════════"
        echo " ИНФОРМАЦИЯ И НАСТРОЙКА"
        echo "═══════════════════════════════════════════════════════════"
        echo "  7) Показать ссылку для подключения"
        echo "  8) Конфигурация (секрет, порт, AD Tag, воркеры)"
        echo
        echo "═══════════════════════════════════════════════════════════"
        echo " ОБСЛУЖИВАНИЕ"
        echo "═══════════════════════════════════════════════════════════"
        echo "  9) Переустановить"
        echo " 10) Удалить"
        echo
        echo "  0) Выход"
        echo
        echo "═══════════════════════════════════════════════════════════"
        read -p "Выберите действие: " choice

        case $choice in
            1)  cd "$DOCKER_DIR" && docker compose up -d && print_success "Запущен" ;;
            2)  cd "$DOCKER_DIR" && docker compose down && print_success "Остановлен" ;;
            3)  cd "$DOCKER_DIR" && docker compose restart && print_success "Перезапущен" ;;
            4)  show_docker_status ;;
            5)  show_docker_logs ;;
            6)  follow_docker_logs; continue ;;
            7)  show_docker_info ;;
            8)  docker_config_menu ;;
            9)  run_docker_install ;;
            10) docker_uninstall; break ;;
            0)  break ;;
            *)  print_error "Неверный выбор" ;;
        esac

        echo
        read -p "Нажмите Enter для продолжения..."
    done
}
