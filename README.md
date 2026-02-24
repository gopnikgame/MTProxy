# MTProxy - Официальная реализация от Telegram

[![GitHub](https://img.shields.io/badge/GitHub-MTProxy-blue?logo=github)](https://github.com/TelegramMessenger/MTProxy)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%2B-orange?logo=ubuntu)](https://ubuntu.com/)
[![License](https://img.shields.io/badge/License-GPL%20v2-green.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)

**Официальный MTProto прокси от Telegram** с автоматической установкой и интеграцией с Remnawave для Ubuntu.

---

## 🚀 Быстрый старт

### Автоматическая установка (рекомендуется)

**Способ 1** - Скачать и выполнить напрямую:
```bash
curl -sSL https://raw.githubusercontent.com/gopnikgame/MTProxy/master/install_official.sh | sudo bash
```

**Способ 2** - Скачать файл с перезаписью:
```bash
wget -O install_official.sh https://raw.githubusercontent.com/gopnikgame/MTProxy/master/install_official.sh
sudo bash install_official.sh
```

### С интеграцией Remnawave (Nginx SNI)

```bash
# 1. Установить MTProxy
sudo bash install_official.sh

# 2. Настроить интеграцию с Remnawave
sudo bash setup_remnawave_integration.sh
```

**Готово!** 🎉 Получите ссылку для подключения: `tg://proxy?server=...&port=443&secret=...`

---

## ✨ Особенности

### ✅ Официальная реализация
- Написана на C (высокая производительность)
- Поддержка Multi-core (несколько воркеров)
- Официальная поддержка от Telegram
- Регулярные обновления

### ✅ Защита и безопасность
- Random Padding (защита от DPI)
- Поддержка TLS (HTTPS маскировка)
- Множественные секреты
- Security hardening в systemd

### ✅ Интеграция с Remnawave
- Nginx SNI (мультидоменность)
- Автоматическая настройка SSL
- Совместная работа с другими сервисами
- Единая точка входа (порт 443)

### ✅ Удобство использования
- Автоматическая установка одной командой
- Интерактивные скрипты настройки
- Systemd интеграция (автозапуск)
- Скрипт управления с меню
- Автообновление конфигурации Telegram

### ✅ Монетизация
- Поддержка AD Tag
- Регистрация в @MTProxybot
- Статистика использования

---

## 🛠 Управление

### Интерактивное меню

```bash
bash manage_mtproxy_official.sh
```

### Основные команды

```bash
# Статус и управление
bash manage_mtproxy_official.sh status      # Статус сервиса
bash manage_mtproxy_official.sh start       # Запустить
bash manage_mtproxy_official.sh stop        # Остановить
bash manage_mtproxy_official.sh restart     # Перезапустить

# Информация и мониторинг
bash manage_mtproxy_official.sh info        # Показать ссылку подключения
bash manage_mtproxy_official.sh stats       # Статистика прокси
bash manage_mtproxy_official.sh logs        # Просмотр логов

# Настройка
bash manage_mtproxy_official.sh change-secret   # Изменить секрет
bash manage_mtproxy_official.sh change-ad-tag   # Изменить AD Tag
bash manage_mtproxy_official.sh change-ports    # Изменить порты
bash manage_mtproxy_official.sh change-workers  # Изменить воркеры

# Обновление
bash manage_mtproxy_official.sh update-config  # Обновить конфигурацию Telegram
bash manage_mtproxy_official.sh rebuild        # Пересобрать MTProxy
```

### Systemd

```bash
systemctl status mtproxy      # Статус
systemctl restart mtproxy     # Перезапуск
journalctl -u mtproxy -f      # Логи
```

---

## 📋 Требования

### Операционная система
- **Ubuntu 20.04+** (рекомендуется 22.04 LTS)

### Зависимости (устанавливаются автоматически)
- `git`, `curl`, `build-essential`
- `libssl-dev`, `zlib1g-dev`
- `certbot`, `xxd`

### Сеть
- Открытый порт 443 (TCP)
- Доменное имя (для интеграции с Remnawave)

---

## 🔗 Подключение клиентов

### Ссылка для подключения

```
tg://proxy?server=proxy.example.com&port=443&secret=dd...
```

### Инструкция для пользователей
1. Откройте ссылку на устройстве с Telegram
2. Нажмите "Connect Proxy"
3. Готово!

### Регистрация в @MTProxybot

1. Откройте [@MTProxybot](https://t.me/MTProxybot)
2. `/newproxy`
3. Отправьте ссылку прокси
4. Получите AD Tag для монетизации

---

## 📊 Архитектура

### Standalone режим
```
Internet:443 → MTProxy
```

### С интеграцией Remnawave (Nginx SNI)
```
Internet:443 → Nginx (SNI routing) → Backend → MTProxy
                 ↓
            [Другие сервисы]
            - XRay Reality
            - Panel
            - etc.
```

---

## 🔄 Обновление

### Автоматическое обновление конфигурации Telegram

Настроено по умолчанию (cron, каждый день в 3:00):
```bash
# Проверить cron
crontab -l | grep update-configs
```

### Ручное обновление
```bash
bash manage_mtproxy_official.sh update-config
```

### Обновление MTProxy (пересборка)
```bash
bash manage_mtproxy_official.sh rebuild
```

---

## 🐛 Устранение проблем

### Проблемы с установкой зависимостей (apt)

Если возникает ошибка `systemd-sysv` или проблемы с зависимостями пакетов:

```bash
# Исправить broken packages
sudo apt-get install -f
sudo dpkg --configure -a

# Обновить систему
sudo apt-get update
sudo apt-get upgrade -y

# Повторить установку
sudo bash install_official.sh
```

### Сервис не запускается
```bash
# Проверить логи
journalctl -u mtproxy -n 50

# Перезапустить
systemctl restart mtproxy
```

### Клиенты не могут подключиться
```bash
# Проверить порт
netstat -tuln | grep :443

# Открыть firewall
sudo ufw allow 443/tcp
```

### Подробное руководство
См. раздел "Устранение проблем" в [README_OFFICIAL.md](README_OFFICIAL.md)

---

## 📁 Структура файлов

```
/opt/MTProxy/
├── .env                      # Конфигурация
├── objs/bin/mtproto-proxy    # Бинарник
├── run/                      # Рабочая директория
│   ├── proxy-secret          # Секрет Telegram
│   ├── proxy-multi.conf      # Конфигурация серверов
│   └── secret.txt            # Секрет пользователя
└── proxy_link.txt            # Ссылка для подключения

/etc/systemd/system/
└── mtproxy.service           # Systemd сервис
```

---

## 🤝 Вклад в проект

Вклад приветствуется! Пожалуйста:
1. Fork репозитория
2. Создайте ветку (`git checkout -b feature/amazing-feature`)
3. Commit изменения (`git commit -m 'Add amazing feature'`)
4. Push в ветку (`git push origin feature/amazing-feature`)
5. Откройте Pull Request

---

## 📄 Лицензия

- **MTProxy**: GPL v2 и LGPL v2 (от Telegram)
- **Скрипты установки**: MIT License

---

## 📖 Оригинальная документация Telegram

Ниже приведена оригинальная документация от Telegram для ручной установки.

<details>
<summary><b>Развернуть оригинальную документацию</b></summary>

## Building
Install dependencies, you would need common set of tools for building from source, and development packages for `openssl` and `zlib`.

On Debian/Ubuntu:
```bash
apt install git curl build-essential libssl-dev zlib1g-dev
```
On CentOS/RHEL:
```bash
yum install openssl-devel zlib-devel
yum groupinstall "Development Tools"
```

Clone the repo:
```bash
git clone https://github.com/TelegramMessenger/MTProxy
cd MTProxy
```

To build, simply run `make`, the binary will be in `objs/bin/mtproto-proxy`:

```bash
make && cd objs/bin
```

If the build has failed, you should run `make clean` before building it again.

## Running
1. Obtain a secret, used to connect to telegram servers.
```bash
curl -s https://core.telegram.org/getProxySecret -o proxy-secret
```
2. Obtain current telegram configuration. It can change (occasionally), so we encourage you to update it once per day.
```bash
curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf
```
3. Generate a secret to be used by users to connect to your proxy.
```bash
head -c 16 /dev/urandom | xxd -ps
```
4. Run `mtproto-proxy`:
```bash
./mtproto-proxy -u nobody -p 8888 -H 443 -S <secret> --aes-pwd proxy-secret proxy-multi.conf -M 1
```
... where:
- `nobody` is the username. `mtproto-proxy` calls `setuid()` to drop privileges.
- `443` is the port, used by clients to connect to the proxy.
- `8888` is the local port. You can use it to get statistics from `mtproto-proxy`. Like `wget localhost:8888/stats`. You can only get this stat via loopback.
- `<secret>` is the secret generated at step 3. Also you can set multiple secrets: `-S <secret1> -S <secret2>`.
- `proxy-secret` and `proxy-multi.conf` are obtained at steps 1 and 2.
- `1` is the number of workers. You can increase the number of workers, if you have a powerful server.

Also feel free to check out other options using `mtproto-proxy --help`.

5. Generate the link with following schema: `tg://proxy?server=SERVER_NAME&port=PORT&secret=SECRET` (or let the official bot generate it for you).
6. Register your proxy with [@MTProxybot](https://t.me/MTProxybot) on Telegram.
7. Set received tag with arguments: `-P <proxy tag>`
8. Enjoy.

## Random padding
Due to some ISPs detecting MTProxy by packet sizes, random padding is
added to packets if such mode is enabled.

It's only enabled for clients which request it.

Add `dd` prefix to secret (`cafe...babe` => `ddcafe...babe`) to enable
this mode on client side.

## Systemd example configuration
1. Create systemd service file (it's standard path for the most Linux distros, but you should check it before):
```bash
nano /etc/systemd/system/MTProxy.service
```
2. Edit this basic service (especially paths and params):
```bash
[Unit]
Description=MTProxy
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/MTProxy
ExecStart=/opt/MTProxy/mtproto-proxy -u nobody -p 8888 -H 443 -S <secret> -P <proxy tag> <other params>
Restart=on-failure

[Install]
WantedBy=multi-user.target
```
3. Reload daemons:
```bash
systemctl daemon-reload
```
4. Test fresh MTProxy service:
```bash
systemctl restart MTProxy.service
# Check status, it should be active
systemctl status MTProxy.service
```
5. Enable it, to autostart on boot:
```bash
systemctl enable MTProxy.service
```

</details>

---

## ⭐ Поддержка проекта

Если проект помог вам, поставьте звезду ⭐ на GitHub!

---

## ✉️ Контакты

- **Issues**: [GitHub Issues](https://github.com/gopnikgame/MTProxy/issues)
- **Telegram**: [@gopnikgame](https://t.me/gopnikgame)
- **MTProxybot**: [@MTProxybot](https://t.me/MTProxybot)

---

**MTProxy Official** - Автоматическая установка официального MTProxy от Telegram для Ubuntu
```
5. Enable it, to autostart service after reboot:
```bash
systemctl enable MTProxy.service
```

## Docker image
Telegram is also providing [official Docker image](https://hub.docker.com/r/telegrammessenger/proxy/).
Note: the image is outdated.
