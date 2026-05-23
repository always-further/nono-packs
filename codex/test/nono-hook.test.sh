#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOOK="$ROOT_DIR/bin/nono-hook.sh"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

CAP_FILE="$TMP_DIR/caps.json"
STUB_DIR="$TMP_DIR/bin"
STUB_LOG="$TMP_DIR/nono.log"
DEFAULT_PERMISSION_MODE="default"
DENIED_STATUS="denied"
ALLOWED_STATUS="allowed"
BLOCKED_SECRET_PATH="/blocked/secret"
BLOCKED_OUT_PATH="/blocked/out"
mkdir -p "$STUB_DIR"
printf '{}\n' > "$CAP_FILE"

cat > "$STUB_DIR/nono" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NONO_STUB_LOG"
if [ "${NONO_STUB_MALFORMED:-0}" = "1" ]; then
    printf 'not json\n'
    exit 0
fi
printf '{"status":"%s"}\n' "${NONO_STUB_STATUS:-denied}"
STUB
chmod +x "$STUB_DIR/nono"

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

assert_empty() {
    local value=$1
    local name=$2
    [ -z "$value" ] || fail "$name: expected empty output, got: $value"
}

assert_contains() {
    local value=$1
    local needle=$2
    local name=$3
    case "$value" in
        *"$needle"*) ;;
        *) fail "$name: expected output to contain: $needle" ;;
    esac
}

assert_log_contains() {
    local needle=$1
    local name=$2
    grep -F -- "$needle" "$STUB_LOG" >/dev/null 2>&1 || fail "$name: expected nono log to contain: $needle"
}

assert_no_nono_call() {
    local name=$1
    [ ! -s "$STUB_LOG" ] || fail "$name: expected no nono call, got: $(cat "$STUB_LOG")"
}

reset_log() {
    : > "$STUB_LOG"
}

payload_string_response() {
    jq -n \
        --arg permission_mode "${1:-default}" \
        --arg tool_name "$2" \
        --argjson tool_input "$3" \
        --arg tool_response "$4" \
        '{
            cwd: "/work",
            hook_event_name: "PostToolUse",
            model: "test",
            permission_mode: $permission_mode,
            session_id: "session",
            tool_input: $tool_input,
            tool_name: $tool_name,
            tool_response: $tool_response,
            tool_use_id: "tool",
            transcript_path: null,
            turn_id: "turn"
        }'
}

payload_response_object() {
    jq -n \
        --arg permission_mode "${1:-default}" \
        --arg tool_name "$2" \
        --argjson tool_input "$3" \
        --argjson tool_response "$4" \
        '{
            cwd: "/work",
            hook_event_name: "PostToolUse",
            model: "test",
            permission_mode: $permission_mode,
            session_id: "session",
            tool_input: $tool_input,
            tool_name: $tool_name,
            tool_response: $tool_response,
            tool_use_id: "tool",
            transcript_path: null,
            turn_id: "turn"
        }'
}

run_hook() {
    local payload=$1
    local status=${2:-denied}
    NONO_CAP_FILE="$CAP_FILE" \
        NONO_STUB_LOG="$STUB_LOG" \
        NONO_STUB_STATUS="$status" \
        PATH="$STUB_DIR:$PATH" \
        bash "$HOOK" <<< "$payload"
}

reset_log
payload=$(payload_string_response "$DEFAULT_PERMISSION_MODE" Bash '{"command":"nl -ba /allowed/file.md"}' $'     1\tOperation not permitted\n     2\tplain document text')
output=$(run_hook "$payload" "$DENIED_STATUS")
assert_empty "$output" "document text denial words"
assert_no_nono_call "document text denial words"

reset_log
payload=$(payload_string_response "$DEFAULT_PERMISSION_MODE" Bash "{\"command\":\"cat $BLOCKED_SECRET_PATH\"}" "cat: $BLOCKED_SECRET_PATH: Operation not permitted")
output=$(run_hook "$payload" "$DENIED_STATUS")
assert_contains "$output" '"decision": "block"' "real denied output"
assert_contains "$output" "Path blocked: $BLOCKED_SECRET_PATH" "real denied path"
assert_log_contains "why --self --json --path $BLOCKED_SECRET_PATH --op read" "real denied nono validation"

reset_log
payload=$(payload_string_response "$DEFAULT_PERMISSION_MODE" Bash '{"command":"cat /allowed/secret"}' 'cat: /allowed/secret: Permission denied')
output=$(run_hook "$payload" "$ALLOWED_STATUS")
assert_empty "$output" "allowed nono result"
assert_log_contains 'why --self --json --path /allowed/secret --op read' "allowed nono validation"

reset_log
mcp_response='{"isError":false,"content":[{"type":"text","text":"Operation not permitted appears in this readable document."}]}'
payload=$(payload_response_object "$DEFAULT_PERMISSION_MODE" mcp_tool '{}' "$mcp_response")
output=$(run_hook "$payload" "$DENIED_STATUS")
assert_empty "$output" "successful MCP response"
assert_no_nono_call "successful MCP response"

reset_log
payload=$(payload_string_response "$DEFAULT_PERMISSION_MODE" apply_patch "{\"cmd\":\"touch $BLOCKED_OUT_PATH\"}" "touch: $BLOCKED_OUT_PATH: Permission denied")
output=$(run_hook "$payload" "$DENIED_STATUS")
context=$(printf '%s\n' "$output" | jq -r '.hookSpecificOutput.additionalContext')
assert_contains "$output" '"decision": "block"' "write denial output"
assert_contains "$context" "nono run --write $BLOCKED_OUT_PATH -- codex" "write denial one-off command"
assert_contains "$context" "\"filesystem\": { \"write\": [\"$BLOCKED_OUT_PATH\"] }" "write denial profile"
assert_log_contains "why --self --json --path $BLOCKED_OUT_PATH --op write" "write denial nono validation"

reset_log
payload=$(payload_string_response "$DEFAULT_PERMISSION_MODE" Read '{"path":"/blocked/fallback"}' 'error: Permission denied')
output=$(run_hook "$payload" "$DENIED_STATUS")
assert_contains "$output" 'Path blocked: /blocked/fallback' "fallback path"
assert_log_contains 'why --self --json --path /blocked/fallback --op read' "fallback path nono validation"

reset_log
payload=$(payload_string_response bypassPermissions Bash "{\"command\":\"cat $BLOCKED_SECRET_PATH\"}" "cat: $BLOCKED_SECRET_PATH: Operation not permitted")
output=$(run_hook "$payload" "$DENIED_STATUS")
assert_empty "$output" "bypassPermissions"
assert_no_nono_call "bypassPermissions"

reset_log
payload=$(payload_string_response "$DEFAULT_PERMISSION_MODE" Bash "{\"command\":\"cat $BLOCKED_SECRET_PATH\"}" "cat: $BLOCKED_SECRET_PATH: Operation not permitted")
output=$(env -u NONO_CAP_FILE NONO_STUB_LOG="$STUB_LOG" NONO_STUB_STATUS="$DENIED_STATUS" PATH="$STUB_DIR:$PATH" bash "$HOOK" <<< "$payload")
assert_empty "$output" "missing NONO_CAP_FILE"
assert_no_nono_call "missing NONO_CAP_FILE"

reset_log
payload=$(payload_string_response "$DEFAULT_PERMISSION_MODE" Bash "{\"command\":\"cat $BLOCKED_SECRET_PATH\"}" "cat: $BLOCKED_SECRET_PATH: Operation not permitted")
output=$(NONO_CAP_FILE="$CAP_FILE" NONO_STUB_LOG="$STUB_LOG" NONO_STUB_MALFORMED=1 PATH="$STUB_DIR:$PATH" bash "$HOOK" <<< "$payload")
assert_empty "$output" "malformed nono why"
assert_log_contains "why --self --json --path $BLOCKED_SECRET_PATH --op read" "malformed nono validation"

printf 'ok - codex nono hook tests\n'
