#!/usr/bin/env python3
"""Safely materialize the Configuration-tab YAML into the relay data volume."""

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

DATA = Path("/data/sirenorelay")
CONFIG = DATA / ".config/sirenorelay/config.yml"
LAST_TAB_HASH = DATA / ".configuration-tab.sha256"
OPTIONS = Path("/data/options.json")
RELAY_UID = 10001
RELAY_GID = 10001


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def read_options() -> str:
    try:
        value = json.loads(OPTIONS.read_text(encoding="utf-8")).get("config_yaml", "")
    except (OSError, json.JSONDecodeError) as error:
        print(f"Unable to read add-on options: {error}", file=sys.stderr)
        return ""
    return value if isinstance(value, str) else ""


def validate(candidate: Path) -> bool:
    result = subprocess.run(
        ["runuser", "-u", "sirenorelay", "--", "sirenorelay", "config-check", "--config", str(candidate)],
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        print(result.stderr or result.stdout, file=sys.stderr, end="")
        return False
    return True


def write_config(yaml_text: str) -> None:
    DATA.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chown(DATA, RELAY_UID, RELAY_GID)
    CONFIG.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chown(CONFIG.parent, RELAY_UID, RELAY_GID)
    content = yaml_text.encode("utf-8")
    with tempfile.NamedTemporaryFile(prefix=".config.", dir=CONFIG.parent, delete=False) as temporary:
        temporary.write(content)
        temporary.flush()
        os.fsync(temporary.fileno())
        candidate = Path(temporary.name)
    os.chmod(candidate, 0o600)
    os.chown(candidate, RELAY_UID, RELAY_GID)
    if not validate(candidate):
        candidate.unlink(missing_ok=True)
        return
    os.replace(candidate, CONFIG)
    LAST_TAB_HASH.write_text(digest(content), encoding="utf-8")
    os.chmod(LAST_TAB_HASH, 0o600)
    os.chown(LAST_TAB_HASH, RELAY_UID, RELAY_GID)
    print("Applied Configuration-tab YAML.")


def publish_current_config() -> None:
    """Copy onboarding's generated YAML into the native Configuration tab."""
    if not CONFIG.exists():
        raise SystemExit("Onboarding did not create config.yml.")
    token = os.environ.get("SUPERVISOR_TOKEN")
    if not token:
        raise SystemExit("SUPERVISOR_TOKEN is unavailable; cannot update Configuration-tab YAML.")
    options = json.loads(OPTIONS.read_text(encoding="utf-8"))
    options["config_yaml"] = CONFIG.read_text(encoding="utf-8")
    result = subprocess.run(
        [
            "curl", "--fail-with-body", "--silent", "--show-error",
            "-X", "POST", "http://supervisor/addons/self/options",
            "-H", f"Authorization: Bearer {token}",
            "-H", "Content-Type: application/json",
            "--data-binary", json.dumps({"options": options}),
        ],
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        raise SystemExit(result.stderr or result.stdout)
    LAST_TAB_HASH.write_text(digest(CONFIG.read_bytes()), encoding="utf-8")
    os.chmod(LAST_TAB_HASH, 0o600)
    os.chown(LAST_TAB_HASH, RELAY_UID, RELAY_GID)
    print("Copied generated config.yml into the Configuration tab.")


def sync(previous: str | None) -> str:
    yaml_text = read_options()
    if not yaml_text.strip() or yaml_text == previous:
        return yaml_text

    desired_hash = digest(yaml_text.encode("utf-8"))
    recorded_hash = LAST_TAB_HASH.read_text(encoding="utf-8").strip() if LAST_TAB_HASH.exists() else ""
    current_hash = digest(CONFIG.read_bytes()) if CONFIG.exists() else ""
    if recorded_hash and current_hash != recorded_hash and desired_hash == recorded_hash:
        print("Configuration file changed outside the Configuration tab; refusing to overwrite it. Import the current YAML into the tab before saving.", file=sys.stderr)
        return yaml_text

    write_config(yaml_text)
    return yaml_text


def main() -> None:
    if len(sys.argv) == 2 and sys.argv[1] == "--publish-current":
        publish_current_config()
        return
    if len(sys.argv) != 1:
        raise SystemExit("Usage: config-sync.py [--publish-current]")
    DATA.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chown(DATA, RELAY_UID, RELAY_GID)
    previous: str | None = None
    while True:
        previous = sync(previous)
        time.sleep(1)


if __name__ == "__main__":
    main()
