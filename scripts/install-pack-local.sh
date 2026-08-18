#!/usr/bin/env bash
# Install a local pack directory directly into the nono package store.
#
# Bypasses the registry entirely — copies files into the store layout that
# `nono pull` would produce, then writes a lockfile entry so nono treats the
# pack as installed.
#
# Usage:
#   scripts/install-pack-local.sh <pack-dir> [namespace]
#
#   pack-dir   Directory containing package.json (e.g. claude, opencode)
#   namespace  Registry namespace (default: always-further)
#
# The pack is then addressable as <namespace>/<pack-name> in nono commands.

set -euo pipefail

PACK_DIR="${1:-}"
NAMESPACE="${2:-always-further}"

if [[ -z "$PACK_DIR" || ! -f "$PACK_DIR/package.json" ]]; then
    echo "Usage: $0 <pack-dir> [namespace]" >&2
    echo "  pack-dir must contain a package.json" >&2
    exit 1
fi

PACK_DIR="$(cd "$PACK_DIR" && pwd)"
PACK_NAME=$(jq -r '.name' "$PACK_DIR/package.json")
VERSION=$(jq -r '.version' "$PACK_DIR/package.json")

# Locate the nono config dir
NONO_CONFIG="${NONO_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/nono}"
PACKAGES_DIR="$NONO_CONFIG/packages"
DEST="$PACKAGES_DIR/$NAMESPACE/$PACK_NAME"
LOCKFILE="$PACKAGES_DIR/lockfile.json"

echo "Installing $NAMESPACE/$PACK_NAME@$VERSION → $DEST"

mkdir -p "$DEST"

# Copy package.json
cp "$PACK_DIR/package.json" "$DEST/package.json"

# Copy each artifact to its correct location in the store.
# Profiles are installed as profiles/<install_as>.json.
# Plugins keep their source path relative to the pack dir.
sha256_for() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# Build the artifacts JSON blob for the lockfile as we copy files
ARTIFACTS_JSON="{"
FIRST=1

while IFS= read -r artifact; do
    type=$(echo "$artifact" | jq -r '.type')
    path=$(echo "$artifact" | jq -r '.path')
    src="$PACK_DIR/$path"

    if [[ ! -f "$src" ]]; then
        echo "  WARNING: artifact not found, skipping: $path" >&2
        continue
    fi

    sha=$(sha256_for "$src")

    if [[ "$type" == "profile" ]]; then
        install_as=$(echo "$artifact" | jq -r '.install_as // (.path | gsub(".json$"; ""))')
        dest_path="profiles/$install_as.json"
    else
        dest_path="$path"
    fi

    mkdir -p "$DEST/$(dirname "$dest_path")"
    cp "$src" "$DEST/$dest_path"
    echo "  copied $type: $path → $dest_path"

    [[ $FIRST -eq 0 ]] && ARTIFACTS_JSON+=","
    ARTIFACTS_JSON+=$(printf '"%s":{"sha256":"%s","type":"%s"}' "$dest_path" "$sha" "$type")
    FIRST=0

done < <(jq -c '.artifacts[]' "$PACK_DIR/package.json")

ARTIFACTS_JSON+="}"

# Update (or create) the lockfile
NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000000+00:00" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

if [[ ! -f "$LOCKFILE" ]]; then
    echo '{"lockfile_version":4,"registry":"https://registry.nono.sh","packages":{}}' > "$LOCKFILE"
fi

# Merge this pack entry into the lockfile using jq
ENTRY=$(jq -n \
    --arg version "$VERSION" \
    --arg installed_at "$NOW" \
    --argjson artifacts "$ARTIFACTS_JSON" \
    '{
        version: $version,
        installed_at: $installed_at,
        pinned: false,
        artifacts: $artifacts,
        wiring_record: []
    }')

PACK_KEY="$NAMESPACE/$PACK_NAME"
tmp=$(mktemp)
jq --arg key "$PACK_KEY" --argjson entry "$ENTRY" \
    '.packages[$key] = $entry' "$LOCKFILE" > "$tmp"
mv "$tmp" "$LOCKFILE"

echo "Done. Pack registered as '$PACK_KEY' in $LOCKFILE"
