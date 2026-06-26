#!/usr/bin/env bash
# Smoke test a single nono pack.
#
# The pack must already be present in the nono package store — use
# scripts/install-pack-local.sh to inject it before running this.
#
# Usage:
#   NONO_BIN=./nono scripts/smoke-test-pack.sh <namespace/pack>
#
# Optional env:
#   NONO_BIN          Path to nono binary (default: nono)
#   NONO_SKIP_SANDBOX Set to 1 to skip sandboxed execution tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"

PACK="${1:-}"
if [[ -z "$PACK" ]]; then
    echo "Usage: $0 <namespace/pack>" >&2
    exit 1
fi

echo "Smoke test: $PACK"

verify_nono_binary

TMPDIR=$(setup_test_dir)
trap 'cleanup_test_dir "$TMPDIR"' EXIT

export NONO_NO_UPDATE_CHECK=1
export NONO_NO_MIGRATE=1
export NONO_NO_SAVE_PROMPT=1

echo "list"

name="${PACK#*/}"
expect_output_contains "nono list shows $PACK" "$name" \
    "$NONO_BIN" list --installed

echo "profile resolution"

expect_success "profile validate $PACK" \
    "$NONO_BIN" profile validate "$PACK"

expect_success "profile show $PACK" \
    "$NONO_BIN" profile show "$PACK"

expect_output_contains "profile show $PACK lists filesystem" "Filesystem:" \
    "$NONO_BIN" profile show "$PACK"

expect_success "profile diff $PACK default" \
    "$NONO_BIN" profile diff "$PACK" default

echo "dry-run execution"

mkdir -p "$TMPDIR/workdir"

expect_success "dry-run under $PACK succeeds" \
    "$NONO_BIN" run --profile "$PACK" --workdir "$TMPDIR/workdir" --dry-run -- echo "smoke"

expect_output_contains "dry-run under $PACK shows Capabilities" "Capabilities:" \
    "$NONO_BIN" run --profile "$PACK" --workdir "$TMPDIR/workdir" --dry-run -- echo "smoke"

echo "sandboxed execution"

if require_working_sandbox "sandboxed execution"; then
    NONO_BIN_ABS="$(cd "$(dirname "$NONO_BIN")" && pwd)/$(basename "$NONO_BIN")"
    expect_success "sandboxed echo under $PACK exits 0" \
        bash -lc "cd \"$TMPDIR/workdir\" && \"$NONO_BIN_ABS\" run --profile \"$PACK\" --allow-cwd --no-audit -- echo smoke"
fi

print_summary
