# MTProxy — Официальная реализация от Telegram

[![GitHub](https://img.shields.io/badge/GitHub-MTProxy-blue?logo=github)](https://github.com/TelegramMessenger/MTProxy)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%2B-orange?logo=ubuntu)](https://ubuntu.com/)
[![License](https://img.shields.io/badge/License-GPL%20v2-green.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)

Автоматическая установка **официального MTProto прокси от Telegram** (C-реализация) на Ubuntu.

---

## 🚀 Быстрый старт

Оба скрипта должны лежать в одной папке — `install_official.sh` копирует `manage_mtproxy_official.sh` в `/opt/MTProxy/` в процессе установки.

```bash
git clone https://github.com/gopnikgame/MTProxy.git
cd MTProxy
sudo bash install_official.sh
```

После установки доступна глобальная команда:

```bash
mtproxy          # интерактивное меню
sudo mtproxy     # для операций, требующих root
```

---

## ✨ Возможности

| | |
|---|---|
| ⚡ **Производительность** | C-реализация, multi-core (воркеры), официальная поддержка Telegram |
| 🔒 **Безопасность** | Random Padding (защита от DPI), TLS/fakeTLS (`-D` домен), systemd hardening |
| 🛠 **Удобство** | Интерактивное меню, автообновление конфигов Telegram, симлинк `mtproxy` |
| 💰 **Монетизация** | AD Tag через [@MTProxybot](https://t.me/MTProxybot) |

---

## 🛠 Управление

`install_official.sh` создаёт симлинки `/usr/local/bin/mtproxy` и `/usr/local/bin/MTProxy`.

```bash
# Интерактивное меню
mtproxy

# Управление сервисом
mtproxy status / start / stop / restart

# Информация
mtproxy info             # Ссылка для подключения
mtproxy stats            # Статистика прокси
mtproxy logs             # Последние логи
mtproxy follow-logs      # Логи в реальном времени

# Настройка
mtproxy change-secret
mtproxy change-ad-tag
mtproxy change-ports
mtproxy change-workers
mtproxy update-config    # Обновить конфиги Telegram

# Обслуживание
mtproxy rebuild          # Пересборка из исходников
mtproxy uninstall        # Удаление MTProxy
```

---

## 🔗 Подключение клиентов

**С TLS-маскировкой** (домен + внешний masking-домен, флаг `-D`):
```
tg://proxy?server=proxy.example.com&port=443&secret=ee<32hex>
```

**С Random Padding** (без домена):
```
tg://proxy?server=1.2.3.4&port=443&secret=dd<32hex>
```

1. Откройте ссылку на устройстве с Telegram → нажмите **Connect Proxy**
2. Для монетизации зарегистрируйтесь в [@MTProxybot](https://t.me/MTProxybot) → `/newproxy`

> Префиксы секрета: `ee` = TLS/fakeTLS режим, `dd` = Random Padding

---

## 📋 Требования

- **Ubuntu 20.04+** (рекомендуется 22.04 LTS)
- Открытый порт (рекомендуется **443 TCP**)
- Зависимости устанавливаются автоматически: `git` `curl` `build-essential` `libssl-dev` `zlib1g-dev` `xxd`

---

## 📁 Файловая структура

```
/opt/MTProxy/
├── .env                           # Конфигурация MTProxy
├── manage_mtproxy_official.sh     # Скрипт управления
├── update-configs.sh              # Автообновление конфигов Telegram (cron)
├── objs/bin/mtproto-proxy         # Бинарник
├── run/
│   ├── proxy-secret               # Секрет Telegram
│   ├── proxy-multi.conf           # Серверы Telegram
│   └── secret.txt                 # Секрет пользователя
└── proxy_link.txt                 # Ссылка для подключения

/usr/local/bin/mtproxy             # Симлинк → manage_mtproxy_official.sh
/usr/local/bin/MTProxy             # Симлинк → manage_mtproxy_official.sh
/etc/systemd/system/mtproxy.service
/etc/sysctl.d/99-mtproxy-pid.conf  # kernel.pid_max=65535 (воркараунд MTProxy)
```

---

## 🔄 Обновления

```bash
# Конфиги Telegram — автоматически ежедневно в 3:00 (cron)
mtproxy update-config              # Вручную

# Пересборка MTProxy из исходников
mtproxy rebuild
```

---

## 🐛 Устранение проблем

**Сервис не запускается**
```bash
journalctl -u mtproxy -n 50
```

**Клиенты не подключаются**
```bash
ss -tuln | grep :443    # Проверить порт
sudo ufw allow 443/tcp  # Открыть firewall
```

