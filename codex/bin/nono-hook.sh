#!/usr/bin/env bash
# nono-hook.sh - Codex PostToolUse hook for nono sandbox diagnostics
# Version: 1.6.0
#
# Behavioural change in 1.6.0: denial detection no longer scans the
# entire successful tool response for broad text such as "Operation not
# permitted". It first finds a denial-shaped line, prefers a path from
# that line, then validates the candidate with `nono why --self --json`.
#
# Behavioural change in 1.5.0: Option B now writes the proposed
# profile to ~/.config/nono/profile-drafts/ (the only writable
# nono-config surface from inside the sandbox) and instructs the
# user to run `nono profile promote <name>` to review and apply.
# Previously the model was told to write directly into
# ~/.config/nono/profiles/, which is now read-only from inside the
# sandbox.
#
# Behavioural change in 1.4.0: path extraction now also looks at
# tool_input and accepts tilde-prefixed paths (`~/test.txt`), not
# just absolute `/...` forms. Earlier versions silently fell back
# to a `<blocked-path>` literal when the denial only mentioned the
# tilde form, which then surfaced in user-facing output.
#
# Behavioural change in 1.3.0: the additionalContext no longer contains
# any <placeholder> tokens. The hook derives a default profile name
# from the blocked path basename (e.g. /home/u/test.txt → codex-test-txt)
# and substitutes it into the JSON template before emitting. This is a
# response to v1.2.0 behaviour where Codex's model echoed `<chosen-name>`
# back to the user verbatim despite explicit instructions to substitute
# a real name — placeholders are clearly mishandled by the model in
# this position. The hook still asks the model to write the file via
# its file-write tool, but if it falls back to printing the template,
# the printout is now directly usable.
#
# 1.2.0 introduced the "act, don't parrot" framing (kept in 1.3.0).
#
# Splits user-visible from agent-visible content so the conversation
# stays readable:
#   `reason`            = ONE-LINE user-visible block reason.
#   `additionalContext` = full diagnostic + Option A/B template, only
#                         visible to the agent on follow-up turns.
#
# Earlier versions emitted the same wall-of-text in both fields and
# duplicated the allow-list dump that SessionStart already provides.
#
# Schema reference:
#   https://github.com/openai/codex/blob/main/codex-rs/hooks/schema/generated/post-tool-use.command.output.schema.json

if [ -z "$NONO_CAP_FILE" ] || [ ! -f "$NONO_CAP_FILE" ]; then
    exit 0
fi
if ! command -v jq &> /dev/null; then
    exit 0
fi

INPUT=$(cat)

# Silent in bypassPermissions mode — user has explicitly opted out
# of sandbox-aware nudges.
PMODE=$(echo "$INPUT" | jq -r '.permission_mode // "default"' 2>/dev/null)
[ "$PMODE" = "bypassPermissions" ] && exit 0

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)

# MCP-style successful responses may contain arbitrary document text.
# If Codex tells us the response is not an error, do not mine it for
# denial phrases.
IS_ERROR=$(echo "$INPUT" | jq -r 'if (.tool_response | type) == "object" and (.tool_response | has("isError")) then .tool_response.isError else empty end' 2>/dev/null)
[ "$IS_ERROR" = "false" ] && exit 0

TOOL_RESPONSE=$(echo "$INPUT" | jq -r '
  .tool_response
  | if type == "string" then .
    elif type == "object" or type == "array" then [.. | strings] | join("\n")
    else tostring
    end
' 2>/dev/null)
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input | tostring' 2>/dev/null)

DENIAL_REGEX='operation not permitted|permission denied|EPERM|EACCES|landlock|sandbox.*denied'
PATH_REGEX='(~/|/)[^[:space:]"'"'"',;]+'
OP_READ="read"
OP_WRITE="write"
OP_READWRITE="readwrite"
STATUS_DENIED="denied"

DENIAL_LINE=$(echo "$TOOL_RESPONSE" | grep -iE "$DENIAL_REGEX" | grep -E "$PATH_REGEX" | head -n 1)
if [ -z "$DENIAL_LINE" ]; then
    DENIAL_LINE=$(echo "$TOOL_RESPONSE" | grep -iE '(^|[^[:alnum:]_])(error|failed|failure|denied|cannot|can'\''t|unable|fatal|exception|traceback|panic|hook|tool|bash|apply_patch|read|write|open|create|remove|delete|rename|move|copy|chmod|chown|mkdir|rmdir|touch|tee|cat|sed|awk|rg|grep|ls|nl|cp|mv|rm)([^[:alnum:]_]|$)' | grep -iE "$DENIAL_REGEX" | head -n 1)
fi
[ -z "$DENIAL_LINE" ] && exit 0

FAILED_PATH=$(echo "$DENIAL_LINE" | grep -oE "$PATH_REGEX" | head -n 1)
if [ -z "$FAILED_PATH" ]; then
    FAILED_PATH=$(echo "$TOOL_INPUT" | grep -oE "$PATH_REGEX" | head -n 1)
fi
[ -z "$FAILED_PATH" ] && exit 0
FAILED_PATH=${FAILED_PATH%:}

case "$FAILED_PATH" in
    \~/*) FAILED_PATH="${HOME}/${FAILED_PATH#\~/}" ;;
    \~)   FAILED_PATH="$HOME" ;;
esac

OP="$OP_READ"
WRITE_REGEX='(^|[^[:alnum:]_])(apply_patch|write|edit|create|created|creating|delete|deleted|deleting|remove|removed|removing|rename|renamed|move|moved|copy|copied|chmod|chown|mkdir|rmdir|touch|tee|install|append|truncate|unlink)([^[:alnum:]_]|$)|(^|[[:space:]])(>|>>)([[:space:]]|$)'
READWRITE_REGEX='(^|[^[:alnum:]_])(readwrite|allow)([^[:alnum:]_]|$)'
OP_HAYSTACK="$TOOL_NAME
$DENIAL_LINE
$TOOL_INPUT"
if echo "$OP_HAYSTACK" | grep -qiE "$READWRITE_REGEX"; then
    OP="$OP_READWRITE"
elif echo "$OP_HAYSTACK" | grep -qiE "$WRITE_REGEX"; then
    OP="$OP_WRITE"
fi

WHY_JSON=$(nono why --self --json --path "$FAILED_PATH" --op "$OP" 2>/dev/null)
WHY_STATUS=$(echo "$WHY_JSON" | jq -r '.status // empty' 2>/dev/null)
if [ "$WHY_STATUS" != "$STATUS_DENIED" ]; then
    exit 0
fi

DISPLAY_PATH="$FAILED_PATH"

# Pack identity. Hardcoded — the pack ships with `install_as: codex`,
# so suggesting `extends: "codex"` is correct for any user who
# started from the pack profile directly. The template includes a
# comment for users on a custom intermediate to update by hand.
PACK_PROFILE="codex"

# Derive a default profile name from the blocked path so the
# additionalContext never contains a `<placeholder>` token — earlier
# versions used `<chosen-name>` and Codex's model parroted it back to
# the user verbatim. Pre-substituting a real name means the worst
# case (model just echoes our template) still produces something the
# user can copy-paste. Algorithm: lowercase, basename, kebab-case,
# strip any chars outside [a-z0-9-]. Fallback to `${PACK_PROFILE}-extended`.
PATH_BASENAME=$(basename "$DISPLAY_PATH" 2>/dev/null \
  | tr '[:upper:]' '[:lower:]' \
  | tr -c 'a-z0-9-' '-' \
  | sed -E 's/-+/-/g; s/^-//; s/-$//')
if [ -z "$PATH_BASENAME" ] || [ "$PATH_BASENAME" = "-" ]; then
    DEFAULT_PROFILE_NAME="${PACK_PROFILE}-extended"
else
    DEFAULT_PROFILE_NAME="${PACK_PROFILE}-${PATH_BASENAME}"
fi

REASON="[nono sandbox] $DISPLAY_PATH was blocked by the OS sandbox — not Codex, not TCC, not Unix permissions. See additional context for diagnosis and the two options."

case "$OP" in
    "$OP_READWRITE")
        FLAG="--allow"
        PROFILE_ACCESS_FIELD="allow"
        NOTE_OP="$OP_READWRITE"
        ;;
    "$OP_WRITE")
        FLAG="--write"
        PROFILE_ACCESS_FIELD="$OP_WRITE"
        NOTE_OP="$OP_WRITE"
        ;;
    *)
        FLAG="--read"
        PROFILE_ACCESS_FIELD="$OP_READ"
        NOTE_OP="$OP_READ"
        ;;
esac

CONTEXT="Sandbox denial. Path blocked: $DISPLAY_PATH
Profile name to use for the persistent fix below: $DEFAULT_PROFILE_NAME

Offer the user TWO choices (A or B). Wait for their answer.

  A) one-off — exit and restart with this path allowed:
       nono run $FLAG $DISPLAY_PATH -- codex

  B) persistent — create a profile file using the name above
     ($DEFAULT_PROFILE_NAME).

If user picks A: print that command. Stop.

If user picks B and ~/.config/nono/profile-drafts does not exist or
cannot be written, or \`nono profile promote --help\` is unavailable:
do not try to modify ~/.config/nono/profiles directly. Tell the user
to upgrade nono, then rerun the draft flow. Stop.

If user picks B and ~/.config/nono/profiles/${DEFAULT_PROFILE_NAME}.json already exists:
read that profile, compute the SHA-256 of the exact bytes you read,
merge the new path into the smallest appropriate filesystem field,
write the full proposed profile to
~/.config/nono/profile-drafts/${DEFAULT_PROFILE_NAME}.json, and write
the hash to ~/.config/nono/profile-drafts/${DEFAULT_PROFILE_NAME}.base.

If user picks B and that user profile does not exist: write the file
using your file-write tool to
~/.config/nono/profile-drafts/${DEFAULT_PROFILE_NAME}.json with
EXACTLY these contents (the profile name is already filled in — do
NOT substitute placeholders, just write what is below):
{
  \"extends\": \"$PACK_PROFILE\",
  \"meta\": { \"name\": \"$DEFAULT_PROFILE_NAME\", \"version\": \"1.0.0\" },
  \"filesystem\": { \"$PROFILE_ACCESS_FIELD\": [\"$DISPLAY_PATH\"] }
}

The profiles/ directory is read-only from inside the sandbox by
design; drafts/ is the writable surface and the user promotes
out-of-band.

After writing, tell the user:
  Drafted $DEFAULT_PROFILE_NAME. Run \`nono profile promote $DEFAULT_PROFILE_NAME\`
  to review and apply, then restart codex with:
    nono run --profile $DEFAULT_PROFILE_NAME -- codex

Stop after either option. Do not retry the blocked tool call — the
user has to promote and restart for the new profile to take effect.

Notes:
  - Use 'read' for view-only; 'write' for modify-only; 'allow' for r+w.
    This failure was inferred as '$NOTE_OP'.
  - For the precise rule that blocked the path: nono why --self --path $DISPLAY_PATH --op $OP"

jq -n --arg reason "$REASON" --arg ctx "$CONTEXT" '{
  "decision": "block",
  "reason": $reason,
  "systemMessage": "nono sandbox denial",
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $ctx
  }
}'
