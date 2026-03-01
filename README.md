# MTProxy — Официальная реализация от Telegram

[![GitHub](https://img.shields.io/badge/GitHub-MTProxy-blue?logo=github)](https://github.com/TelegramMessenger/MTProxy)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%2B-orange?logo=ubuntu)](https://ubuntu.com/)
[![License](https://img.shields.io/badge/License-GPL%20v2-green.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)

Автоматическая установка **официального MTProto прокси от Telegram** (C-реализация) с интеграцией в стек Remnawave / Nginx для Ubuntu.

---

## 🚀 Быстрый старт

Все три скрипта должны лежать в одной папке — `install_official.sh` копирует их в `/opt/MTProxy/` в процессе установки.

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
| 🔒 **Безопасность** | Random Padding (защита от DPI), TLS/fakeTLS, systemd hardening |
| 🌐 **Интеграция** | Nginx SNI + Remnawave: единый порт 443 для всех сервисов на сервере |
| 🛠 **Удобство** | Интерактивное меню, автообновление конфигов Telegram, симлинк `mtproxy` |
| 💰 **Монетизация** | AD Tag через [@MTProxybot](https://t.me/MTProxybot) |

---

## 🛠 Управление

`install_official.sh` создаёт симлинк `/usr/local/bin/mtproxy → /opt/MTProxy/manage_mtproxy_official.sh`.

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
sudo mtproxy setup-remnawave  # Настроить интеграцию с Remnawave
mtproxy uninstall
```

---

## 🔗 Подключение клиентов

```
tg://proxy?server=proxy.example.com&port=443&secret=ee<32hex>
```

1. Откройте ссылку на устройстве с Telegram → нажмите **Connect Proxy**
2. Для монетизации зарегистрируйтесь в [@MTProxybot](https://t.me/MTProxybot) → `/newproxy`

> Префикс секрета: `ee` = TLS/fakeTLS режим (при работе через Nginx SNI), `dd` = Random Padding

---

## 🌐 Интеграция с Remnawave (Nginx SNI)

> Nginx Remnawave работает в Docker-контейнере `remnawave-nginx` с `network_mode: host`.  
> Домены Remnawave (XRay Reality, панель) **требуют** `proxy_protocol` — MTProxy его не поддерживает, поэтому используется relay-сервер.

### Архитектура

```
Internet :443
└─► Nginx Docker  (network_mode: host, ssl_preread SNI, proxy_protocol ON)
     ├─► ru3-x.vline.online ──► nginx_backend:8443   (proxy_protocol ✓)
     ├─► ru3.vline.online   ──► xray_reality:9443    (proxy_protocol ✓)
     └─► proxy.example.com ──► mtproxy_relay:11443
                                       │
                          set_real_ip_from (strips PROXY header)
                                       │
                              MTProxy systemd :10443
                              (-D proxy.example.com, fakeTLS)
```

`ngx_stream_realip_module` входит в официальный образ `nginx:1.29.1` — дополнительная установка не требуется.

### Запуск

```bash
sudo mtproxy setup-remnawave
# или напрямую:
sudo bash /opt/MTProxy/setup_remnawave_integration.sh
```

Скрипт автоматически:
- Запрашивает домен и backend-порт
- Получает SSL-сертификат (Let's Encrypt, webroot — без остановки сервисов)
- Обновляет `stream.conf` (SNI map + relay-сервер для MTProxy)
- Обновляет `sites-available/80.conf` (ACME challenge + HTTPS redirect)
- Добавляет `-D domain` в systemd-сервис MTProxy (fakeTLS режим)
- Перезагружает Nginx: `docker exec remnawave-nginx nginx -s reload`

### Управление Nginx (Docker)

```bash
docker exec remnawave-nginx nginx -t          # Проверить конфиг
docker exec remnawave-nginx nginx -s reload   # Graceful reload (без разрыва соединений)
docker logs remnawave-nginx -f                # Логи контейнера
```

---

## 📋 Требования

- **Ubuntu 20.04+** (рекомендуется 22.04 LTS)
- Открытый порт **443 TCP**
- Доменное имя, указывающее на сервер (для Remnawave-интеграции)
- Docker + Remnawave запущены (для SNI-интеграции)
- Зависимости устанавливаются автоматически: `git` `curl` `build-essential` `libssl-dev` `zlib1g-dev` `certbot` `xxd`

---

## 📁 Файловая структура

```
/opt/MTProxy/
├── .env                           # Конфигурация MTProxy
├── manage_mtproxy_official.sh     # Скрипт управления
├── setup_remnawave_integration.sh # Скрипт интеграции с Remnawave
├── update-configs.sh              # Автообновление конфигов Telegram (cron)
├── objs/bin/mtproto-proxy         # Бинарник
├── run/
│   ├── proxy-secret               # Секрет Telegram
│   ├── proxy-multi.conf           # Серверы Telegram
│   └── secret.txt                 # Секрет пользователя
└── proxy_link.txt                 # Ссылка для подключения

/usr/local/bin/mtproxy             # Симлинк → manage_mtproxy_official.sh
/etc/systemd/system/mtproxy.service

/opt/remnawave/                    # Remnawave (docker-compose)
├── stream.conf                    # SNI routing + MTProxy relay
└── sites-available/
    ├── 80.conf                    # ACME challenge + HTTPS redirect
    └── <domain>.conf              # HTTPS virtual hosts
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

**Ошибка конфигурации Nginx**
```bash
docker exec remnawave-nginx nginx -t
# Резервные копии: /opt/remnawave/stream.conf.backup.*
```

**Broken apt-пакеты**
```bash
sudo apt-get install -f && sudo dpkg --configure -a
```

---

## 🤝 Вклад в проект

1. Fork репозитория
2. Создайте ветку (`git checkout -b feature/amazing-feature`)
3. Commit + Push → откройте Pull Request

---

## 📄 Лицензия

- **MTProxy**: GPL v2 / LGPL v2 (Telegram)
- **Скрипты установки**: MIT

---

> 🤖 *README отредактирован с помощью ИИ — с любовью и заботой о читаемости.*

---

**Issues** · [GitHub](https://github.com/gopnikgame/MTProxy/issues) &nbsp;|&nbsp;
**Telegram** · [@gopnikgame](https://t.me/gopnikgame) &nbsp;|&nbsp;
**MTProxybot** · [@MTProxybot](https://t.me/MTProxybot)
