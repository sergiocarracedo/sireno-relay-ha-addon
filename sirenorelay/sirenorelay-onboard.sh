#!/bin/bash
set -u

config=/data/sirenorelay/.config/sirenorelay/config.yml
if [[ -f "$config" ]]; then
  echo "SirenoRELAY is already configured. Edit config_yaml in the Home Assistant Configuration tab."
  exec bash -l
fi

sirenorelay onboard
status=$?
if [[ $status -eq 0 ]]; then
  python3 /usr/local/bin/config-sync.py --publish-current \
    || echo "Unable to copy config.yml into the Configuration tab. Copy it manually before changing Configuration-tab settings."
fi

echo
echo "Onboarding finished. This terminal will remain open until you close it."
exec bash -l
