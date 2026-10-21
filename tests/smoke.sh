#!/bin/bash
set -euo pipefail

name="sirenorelay-ha-smoke-$$"
volume="sirenorelay-ha-smoke-data-$$"
config_file="$(mktemp "${TMPDIR:-/tmp}/sirenorelay-config.XXXXXX")"
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; docker volume rm -f "$volume" >/dev/null 2>&1 || true; rm -f "$config_file"' EXIT

docker volume create "$volume" >/dev/null
docker run -d --rm --name "$name" -v "$volume:/data" sirenorelay-ha-addon:test >/dev/null

for attempt in {1..20}; do
  if docker exec "$name" curl -fsS http://127.0.0.1:8099/ -o /dev/null 2>/dev/null; then
    break
  fi
  sleep 1
done

docker exec "$name" sh -c 'test "$(id -u sirenorelay)" = 10001 && command -v sirenorelay && command -v himalaya && command -v socat && command -v ttyd'
docker exec "$name" sh -c 'curl -fsS http://127.0.0.1:8099/ -o /tmp/ingress.html && grep -Fq "Mail, on your terms." /tmp/ingress.html'
docker exec "$name" sh -c 'curl -fsS http://127.0.0.1:8099/terminal/ -o /tmp/terminal.html && grep -Fq ttyd /tmp/terminal.html'
docker exec "$name" sh -c 'grep -Fq "FIRST-TIME SETUP" /tmp/ingress.html && curl -fsS http://127.0.0.1:8099/onboard/ -o /tmp/onboard.html && grep -Fq ttyd /tmp/onboard.html && test -f /usr/share/sirenorelay-web/vs/loader.js'
docker exec "$name" sh -c '! ss -ltn | grep -q ":8443"'

cat <<'EOF' | docker exec -i "$name" python3 -c 'import json, sys; print(json.dumps({"config": sys.stdin.read()}))' > "$config_file"
providers:
  home:
    address: owner@example.test
    imap: {address: imap.example.test:993, username: owner@example.test, password: test}
    smtp: {address: smtp.example.test:465, username: owner@example.test, password: test}
profiles:
  default:
    folders: {allow: ["ro:INBOX"]}
users:
  agent: {provider: home, profile: default, token_hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
listen: {mcp: "127.0.0.1:8080"}
EOF
docker cp "$config_file" "$name:/tmp/config.json"
docker exec "$name" sh -c 'curl -fsS -X PUT http://127.0.0.1:8098/api/config -H "Content-Type: application/json" --data-binary @/tmp/config.json | grep -Fq "Saved and restarted"'
for attempt in {1..10}; do
  if docker exec "$name" sh -c 'test -f /data/sirenorelay/.config/sirenorelay/config.yml && test "$(stat -c %a /data/sirenorelay/.config/sirenorelay/config.yml)" = 600 && test "$(stat -c %u /data/sirenorelay/.config/sirenorelay/config.yml)" = 10001'; then
    break
  fi
  sleep 1
done
docker exec "$name" sh -c 'test "$(stat -c %a /data/sirenorelay/.config/sirenorelay/config.yml)" = 600'

echo "SirenoRELAY Home Assistant add-on smoke test: OK"
