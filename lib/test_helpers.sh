#!/usr/bin/env bash
# Minimal test helpers for nono pack smoke tests.
#
# Sourced by test_registry_packs.sh. Provides:
#   verify_nono_binary, setup_test_dir, cleanup_test_dir,
#   expect_success, expect_output_contains, require_working_sandbox,
#   print_summary

NONO_BIN="${NONO_BIN:-nono}"

_PASS=0
_FAIL=0
_FAILURES=()

_pass() { _PASS=$((_PASS + 1)); echo "  PASS  $1"; }
_fail() {
    _FAIL=$((_FAIL + 1))
    _FAILURES+=("$1")
    echo "  FAIL  $1"
    if [[ -n "${2:-}" ]]; then
        echo "        $2"
    fi
}

verify_nono_binary() {
    if [[ -z "${NONO_BIN:-}" ]]; then
        echo "NONO_BIN is not set" >&2
        exit 1
    fi
    if ! command -v "$NONO_BIN" >/dev/null 2>&1 && [[ ! -x "$NONO_BIN" ]]; then
        echo "nono binary not found: $NONO_BIN" >&2
        exit 1
    fi
}

setup_test_dir() {
    mktemp -d
}

cleanup_test_dir() {
    local dir="${1:-}"
    [[ -n "$dir" && -d "$dir" ]] && rm -rf "$dir"
}

expect_success() {
    local label="$1"; shift
    local output
    if output=$("$@" 2>&1); then
        _pass "$label"
    else
        _fail "$label" "exit $? — $(echo "$output" | head -3)"
    fi
}

expect_output_contains() {
    local label="$1"
    local pattern="$2"
    shift 2
    local output
    output=$("$@" 2>&1)
    if echo "$output" | grep -qF "$pattern"; then
        _pass "$label"
    else
        _fail "$label" "pattern '$pattern' not found in output"
    fi
}

require_working_sandbox() {
    local label="${1:-sandbox}"
    # Skip on platforms where sandbox is unavailable in CI
    if [[ "${NONO_SKIP_SANDBOX:-0}" == "1" ]]; then
        echo "  SKIP  $label (NONO_SKIP_SANDBOX=1)"
        return 1
    fi
    return 0
}

print_summary() {
    local total=$((_PASS + _FAIL))
    echo ""
    echo "Results: $total tests — $_PASS passed, $_FAIL failed"
    if (( _FAIL > 0 )); then
        echo "Failed:"
        for f in "${_FAILURES[@]}"; do
            echo "  - $f"
        done
        exit 1
    fi
}
