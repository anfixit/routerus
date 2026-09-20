#!/bin/bash
# Управление deploy-remnanode.sh, запущенным на сервере в tmux-сессии deploy.
#   remote-tmux.sh TARGET send "текст" [пауза_сек] [строк]   — ввести строку и показать хвост экрана
#   remote-tmux.sh TARGET wait "regex" [макс_сек]            — ждать строку на экране (или SCRIPT_EXITED / ✖)
#   remote-tmux.sh TARGET show [строк]                        — показать хвост экрана
# TARGET: root@IP до фазы 3 скрипта, затем admin@IP:PORT или ssh-ярлык (sudo подставится сам).
set -euo pipefail
T="$1"; CMD="$2"; shift 2
PORT=""; HOST="$T"
if [[ "$T" == *:* ]]; then PORT="${T##*:}"; HOST="${T%:*}"; fi
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10); [[ -n "$PORT" ]] && SSH+=(-p "$PORT")
SUDO="sudo "; [[ "$HOST" == root@* ]] && SUDO=""
show() { "${SSH[@]}" "$HOST" "${SUDO}tmux capture-pane -pt deploy -S -60" 2>/dev/null | grep -v '^\s*$' | tail -"${1:-30}"; }
case "$CMD" in
  send) TXT="$1"; SL="${2:-4}"; N="${3:-30}"
        "${SSH[@]}" "$HOST" "${SUDO}tmux send-keys -t deploy -l -- $(printf '%q' "$TXT"); ${SUDO}tmux send-keys -t deploy Enter"; sleep "$SL"; show "$N" ;;
  wait) RE="$1"; MAX="${2:-900}"
        for _ in $(seq 1 $((MAX/10))); do out=$(show 40 || true)
          if echo "$out" | grep -qE "$RE|SCRIPT_EXITED|✖"; then echo "$out" | tail -25; exit 0; fi; sleep 10; done
        echo TIMEOUT; exit 1 ;;
  show) show "${1:-30}" ;;
  *) echo "неизвестная команда: $CMD"; exit 2 ;;
esac
