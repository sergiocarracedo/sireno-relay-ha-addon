# SirenoRELAY Home Assistant add-on

Run [SirenoRELAY](https://github.com/sergiocarracedo/sireno-relay) as a Home Assistant add-on. It keeps upstream email credentials inside the add-on and gives an agent a revocable bearer token for a policy-filtered MCP endpoint.

## Install

1. Open **Settings → Add-ons → Add-on Store** in Home Assistant.
2. Add `https://github.com/sergiocarracedo/sireno-relay-ha-addon` under **Repositories**.
3. Install **SirenoRELAY** and start it.
4. Select **Open Web UI**. On first run, the guided terminal appears embedded in the page.
5. Complete the interactive IMAP/SMTP setup. The page then switches automatically to a Monaco editor for `config.yml`.
6. Save future configuration edits directly from that editor.

The ingress editor is authoritative. It persists YAML at `/data/sirenorelay/.config/sirenorelay/config.yml`; onboarding secrets live beside it in `/data/sirenorelay/.config/sirenorelay/secrets/`. Home Assistant includes `/data` in app backups. Audit logs are intentionally not retained in that backed-up directory.

## Connect another Home Assistant add-on

SirenoRELAY itself stays on loopback. This add-on provides a token-protected internal bridge at port `8081` for other Home Assistant add-ons. Find the installed add-on’s hostname in **Settings → Add-ons → System → Network** and configure the client with:

```text
http://<addon-hostname>:8081/mcp
```

Give each agent its own bearer token. Do not mount this add-on’s data directory, secret files, or configuration into the agent’s container.

## Optional LAN access

LAN access is disabled by default. To enable it:

1. Put a certificate and private key in Home Assistant’s `ssl` directory.
2. Expand **LAN access** in the app’s Web UI and set the certificate/key file names.
3. Assign a host port to the add-on’s `8443/tcp` port in the Network settings.

The add-on refuses to start the LAN endpoint unless both TLS files exist. The endpoint is HTTPS only. Keep bearer tokens out of unencrypted connections.

## Terminal operations

The ingress terminal runs as the dedicated `sirenorelay` account. It is intended for onboarding, `config-check`, policy checks, and `sirenorelay user token rotate`.

## MCP bridge port

The App configuration includes `mcp_port` (default `8081`) for the authenticated bridge used by other Home Assistant Apps. Restart SirenoRELAY after changing it, then use the port shown in the Web UI header.

When Supervisor reports this App's internal hostname, SirenoRELAY automatically
uses `http://<app-hostname>:<mcp_port>` for one-minute attachment download links
returned by `read_attachment`. This endpoint remains internal to Home Assistant;
it does not enable LAN access. An explicit `attachments.base_url` in `config.yml`
takes precedence if an operator needs a different reachable origin.

After a token rotation, reload the app’s Web UI before editing so the Monaco editor reads the updated `config.yml`.

## Development

```sh
docker build \
  --build-arg BUILD_VERSION=2026.10.20-1 \
  --build-arg BUILD_ARCH=amd64 \
  -t sirenorelay-ha-addon:test sirenorelay
bash tests/smoke.sh
```
