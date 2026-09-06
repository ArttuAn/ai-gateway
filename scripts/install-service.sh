#!/usr/bin/env bash
# Install the gateway as a systemd --user service: survives reboot, restarts
# on crash. Replaces the nohup launcher as the supervised way to run it.
set -euo pipefail
cd "$(dirname "$0")/.."
DIR="$PWD"
UNIT="$HOME/.config/systemd/user/ai-gateway.service"
mkdir -p "$(dirname "$UNIT")" logs

[ -r "$HOME/.config/ai-gateway/secrets.env" ] || {
  echo "missing ~/.config/ai-gateway/secrets.env (ANTHROPIC_API_KEY=...)" >&2; exit 1; }

cat > "$UNIT" <<UNITEOF
[Unit]
Description=AI Gateway (LiteLLM proxy: local + cloud LLM routing)
Documentation=file://$DIR/README.md
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$DIR
# .env carries non-secret config; the credential lives outside the repo.
EnvironmentFile=$DIR/.env
EnvironmentFile=$HOME/.config/ai-gateway/secrets.env
Environment=LITELLM_MODE=PRODUCTION
Environment=LITELLM_LOG=ERROR

# Postgres is a Docker container with its own restart policy, but systemd has
# no ordering relationship to it — so wait for the database rather than
# crash-looping on boot.
ExecStartPre=/bin/bash -c 'for i in \$(seq 1 60); do docker exec \$PG_CONTAINER pg_isready -U litellm -d litellm >/dev/null 2>&1 && exit 0; docker start \$PG_CONTAINER >/dev/null 2>&1 || true; sleep 2; done; echo "postgres never became ready" >&2; exit 1'
ExecStart=$DIR/.venv/bin/litellm --config $DIR/config/config.yaml --host \${GATEWAY_HOST} --port \${GATEWAY_PORT}

Restart=on-failure
RestartSec=5
StandardOutput=append:$DIR/logs/gateway.log
StandardError=append:$DIR/logs/gateway.log

[Install]
WantedBy=default.target
UNITEOF

# Stop any nohup-launched instance so the port is free.
./scripts/stop.sh >/dev/null 2>&1 || true

systemctl --user daemon-reload
systemctl --user enable --now ai-gateway.service

# Without lingering, user services stop at logout and don't start at boot.
if loginctl show-user "$USER" --property=Linger 2>/dev/null | grep -q 'Linger=yes'; then
  echo "lingering: already enabled (starts at boot)"
elif loginctl enable-linger "$USER" 2>/dev/null; then
  echo "lingering: enabled (starts at boot)"
else
  echo "lingering: NOT enabled — needs 'sudo loginctl enable-linger $USER'"
  echo "           without it the gateway starts at login rather than at boot."
fi

sleep 3
systemctl --user --no-pager status ai-gateway.service | head -6
