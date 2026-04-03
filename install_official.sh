#!/bin/bash
# install_official.sh — Загрузчик установки MTProxy Official.
# Проверяет окружение и делегирует всю логику модульной системе.
# Использование: sudo bash install_official.sh

set -e

# Проверка прав root до загрузки модулей
if [ "$EUID" -ne 0 ]; then
    echo "Скрипт требует права root. Запустите: sudo bash $0"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# Загружаем модули в порядке зависимостей
for _mod in lib_common lib_sni lib_config lib_install; do
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/modules/${_mod}.sh"
done
unset _mod

check_ubuntu
run_install "$SCRIPT_DIR"
