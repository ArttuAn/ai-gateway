#!/usr/bin/env bash
# Single entry point for gateway lifecycle. Prefers the systemd unit when it is
# installed (supervised, restarts on failure, survives reboot) and falls back to
# the nohup launcher otherwise, so both paths never run at once.
set -euo pipefail
cd "$(dirname "$0")/.."
have_unit() { systemctl --user list-unit-files ai-gateway.service >/dev/null 2>&1 \
              && systemctl --user cat ai-gateway.service >/dev/null 2>&1; }

case "${1:-start}" in
  start)
    if have_unit; then
      systemctl --user start ai-gateway.service
      set -a; source .env; set +a
      for i in $(seq 1 90); do
        curl -sf -m 2 "http://$GATEWAY_HOST:$GATEWAY_PORT/health/liveliness" >/dev/null 2>&1 \
          && { echo "gateway (systemd) → http://$GATEWAY_HOST:$GATEWAY_PORT"; exit 0; }
        sleep 1
      done
      echo "gateway did not become healthy; systemctl --user status ai-gateway" >&2; exit 1
    else
      exec ./scripts/start.sh
    fi ;;
  stop)
    if have_unit; then systemctl --user stop ai-gateway.service && echo "gateway (systemd) stopped"
    else exec ./scripts/stop.sh; fi ;;
  restart) "$0" stop || true; exec "$0" start ;;
  status)
    if have_unit; then systemctl --user --no-pager status ai-gateway.service | head -8
    else ./scripts/health-local.sh; fi ;;
  *) echo "usage: $0 {start|stop|restart|status}" >&2; exit 2 ;;
esac
