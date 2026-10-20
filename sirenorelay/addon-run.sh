#!/bin/bash
set -euo pipefail

CONFIG=/data/sirenorelay/.config/sirenorelay/config.yml
RUN_DIR=/run/sirenorelay
mkdir -p "$RUN_DIR" /run/nginx /data/sirenorelay
chown -R sirenorelay:sirenorelay /data/sirenorelay
chown -R www-data:www-data /run/nginx

python3 /usr/local/bin/config-sync.py &
sync_pid=$!

run_relay() {
  while true; do
    if [[ -f "$CONFIG" ]]; then
      runuser -u sirenorelay -- env HOME=/data/sirenorelay XDG_CONFIG_HOME=/data/sirenorelay/.config \
        sirenorelay serve --config "$CONFIG" || true
    else
      echo "Waiting for onboarding or Configuration-tab YAML."
    fi
    sleep 2
  done
}

run_relay &
relay_pid=$!

# Other Home Assistant add-ons reach this bridge, not the relay's loopback listener.
socat TCP-LISTEN:8081,fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:8080 &
bridge_pid=$!

ttyd -W -i 127.0.0.1 -p 7681 -b /terminal /usr/local/bin/sirenorelay-terminal.sh &
terminal_pid=$!
ttyd -W -i 127.0.0.1 -p 7682 -b /onboard /usr/local/bin/sirenorelay-onboard.sh &
onboard_pid=$!

if [[ "$(jq -r '.lan_tls_enabled // false' /data/options.json 2>/dev/null || echo false)" == true ]]; then
  certificate="$(jq -r '.tls_certificate // empty' /data/options.json)"
  key="$(jq -r '.tls_key // empty' /data/options.json)"
  if [[ "$certificate" =~ ^[A-Za-z0-9._-]+$ && "$key" =~ ^[A-Za-z0-9._-]+$ && -r "/ssl/$certificate" && -r "/ssl/$key" ]]; then
    cat > "$RUN_DIR/tls.conf" <<EOF
server {
  listen 8443 ssl;
  ssl_certificate /ssl/$certificate;
  ssl_certificate_key /ssl/$key;
  location / { proxy_pass http://127.0.0.1:8080; proxy_http_version 1.1; proxy_set_header Host \$host; }
}
EOF
  else
    echo "LAN TLS is enabled but the configured certificate or key is unavailable; refusing to expose port 8443." >&2
  fi
fi

nginx -c /etc/nginx/sirenorelay-ingress.conf -g 'daemon off;' &
nginx_pid=$!

cleanup() {
  kill "$sync_pid" "$relay_pid" "$bridge_pid" "$terminal_pid" "$onboard_pid" "$nginx_pid" 2>/dev/null || true
  wait "$sync_pid" "$relay_pid" "$bridge_pid" "$terminal_pid" "$onboard_pid" "$nginx_pid" 2>/dev/null || true
}
trap cleanup EXIT
wait -n "$bridge_pid" "$terminal_pid" "$onboard_pid" "$nginx_pid"
