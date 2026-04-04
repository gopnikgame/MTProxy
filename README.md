# MTProxy — Официальная реализация от Telegram

[![GitHub](https://img.shields.io/badge/GitHub-MTProxy-blue?logo=github)](https://github.com/TelegramMessenger/MTProxy)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%2B-orange?logo=ubuntu)](https://ubuntu.com/)
[![License](https://img.shields.io/badge/License-GPL%20v2-green.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)

Автоматическая установка **официального MTProto прокси от Telegram** на Ubuntu.  
Поддерживает два варианта: **C-бинарник** (компиляция из исходников) и **Docker-контейнер** (zero-configuration).  
Управление через **модульную bash-систему** — каждый файл отвечает за одну зону ответственности.

---

## 🚀 Быстрый старт

```bash
git clone https://github.com/gopnikgame/MTProxy.git
cd MTProxy
sudo bash install_official.sh
```

`install_official.sh` копирует модули в `/opt/MTProxy/` и создаёт симлинк `mtproxy`. После запуска предложит выбрать вариант установки:

```bash
sudo mtproxy          # мастер: выбор Binary (C-бинарник) или Docker-контейнер
mtproxy help          # список всех команд
```

> Все операции управления требуют `sudo`.

---

## ✨ Возможности

| | |
|---|---|
| ⚡ **Производительность** | C-реализация, multi-core (воркеры), официальная поддержка Telegram |
| 🔒 **Безопасность** | Random Padding (защита от DPI), fakeTLS (`ee`-секрет, флаг `-D`), systemd hardening |
| 🌐 **SNI-маскировка** | Автоопределение доменов nginx / Caddy / remnanode для `-D` |
| 🛠 **Удобство** | Интерактивное меню, автообновление конфигов Telegram, симлинк `mtproxy` |
| 💰 **Монетизация** | AD Tag через [@MTProxybot](https://t.me/MTProxybot) |
| 🐳 **Docker-режим** | Zero-configuration контейнер `telegrammessenger/proxy`, авторестарт в 4:00 |

---

## 🛠 Управление

```bash
# Установка (мастер: выбор Binary или Docker)
sudo mtproxy install
sudo mtproxy          # то же при первом запуске

# Управление сервисом / контейнером
sudo mtproxy start / stop / restart / status

# Информация
sudo mtproxy info             # Ссылка для подключения
sudo mtproxy stats            # Статистика прокси
sudo mtproxy logs             # Последние 50 строк логов
sudo mtproxy follow-logs      # Логи в реальном времени

# Настройка (Binary и Docker)
sudo mtproxy change-secret
sudo mtproxy change-ad-tag
sudo mtproxy change-ports
sudo mtproxy change-workers
sudo mtproxy uninstall        # Полное удаление

# Только для Binary-режима
sudo mtproxy update-config    # Обновить конфиги Telegram
sudo mtproxy rebuild          # Пересборка из исходников
```

---

## 🔗 Подключение клиентов

**fakeTLS-маскировка** (домен + флаг `-D`):
```
tg://proxy?server=proxy.example.com&port=443&secret=ee<32hex>
```

**Random Padding** (без домена):
```
tg://proxy?server=1.2.3.4&port=443&secret=dd<32hex>
```

1. Откройте ссылку на устройстве с Telegram → **Connect Proxy**
2. Для монетизации зарегистрируйтесь в [@MTProxybot](https://t.me/MTProxybot) → `/newproxy`

> Префиксы секрета: `ee` = fakeTLS, `dd` = Random Padding, без префикса = plain

---

## 📁 Структура репозитория

```
MTProxy/                            ← репозиторий (git clone)
├── install_official.sh             # Загрузчик: копирует модули, создаёт симлинк
├── manage_mtproxy_official.sh      # Диспетчер управления
└── modules/
    ├── lib_common.sh               # Константы, утилиты, build_cmd()
    ├── lib_sni.sh                  # Детектор SNI-доменов (nginx/Caddy/remnanode)
    ├── lib_config.sh               # Мастер настройки + show_connection_info()
    ├── lib_install.sh              # Полный пайплайн установки Binary
    ├── lib_service.sh              # Управление сервисом (start/stop/logs/stats)
    ├── lib_manage.sh               # Изменение параметров, rebuild, uninstall
    └── lib_docker.sh               # Docker-контейнер: установка, управление, конфигурация
```

После установки все файлы копируются в `/opt/MTProxy/`:

```
/opt/MTProxy/
├── .env                            # Конфигурация (source-совместимый key=value)
├── manage_mtproxy_official.sh      # Диспетчер (симлинк: /usr/local/bin/mtproxy)
├── update-configs.sh               # Cron: обновление конфигов Telegram (3:00)
├── proxy_link.txt                  # Ссылка для подключения
├── modules/                        # Модули (скопированы из репозитория)
│   └── lib_*.sh
├── objs/bin/mtproto-proxy          # Скомпилированный бинарник
└── run/
    ├── proxy-secret                # Ключи Telegram
    ├── proxy-multi.conf            # Серверы Telegram
    └── secret.txt                  # Пользовательский секрет (32 hex)

/usr/local/bin/mtproxy              # Симлинк → /opt/MTProxy/manage_mtproxy_official.sh
/usr/local/bin/MTProxy              # Симлинк → /opt/MTProxy/manage_mtproxy_official.sh
/etc/systemd/system/mtproxy.service
/etc/sysctl.d/99-mtproxy-pid.conf   # kernel.pid_max=65535 (воркараунд MTProxy C-ассерта)

# При установке Docker-варианта:
/opt/mtproto-proxy/
├── docker-compose.yml              # Конфигурация контейнера (SECRET, WORKERS, INTERNAL_IP)
└── proxy_link.txt                  # Ссылка для подключения
```

---

## 🏗 Модульная архитектура

```
# ── Binary ──────────────────────────────────────────────────────
install_official.sh → sudo mtproxy install
  └─► run_install()                  [lib_install.sh]
        ├─ install_dependencies()
        ├─ clone_and_build_mtproxy()
        ├─ interactive_configuration() [lib_config.sh]
        │     └─ detect_sni_domains()  [lib_sni.sh]
        │        select_tls_domain()   [lib_sni.sh]
        ├─ create_systemd_service()
        │     └─ build_cmd()          [lib_common.sh]
        ├─ setup_config_updater()     cron 3:00
        └─ start_and_verify()

# ── Docker ──────────────────────────────────────────────────────
install_official.sh → sudo mtproxy install
  └─► run_docker_install()           [lib_docker.sh]
        ├─ _docker_install_engine()   Docker Engine (если не установлен)
        ├─ _docker_select_image_tag() выбор версии образа
        ├─ _docker_create_compose()   docker-compose.yml + INTERNAL_IP
        └─ open_ufw_port()            UFW правило

# ── Диспетчер ───────────────────────────────────────────────────
manage_mtproxy_official.sh
  ├─ sources: все 7 lib_*.sh модулей
  ├─ _detect_install_type()          binary / docker / both / none
  ├─ show_menu()                     Binary интерактивное меню
  ├─ show_docker_menu()              Docker интерактивное меню
  └─ CLI dispatch                    mtproxy <команда> (авторутинг)
```

Ключевые функции `lib_common.sh`, используемые всеми модулями:

| Функция | Описание |
|---------|----------|
| `build_cmd()` | Строит `ExecStart` из `.env` — исключает дублирование в 4 `change_*`-функциях |
| `apply_cmd_to_service()` | `sed ExecStart` + `daemon-reload` |
| `get_client_secret()` | ee/dd/plain-префикс → `$CLIENT_SECRET` |
| `get_server_addr()` | domain/NAT/IP логика → `$SERVER_ADDR` |

---

## 🔄 Обновления

```bash
# Конфиги Telegram — автоматически каждый день в 3:00 (cron)
sudo mtproxy update-config    # вручную

# Пересборка MTProxy из исходников
sudo mtproxy rebuild
```

---

## 🐛 Устранение проблем

**Сервис не запускается**
```bash
journalctl -u mtproxy -n 50
sudo mtproxy status
```

**Клиенты не подключаются**
```bash
ss -tuln | grep :443          # проверить порт
sudo ufw allow 443/tcp        # открыть firewall
sudo mtproxy stats            # статистика подключений
```

**Ошибка компиляции при установке**
```bash
sudo apt-get install build-essential libssl-dev zlib1g-dev
sudo mtproxy rebuild
```

---

## 📋 Требования

- **Ubuntu 20.04+** (рекомендуется 22.04 LTS)
- Открытый входящий порт (рекомендуется **443 TCP**)
- **Binary:** зависимости устанавливаются автоматически: `git` `curl` `build-essential` `libssl-dev` `zlib1g-dev` `xxd`
- **Docker:** Docker Engine ≥ 20.10 с плагином `compose` — устанавливается автоматически при выборе Docker-режима
