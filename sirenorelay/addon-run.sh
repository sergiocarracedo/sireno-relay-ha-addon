#!/bin/bash
set -euo pipefail

CONFIG=/data/sirenorelay/.config/sirenorelay/config.yml
CONFIG_DIR=/data/sirenorelay/.config/sirenorelay
LEGACY_CONFIG_DIR=/root/.config/sirenorelay
SETTINGS=/data/sirenorelay/ui-settings.json
RUN_DIR=/run/sirenorelay
mkdir -p "$RUN_DIR" /run/nginx /data/sirenorelay
chown -R sirenorelay:sirenorelay /data/sirenorelay
chown -R www-data:www-data /run/nginx

if [[ ! -f "$CONFIG" && -f "$LEGACY_CONFIG_DIR/config.yml" ]]; then
  echo "Migrating SirenoRELAY configuration from the legacy onboarding location."
  mkdir -p "$CONFIG_DIR"
  cp -a "$LEGACY_CONFIG_DIR/." "$CONFIG_DIR/"
  sed -i "s|$LEGACY_CONFIG_DIR/|$CONFIG_DIR/|g" "$CONFIG"
  chown -R sirenorelay:sirenorelay "$CONFIG_DIR"
  find "$CONFIG_DIR" -type d -exec chmod 700 {} +
  find "$CONFIG_DIR" -type f -exec chmod 600 {} +
fi

MCP_PORT="$(jq -r '.mcp_port // 8081' /data/options.json 2>/dev/null || echo 8081)"
if ! [[ "$MCP_PORT" =~ ^[1-9][0-9]{0,4}$ ]] || ((10#$MCP_PORT > 65535)); then
  echo "Invalid MCP bridge port in App configuration; using 8081." >&2
  MCP_PORT=8081
fi

# Apps can reach each other by their Supervisor-managed hostname on the
# internal network. Never fall back to the container hostname: it is not a
# stable or necessarily resolvable App address.
SIRENORELAY_APP_HOSTNAME=""
if [[ -n "${SUPERVISOR_TOKEN:-}" ]]; then
  SIRENORELAY_APP_HOSTNAME="$(curl --fail --silent --show-error --max-time 2 \
    -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
    http://supervisor/addons/self/info 2>/dev/null | jq -r '.data.hostname // empty' 2>/dev/null || true)"
fi
if [[ "$SIRENORELAY_APP_HOSTNAME" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  export SIRENORELAY_APP_HOSTNAME
  export SIRENORELAY_ATTACHMENT_BASE_URL="http://$SIRENORELAY_APP_HOSTNAME:$MCP_PORT"
else
  unset SIRENORELAY_APP_HOSTNAME
  unset SIRENORELAY_ATTACHMENT_BASE_URL
  echo "Could not determine the Supervisor App hostname; attachment download URLs will remain disabled unless attachments.base_url is configured." >&2
fi

python3 /usr/local/bin/web.py &
web_pid=$!

run_relay() {
  while true; do
    if [[ -f "$CONFIG" ]]; then
      runuser -u sirenorelay -- env HOME=/data/sirenorelay XDG_CONFIG_HOME=/data/sirenorelay/.config SIRENORELAY_ATTACHMENT_BASE_URL="${SIRENORELAY_ATTACHMENT_BASE_URL:-}" \
        sirenorelay serve --config "$CONFIG" || true
    else
      echo "Waiting for first-time onboarding."
    fi
    sleep 2
  done
}

run_relay &
relay_pid=$!

# The v1.4 MCP SDK rejects non-loopback Host headers on a loopback listener to
# prevent DNS rebinding. Other HA Apps use this listener, so terminate their
# request here and forward a loopback Host header to the relay.
cat > "$RUN_DIR/mcp-bridge.conf" <<EOF
server {
  listen $MCP_PORT;
  location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Host 127.0.0.1:8080;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF

ttyd -W -i 127.0.0.1 -p 7681 -b /terminal /usr/local/bin/sirenorelay-terminal.sh &
terminal_pid=$!
ttyd -W -i 127.0.0.1 -p 7682 -b /onboard /usr/local/bin/sirenorelay-onboard.sh &
onboard_pid=$!

if [[ "$(jq -r '.lan_tls_enabled // false' "$SETTINGS" 2>/dev/null || echo false)" == true ]]; then
  certificate="$(jq -r '.tls_certificate // empty' "$SETTINGS")"
  key="$(jq -r '.tls_key // empty' "$SETTINGS")"
  if [[ "$certificate" =~ ^[A-Za-z0-9._-]+$ && "$key" =~ ^[A-Za-z0-9._-]+$ && -r "/ssl/$certificate" && -r "/ssl/$key" ]]; then
    cat > "$RUN_DIR/tls.conf" <<EOF
server {
  listen 8443 ssl;
  ssl_certificate /ssl/$certificate;
  ssl_certificate_key /ssl/$key;
  location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Host 127.0.0.1:8080;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF
  else
    echo "LAN TLS is enabled but the configured certificate or key is unavailable; refusing to expose port 8443." >&2
  fi
fi

nginx -c /etc/nginx/sirenorelay-ingress.conf -g 'daemon off;' &
nginx_pid=$!

cleanup() {
  kill "$web_pid" "$relay_pid" "$terminal_pid" "$onboard_pid" "$nginx_pid" 2>/dev/null || true
  wait "$web_pid" "$relay_pid" "$terminal_pid" "$onboard_pid" "$nginx_pid" 2>/dev/null || true
}
trap cleanup EXIT
wait -n "$web_pid" "$terminal_pid" "$onboard_pid" "$nginx_pid"
