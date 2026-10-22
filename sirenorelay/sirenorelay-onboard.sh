#!/bin/bash
set -u

config=/data/sirenorelay/.config/sirenorelay/config.yml
if [[ -f "$config" ]]; then
  echo "SirenoRELAY is already configured. Edit config_yaml in the Home Assistant Configuration tab."
  exec bash -l
fi

runuser -u sirenorelay -- env HOME=/data/sirenorelay XDG_CONFIG_HOME=/data/sirenorelay/.config sirenorelay onboard
status=$?
if [[ $status -eq 0 ]]; then
  echo "Configuration created. Return to the SirenoRELAY page to edit it in the YAML editor."
fi

echo
echo "Onboarding finished. This terminal will remain open until you close it."
exec bash -l
