#!/usr/bin/env python3
"""Authenticated ingress UI API for SirenoRELAY configuration."""

import json
import os
import re
import subprocess
import tempfile
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

DATA = Path("/data/sirenorelay")
CONFIG = DATA / ".config/sirenorelay/config.yml"
SETTINGS = DATA / "ui-settings.json"
WEB_ROOT = Path("/usr/share/sirenorelay-web")
UID = GID = 10001
SAFE_FILENAME = re.compile(r"^[A-Za-z0-9._-]+$")


def read_settings():
    defaults = {"lan_tls_enabled": False, "tls_certificate": "fullchain.pem", "tls_key": "privkey.pem"}
    try:
        saved = json.loads(SETTINGS.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return defaults
    return {**defaults, **{key: saved[key] for key in defaults if key in saved}}


def atomic_write(path: Path, content: bytes, mode: int, owner: bool = False):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=f".{path.name}.", delete=False) as temporary:
        temporary.write(content)
        temporary.flush()
        os.fsync(temporary.fileno())
        candidate = Path(temporary.name)
    os.chmod(candidate, mode)
    if owner:
        os.chown(candidate, UID, GID)
        os.chown(path.parent, UID, GID)
    os.replace(candidate, path)


def validate_config(value: str):
    CONFIG.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chown(CONFIG.parent, UID, GID)
    with tempfile.NamedTemporaryFile(dir=CONFIG.parent, prefix=".check.", delete=False) as temporary:
        temporary.write(value.encode("utf-8"))
        candidate = Path(temporary.name)
    os.chmod(candidate, 0o600)
    os.chown(candidate, UID, GID)
    result = subprocess.run(
        ["runuser", "-u", "sirenorelay", "--", "sirenorelay", "config-check", "--config", str(candidate)],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode:
        candidate.unlink(missing_ok=True)
        raise ValueError((result.stderr or result.stdout).strip() or "Invalid config.yml")
    return candidate


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB_ROOT), **kwargs)

    def log_message(self, *_args):
        pass

    def send_json(self, status, body):
        encoded = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(encoded)

    def body(self):
        length = int(self.headers.get("Content-Length", "0"))
        return json.loads(self.rfile.read(length))

    def do_GET(self):
        if self.path == "/api/status":
            self.send_json(HTTPStatus.OK, {
                "configured": CONFIG.exists(),
                "config": CONFIG.read_text(encoding="utf-8") if CONFIG.exists() else "",
                "settings": read_settings(),
            })
            return
        super().do_GET()

    def do_PUT(self):
        if self.path != "/api/config":
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        try:
            value = self.body()["config"]
            if not isinstance(value, str) or not value.strip():
                raise ValueError("config.yml cannot be empty")
            candidate = validate_config(value)
            os.replace(candidate, CONFIG)
            self.send_json(HTTPStatus.OK, {"message": "Saved and restarted SirenoRELAY."})
            subprocess.run(["pkill", "-u", "sirenorelay", "-f", "^sirenorelay serve --config"], check=False)
        except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
            self.send_json(HTTPStatus.BAD_REQUEST, {"message": str(error)})

    def do_POST(self):
        if self.path != "/api/settings":
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        try:
            value = self.body()
            certificate, key = value["tls_certificate"], value["tls_key"]
            if not isinstance(value.get("lan_tls_enabled"), bool) or not all(isinstance(item, str) and SAFE_FILENAME.fullmatch(item) for item in (certificate, key)):
                raise ValueError("TLS file names may contain only letters, numbers, dots, underscores, and hyphens.")
            atomic_write(SETTINGS, json.dumps(value).encode("utf-8"), 0o600)
            self.send_json(HTTPStatus.OK, {"message": "Saved. Restart the app to apply LAN TLS changes."})
        except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
            self.send_json(HTTPStatus.BAD_REQUEST, {"message": str(error)})


ThreadingHTTPServer(("127.0.0.1", 8098), Handler).serve_forever()
