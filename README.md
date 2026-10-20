# SirenoRELAY Home Assistant add-on

Run [SirenoRELAY](https://github.com/sergiocarracedo/sireno-relay) as a Home Assistant add-on. It keeps upstream email credentials inside the add-on and gives an agent a revocable bearer token for a policy-filtered MCP endpoint.

## Install

1. Open **Settings → Add-ons → Add-on Store** in Home Assistant.
2. Add `https://github.com/sergiocarracedo/sireno-relay-ha-addon` under **Repositories**.
3. Install **SirenoRELAY** and start it.
4. Select **Open Web UI**, then choose **Run first-time setup**.
5. Complete the interactive IMAP/SMTP setup. Its generated YAML is automatically copied into the add-on’s **Configuration** tab.
6. Use that tab’s `config_yaml` editor for all later configuration changes.

The Configuration tab is authoritative after this import. It persists the YAML at `/data/sirenorelay/.config/sirenorelay/config.yml`; onboarding secrets live beside it in `/data/sirenorelay/.config/sirenorelay/secrets/`. Home Assistant includes `/data` in add-on backups. Audit logs are intentionally not retained in that backed-up directory.

## Connect another Home Assistant add-on

SirenoRELAY itself stays on loopback. This add-on provides a token-protected internal bridge at port `8081` for other Home Assistant add-ons. Find the installed add-on’s hostname in **Settings → Add-ons → System → Network** and configure the client with:

```text
http://<addon-hostname>:8081/mcp
```

Give each agent its own bearer token. Do not mount this add-on’s data directory, secret files, or configuration into the agent’s container.

## Optional LAN access

LAN access is disabled by default. To enable it:

1. Put a certificate and private key in Home Assistant’s `ssl` directory.
2. Set **Enable LAN TLS** and the certificate/key file names in the Configuration tab.
3. Assign a host port to the add-on’s `8443/tcp` port in the Network settings.

The add-on refuses to start the LAN endpoint unless both TLS files exist. The endpoint is HTTPS only. Keep bearer tokens out of unencrypted connections.

## Terminal operations

The ingress terminal runs as the dedicated `sirenorelay` account. It is intended for onboarding, `config-check`, policy checks, and `sirenorelay user token rotate`.

After a token rotation, copy the updated `config.yml` into the Configuration tab before saving any tab changes. The add-on detects a stale tab value and refuses to overwrite a config changed outside the tab.

## Development

```sh
docker build \
  --build-arg BUILD_VERSION=2026.10.20-1 \
  --build-arg BUILD_ARCH=amd64 \
  -t sirenorelay-ha-addon:test sirenorelay
bash tests/smoke.sh
```
