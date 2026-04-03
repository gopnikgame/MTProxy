#!/bin/bash
# modules/lib_sni.sh
# Обнаружение локальных SNI-доменов (nginx, Caddy, remnanode)
# и интерактивный выбор TLS_DOMAIN / DOMAIN_NAME для MTProxy fakeTLS.
# Зависимость: lib_common.sh

[[ -n "${_LIB_SNI_LOADED:-}" ]] && return 0
_LIB_SNI_LOADED=1

# shellcheck source=modules/lib_common.sh
[[ -z "${_LIB_COMMON_LOADED:-}" ]] && source "$(dirname "${BASH_SOURCE[0]}")/lib_common.sh"

# Глобальный массив найденных доменов — заполняется через detect_sni_domains()
SNI_DETECTED_DOMAINS=()

# Regex валидного доменного имени (без wildcard и localhost)
readonly _SNI_DOMAIN_RE='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$'

################################################################################
# Сканеры
################################################################################

# Извлекает server_name из конфигов nginx
_sni_nginx_domains() {
    command -v nginx &>/dev/null || [ -d /etc/nginx ] || return
    local dirs=("/etc/nginx/sites-enabled" "/etc/nginx/conf.d")
    for dir in "${dirs[@]}"; do
        [ -d "$dir" ] || continue
        grep -rh 'server_name' "$dir" 2>/dev/null \
            | sed 's/server_name[[:space:]]*//; s/;//g' \
            | tr ' ' '\n' \
            | grep -E "$_SNI_DOMAIN_RE"
    done
}

# Извлекает имена сайтов из конфигов Caddy
_sni_caddy_domains() {
    command -v caddy &>/dev/null || [ -f /etc/caddy/Caddyfile ] || return
    local files=("/etc/caddy/Caddyfile")
    while IFS= read -r f; do files+=("$f"); done \
        < <(find /etc/caddy/conf.d /etc/caddy/sites-enabled 2>/dev/null \
            -maxdepth 1 -type f \( -name '*.conf' -o -name '*.caddy' \) 2>/dev/null)
    for f in "${files[@]}"; do
        [ -f "$f" ] || continue
        # Строки вида: domain.tld { или https://domain.tld {
        grep -E '^\s*(https?://)?[a-zA-Z0-9]' "$f" 2>/dev/null \
            | grep -v '#' \
            | awk '{print $1}' \
            | sed 's|https://||; s|http://||; s|:.*||; s|[{].*||; s|[[:space:]]||g' \
            | grep -E "$_SNI_DOMAIN_RE"
    done
}

# Извлекает домен из конфигурации remnanode (/opt/remnanode)
_sni_remnanode_domain() {
    local dir="/opt/remnanode"
    [ -d "$dir" ] || return

    # Сначала .env
    if [ -f "$dir/.env" ]; then
        local d
        d=$(grep -iE '^(APP_)?DOMAIN=' "$dir/.env" 2>/dev/null \
            | head -1 | cut -d= -f2- | tr -d '"'"'" | tr -d '[:space:]')
        [[ "$d" =~ $_SNI_DOMAIN_RE ]] && echo "$d" && return
    fi

    # docker-compose.yml / .yaml
    local compose=""
    for f in "$dir/docker-compose.yml" "$dir/docker-compose.yaml"; do
        [ -f "$f" ] && compose="$f" && break
    done
    if [ -n "$compose" ]; then
        local d
        d=$(grep -oE '[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+' \
                "$compose" 2>/dev/null \
            | grep -v 'traefik\.' \
            | grep -E "$_SNI_DOMAIN_RE" \
            | head -1)
        [[ -n "$d" ]] && echo "$d"
    fi
}

################################################################################
# Сбор и дедупликация
################################################################################

# Заполняет SNI_DETECTED_DOMAINS уникальными доменами из nginx, Caddy, remnanode.
detect_sni_domains() {
    SNI_DETECTED_DOMAINS=()
    local _seen=()

    _sni_add() {
        local d="${1//[[:space:]]/}"
        [[ -z "$d" ]] && return
        [[ ! "$d" =~ $_SNI_DOMAIN_RE ]] && return
        for s in "${_seen[@]}"; do [[ "$s" == "$d" ]] && return; done
        _seen+=("$d")
        SNI_DETECTED_DOMAINS+=("$d")
    }

    print_info "Поиск доменов: nginx, caddy, remnanode..."

    while IFS= read -r d; do _sni_add "$d"; done < <(_sni_nginx_domains)
    while IFS= read -r d; do _sni_add "$d"; done < <(_sni_caddy_domains)
    _sni_add "$(_sni_remnanode_domain)"

    if [ ${#SNI_DETECTED_DOMAINS[@]} -gt 0 ]; then
        print_success "Обнаружено доменов: ${#SNI_DETECTED_DOMAINS[@]}"
    else
        print_info "Локальные домены не обнаружены"
    fi
}

################################################################################
# Выбор DOMAIN_NAME (домен клиентской ссылки)
################################################################################

# Показывает найденные домены и предлагает выбрать или ввести свой.
# Результат → переменная DOMAIN_NAME.
# $1 — текущее значение (для подстановки по умолчанию)
select_domain_name() {
    local current="${1:-}"
    DOMAIN_NAME=""

    if [ ${#SNI_DETECTED_DOMAINS[@]} -gt 0 ]; then
        echo
        echo -e "  ${GREEN}Домены, настроенные на этом сервере:${NC}"
        local i=1
        for d in "${SNI_DETECTED_DOMAINS[@]}"; do
            echo "    $i) $d"
            ((i++))
        done
        local manual_idx=$i
        echo "    $manual_idx) Ввести другой домен"
        echo

        local hint=""
        [ -n "$current" ] && hint=" (Enter — оставить: $current)"
        while true; do
            read -p "Выберите домен [1-$manual_idx]$hint: " choice
            if [ -z "$choice" ] && [ -n "$current" ]; then
                DOMAIN_NAME="$current"
                print_info "Оставлен: $DOMAIN_NAME"
                return
            fi
            if [[ "$choice" =~ ^[0-9]+$ ]]; then
                if [ "$choice" -ge 1 ] && [ "$choice" -lt "$manual_idx" ]; then
                    DOMAIN_NAME="${SNI_DETECTED_DOMAINS[$((choice-1))]}"
                    print_success "Выбран: $DOMAIN_NAME"
                    return
                elif [ "$choice" -eq "$manual_idx" ]; then
                    break
                fi
            fi
            print_warning "Введите число от 1 до $manual_idx"
        done
    fi

    # Ручной ввод
    while true; do
        local prompt="Доменное имя"
        [ -n "$current" ] && prompt="$prompt [$current]"
        read -p "$prompt: " input
        DOMAIN_NAME="${input:-$current}"
        [ -n "$DOMAIN_NAME" ] && break
        print_warning "Домен не может быть пустым"
    done
}

################################################################################
# Выбор TLS_DOMAIN (домен маскировки для флага -D)
################################################################################

# Популярные внешние домены — тематики взяты из SNI-Templates
# (speedtest, filecloud, converter, games-site, 503-page)
_SNI_EXT_SUGGESTIONS=(
    "speedtest.net"
    "www.cloudflare.com"
    "www.microsoft.com"
    "www.google.com"
    "cdn.jsdelivr.net"
)

# Показывает список вариантов (локальные домены + внешние + ручной ввод).
# Результат → переменная TLS_DOMAIN.
# $1 — текущее значение
# $2 — предпочтительный домен (обычно = DOMAIN_NAME, показывается первым)
select_tls_domain() {
    local current="${1:-}"
    local preferred="${2:-}"

    echo
    echo -e "  ${CYAN}► Домен маскировки TLS (флаг -D):${NC}"
    echo    "  MTProxy имитирует TLS-рукопожатие этого домена."
    echo    "  Можно использовать собственный домен или любой внешний HTTPS-сайт."
    echo

    # Строим два параллельных массива: метки и значения
    local _labels=()
    local _values=()

    # 1. Предпочтительный домен (этот сервер) — первым
    if [ -n "$preferred" ]; then
        _labels+=("$preferred  ${CYAN}← этот сервер (рекомендуется)${NC}")
        _values+=("$preferred")
    fi

    # 2. Остальные локальные домены
    for d in "${SNI_DETECTED_DOMAINS[@]}"; do
        [[ "$d" == "$preferred" ]] && continue
        _labels+=("$d  ${GREEN}← этот сервер${NC}")
        _values+=("$d")
    done

    # 3. Внешние варианты (не дублируем уже добавленные)
    for ext in "${_SNI_EXT_SUGGESTIONS[@]}"; do
        local dup=0
        for v in "${_values[@]}"; do [[ "$v" == "$ext" ]] && dup=1 && break; done
        [[ $dup -eq 0 ]] && _labels+=("$ext") && _values+=("$ext")
    done

    # 4. Ввести свой
    local manual_label="Ввести свой домен"
    _labels+=("$manual_label")
    _values+=("")

    local total=${#_labels[@]}
    for ((i=0; i<total; i++)); do
        echo -e "    $((i+1))) ${_labels[$i]}"
    done
    echo

    # Подсказка про SNI-Templates если нет локальных доменов
    if [ ${#SNI_DETECTED_DOMAINS[@]} -eq 0 ] && [ -z "$preferred" ]; then
        echo -e "  ${YELLOW}Совет: создайте сайт-заглушку на своём домене — шаблоны:${NC}"
        echo    "  https://github.com/Famebloody/SNI-Templates"
        echo
    fi

    local hint=""
    [ -n "$current" ] && hint=" (Enter — оставить: $current)"

    while true; do
        read -p "Выберите [1-$total]$hint: " choice
        if [ -z "$choice" ] && [ -n "$current" ]; then
            TLS_DOMAIN="$current"
            print_info "Оставлен: $TLS_DOMAIN"
            return
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$total" ]; then
            local val="${_values[$((choice-1))]}"
            if [ -z "$val" ]; then
                break   # ручной ввод
            fi
            TLS_DOMAIN="$val"
            print_success "Выбран: $TLS_DOMAIN"
            _sni_validate_domain "$TLS_DOMAIN"
            return
        fi
        print_warning "Введите число от 1 до $total"
    done

    # Ручной ввод
    local def="${current:-www.google.com}"
    echo -e "  ${YELLOW}Примеры: www.cloudflare.com, speedtest.net, microsoft.com${NC}"
    read -p "Домен маскировки [$def]: " input
    TLS_DOMAIN="${input:-$def}"
    _sni_validate_domain "$TLS_DOMAIN"
}

_sni_validate_domain() {
    local d="$1"
    if host "$d" >/dev/null 2>&1; then
        print_success "DNS OK: $d"
    else
        print_warning "Не удалось разрешить $d — убедитесь, что домен существует"
    fi
}
