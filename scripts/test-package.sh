#!/usr/bin/env bash
# Dispatch the generic test-package workflow for a nono pack.
#
# Usage:
#   scripts/test-package.sh [--dry-run]

set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage: scripts/test-package.sh [--dry-run]

Prompts for package details, then dispatches .github/workflows/test-package.yml
with GitHub CLI.

Options:
  --dry-run   Print the gh command; do not dispatch the workflow.
USAGE
  exit 2
}

DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage ;;
    *) echo "unknown flag: $1" >&2; usage ;;
  esac
  shift
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$REPO_ROOT" ]] || { echo "not inside a git repo" >&2; exit 1; }
cd "$REPO_ROOT"

WORKFLOW=".github/workflows/test-package.yml"
[[ -f "$WORKFLOW" ]] || { echo "missing $WORKFLOW" >&2; exit 1; }

prompt() {
  local label="$1"
  local default="${2:-}"
  local value

  if [[ -n "$default" ]]; then
    read -r -p "$label [$default]: " value
    printf '%s\n' "${value:-$default}"
  else
    read -r -p "$label: " value
    printf '%s\n' "$value"
  fi
}

PACKAGE_NAME="$(prompt "Package name")"
[[ -n "$PACKAGE_NAME" ]] || { echo "package name is required" >&2; exit 1; }

PACKAGE_PATH="$(prompt "Package path" "$PACKAGE_NAME")"
[[ -n "$PACKAGE_PATH" ]] || { echo "package path is required" >&2; exit 1; }
[[ -d "$PACKAGE_PATH" ]] || { echo "package directory not found: $PACKAGE_PATH" >&2; exit 1; }
[[ -f "$PACKAGE_PATH/package.json" ]] || { echo "missing $PACKAGE_PATH/package.json" >&2; exit 1; }

PACKAGE_JSON_VERSION="$(jq -r '.version // empty' "$PACKAGE_PATH/package.json")"
DEFAULT_TEST_VERSION="test-$PACKAGE_NAME"
if [[ -n "$PACKAGE_JSON_VERSION" ]]; then
  DEFAULT_TEST_VERSION="$DEFAULT_TEST_VERSION-v$PACKAGE_JSON_VERSION"
fi

PACKAGE_VERSION="$(prompt "Package version" "$DEFAULT_TEST_VERSION")"
[[ -n "$PACKAGE_VERSION" ]] || { echo "package version is required" >&2; exit 1; }

PACKAGE_NAMESPACE="$(prompt "Package namespace" "nolabs-ai")"
[[ -n "$PACKAGE_NAMESPACE" ]] || { echo "package namespace is required" >&2; exit 1; }

REGISTRY_URL="$(prompt "Registry URL" "https://lukehinds.rat.alwaysfurther.us/api/v1")"
[[ -n "$REGISTRY_URL" ]] || { echo "registry URL is required" >&2; exit 1; }

COMMAND=(
  gh workflow run test-package.yml
  -f "package_name=$PACKAGE_NAME"
  -f "package_path=$PACKAGE_PATH"
  -f "package_version=$PACKAGE_VERSION"
  -f "package_namespace=$PACKAGE_NAMESPACE"
  -f "registry_url=$REGISTRY_URL"
)

cat <<EOF

About to dispatch:
  workflow   $WORKFLOW
  package    $PACKAGE_NAME
  path       $PACKAGE_PATH
  version    $PACKAGE_VERSION
  namespace  $PACKAGE_NAMESPACE
  registry   $REGISTRY_URL
  dry-run    $([[ $DRY_RUN -eq 1 ]] && echo "yes" || echo "no")

Command:
  ${COMMAND[*]}

EOF

if (( DRY_RUN )); then
  exit 0
fi

command -v gh >/dev/null || { echo "gh not found — install GitHub CLI first" >&2; exit 1; }

read -r -p "Proceed? [y/N] " ANSWER
case "$ANSWER" in
  y|Y|yes|YES) ;;
  *) echo "aborted" >&2; exit 1 ;;
esac

"${COMMAND[@]}"

cat <<EOF

Workflow dispatched. Watch it with:
  gh run watch --workflow test-package.yml
EOF
