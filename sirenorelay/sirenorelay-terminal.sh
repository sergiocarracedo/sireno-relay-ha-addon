#!/bin/bash
set -euo pipefail

exec runuser -u sirenorelay -- env \
  HOME=/data/sirenorelay \
  XDG_CONFIG_HOME=/data/sirenorelay/.config \
  bash -l
