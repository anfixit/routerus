# tools/ — ввод и вывод нод через API панели

Скрипты вокруг `deploy-remnanode.sh`: то, что руками делается в панели
Remnawave, в мониторинге и при проверке. Все `*.py` принимают первыми двумя
аргументами `KEY URL` панели; обёртка `panel-api.sh` подставляет их сама.

## Настройка

`~/.config/routerus/panel.env` (в репозиторий не попадает):

```
REMNAWAVE_API_URL=https://panel.example.com
REMNAWAVE_API_KEY=...            # готовый токен панели,
PANEL_KEY_HOST=bots              # либо ssh-ярлык сервера, где в контейнере
PANEL_KEY_CONTAINER=remnawave_bot  # бота лежит REMNAWAVE_API_KEY (скрипт выполнится там)
SQUAD_NAME=Default-Squad         # сквад, в который попадают входы новых нод
PROMETHEUS_ALLOW_IP=1.2.3.4      # сервер Prometheus, которому открывать node_exporter
```

## Ввод ноды

1. Ключ на сервер: `ssh-copy-id root@IP`. A-запись домена; дождаться, пока
   `dig @1.1.1.1` и `dig @8.8.8.8` отдадут IP, иначе не выпустится сертификат.
2. На сервере в tmux: `REMNANODE_IMAGE=remnawave/node:X.Y.Z bash deploy-remnanode.sh`
   (пинуй ту версию, что стоит на остальном флоте). После фазы 3 sshd уезжает
   на новый порт, дальше `ssh -p PORT admin@IP` и `sudo tmux attach`.
3. На паузе «Профиль создан?» забрать `/opt/remnanode/config-profile.json` и:
   ```bash
   tools/panel-api.sh tools/panel-new-node.py ИМЯ IP CC ДОМЕН НОМЕР профиль.json ПРОВАЙДЕР 2026-12-06
   ```
   Создаёт профиль, ноду, два хоста с тегами `CC_MOB`/`CC_WIFI` (исключены из
   XRAY_JSON, их подтягивает шаблон Country balancer), добавляет входы в сквад,
   привязывает биллинг и последней строкой печатает `SECRET_KEY` для скрипта.
   Идемпотентен, при таймауте панели просто повторить.
4. Мониторинг: `sudo bash tools/install-node-exporter.sh IP_PROMETHEUS [порт]`
   на ноде, `sudo python3 tools/prom-add.py ИМЯ IP CC [порт_exporter] [порт_xray]`
   на сервере Prometheus, затем `docker kill -s HUP prometheus`.
5. Проверка, что нода реально работает, а не только зелёная:
   ```bash
   tools/panel-api.sh tools/nodes-status.py            # панель видит ноду
   tools/panel-api.sh tools/sub-check.py ДОМЕН          # ссылки в base64-подписке, pbk = PUBLIC_KEY ноды
   tools/panel-api.sh tools/happ-check.py Страна        # кто внутри балансировщика страны (JSON, как видит Happ)
   tools/panel-api.sh tools/xray-test.py ДОМЕН          # xray-core в docker ходит через ноду, внешний IP = IP ноды
   ```
   `xray-test.py` нужен docker на той машине, где выполняется (см. PANEL_KEY_HOST).

## Вывод ноды

```bash
tools/panel-api.sh tools/panel-remove-node.py имя1,имя2         # что затронет
tools/panel-api.sh tools/panel-remove-node.py имя1,имя2 apply   # выполнить
```

Сначала слепок в `~/backup-profiles/`, затем виртуальные хосты балансировщика,
привязанные к входам удаляемых нод, перевешиваются на живую ноду той же
страны (иначе страна пропадёт из JSON-подписки), потом удаляются хосты, ноды,
профили. Из Prometheus и `~/.ssh/config` ноду убрать руками.

## Прочее

`hosts-map.py` печатает каждый хост с профилем и входом, к которому он
привязан: первое, что смотреть, если сервер «есть в панели, но нет у людей».
