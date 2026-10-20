#!/usr/bin/env bash
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
dockerfile="$root/sirenorelay/Dockerfile"
config="$root/sirenorelay/config.yaml"
changelog="$root/CHANGELOG.md"
release_json="$(mktemp)"
trap 'rm -f "$release_json"' EXIT

curl -fsSL -H 'Accept: application/vnd.github+json' \
  https://api.github.com/repos/sergiocarracedo/sireno-relay/releases/latest -o "$release_json"

tag="$(jq -r '.tag_name // empty' "$release_json")"
published_at="$(jq -r '.published_at // empty' "$release_json")"
if [[ ! "$tag" =~ ^v[0-9]+(\.[0-9]+){2}$ || -z "$published_at" ]]; then
  echo "Expected a published stable SirenoRELAY tag, got $tag" >&2
  exit 1
fi

current="$(sed -n -E 's/^ARG SIRENORELAY_VERSION=([^[:space:]]+)$/\1/p' "$dockerfile")"
if [[ "$current" == "${tag#v}" ]]; then
  echo "SirenoRELAY is already pinned to $tag."
  exit 0
fi

release_date="$(date -u -d "$published_at" +'%Y.%-m.%-d')"
addon_version="${release_date}-1"
sed -i -E "s/^ARG SIRENORELAY_VERSION=.*/ARG SIRENORELAY_VERSION=${tag#v}/" "$dockerfile"
sed -i -E "s/^version: .*/version: \"${addon_version}\"/" "$config"

temporary="$(mktemp)"
{
  printf '# Changelog\n\n## %s\n\n- Update SirenoRELAY to [%s](https://github.com/sergiocarracedo/sireno-relay/releases/tag/%s).\n\n' "$addon_version" "$tag" "$tag"
  test -f "$changelog" && sed '1,3d' "$changelog" || true
} > "$temporary"
mv "$temporary" "$changelog"
