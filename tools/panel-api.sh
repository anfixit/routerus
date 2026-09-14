#!/bin/bash
# Запускает скрипт из tools/ с ключом и адресом панели Remnawave.
#   tools/panel-api.sh tools/nodes-status.py [аргументы]
# Откуда брать ключ — из ~/.config/routerus/panel.env (файл не в репозитории):
#   REMNAWAVE_API_URL=https://panel.example.com
#   REMNAWAVE_API_KEY=...                      # либо готовый токен,
#   PANEL_KEY_HOST=bots  PANEL_KEY_CONTAINER=remnawave_bot   # либо взять из контейнера бота по ssh
# Если задан PANEL_KEY_HOST, скрипт копируется туда и выполняется там (панель может
# пускать к API только с известных адресов).
set -euo pipefail
CFG="${ROUTERUS_PANEL_ENV:-$HOME/.config/routerus/panel.env}"
[[ -f "$CFG" ]] && set -a && . "$CFG" && set +a
S="$1"; shift
if [[ -n "${PANEL_KEY_HOST:-}" ]]; then
    C="${PANEL_KEY_CONTAINER:-remnawave_bot}"
    scp -q -o BatchMode=yes "$S" "$PANEL_KEY_HOST:/tmp/$(basename "$S")"
    ssh -o BatchMode=yes -o ConnectTimeout=20 "$PANEL_KEY_HOST" \
        "K=\$(docker exec $C printenv REMNAWAVE_API_KEY); U=\$(docker exec $C printenv REMNAWAVE_API_URL); python3 /tmp/$(basename "$S") \"\$K\" \"\$U\" $(printf '%q ' "$@")"
else
    : "${REMNAWAVE_API_KEY:?нет ключа: задай REMNAWAVE_API_KEY или PANEL_KEY_HOST в $CFG}"
    : "${REMNAWAVE_API_URL:?нет адреса панели: задай REMNAWAVE_API_URL в $CFG}"
    python3 "$S" "$REMNAWAVE_API_KEY" "$REMNAWAVE_API_URL" "$@"
fi
