# copilot-cli Pack — Implementation Notes

This document records what was verified from source, what was inferred by analogy with the `claude` and `codex` packs, and what still needs hands-on verification before a production release.

---

## What Was Verified

### Copilot CLI hook event names
Verified from `https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-hooks-reference`:
- `PostToolUseFailure` — fires after a tool call fails
- `PostToolUse` — fires after every successful tool call
- `SessionStart` — fires when the session begins
- Both camelCase and PascalCase event names are accepted; PascalCase used here for consistency with `claude` / `codex`.

### Copilot CLI hook input schemas (VS Code compat format)
- `PostToolUseFailure`: `{ hook_event_name, session_id, tool_name, tool_input, error }`
- `PostToolUse`: `{ hook_event_name, session_id, tool_name, tool_input, tool_result: { result_type, text_result_for_llm } }`
- `SessionStart`: `{ hook_event_name, session_id, timestamp, cwd, source }`

### Copilot CLI tool names
Verified from hooks reference. Tools that can cause sandbox denials:
- `bash` — shell commands
- `view` — read a file (Claude Code equivalent: `Read`)
- `edit` — edit a file (Claude Code equivalent: `Edit`)
- `create` — create a file (Claude Code equivalent: `Write`)

### Installed plugins path
Verified from `https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference`:
- `~/.copilot/installed-plugins/MARKETPLACE/PLUGIN-NAME/`
- Wiring symlinks the pack dir to `~/.copilot/installed-plugins/nolabs-ai/nono/`.

### Plugin manifest discovery
Verified: Copilot CLI checks for plugin manifests at `plugin.json` (root level) among other paths. The existing `copilot-cli/plugin.json` at pack root is correctly positioned — Copilot finds it when scanning the installed plugin directory.

### hooks.json format
Verified: `{ "version": 1, "hooks": { "EventName": [ { "type": "command", "bash": "..." } ] } }`.

### nono pack format
Verified from `nono/crates/nono-cli/src/package.rs` and `nono/crates/nono-cli/src/wiring.rs`:
- Valid artifact types: `profile`, `instruction`, `trust_policy`, `groups`, `plugin`
- Valid wiring directive types: `symlink`, `write_file`, `json_merge`, `json_array_append`, `toml_block`
- Wiring variables available: `$PACK_DIR`, `$NS`, `$PLUGIN`, `$HOME`, `$XDG_CONFIG_HOME`, `$NOW`
- `min_nono_version: "0.44.0"` matches `claude` and `codex` packs (wiring system stable from this version)

---

## What Needs Verification

### 1. `COPILOT_PLUGIN_ROOT` environment variable
**Gap**: The Copilot CLI hooks reference does not document which (if any) environment variables Copilot sets when executing hook commands. Claude Code sets `${CLAUDE_PLUGIN_ROOT}` for its hook scripts; Copilot may do the same or use a different name.

**Current approach**: `hooks/hooks.json` uses `${COPILOT_PLUGIN_ROOT:-$HOME/.copilot/installed-plugins/nolabs-ai/nono}` — uses `COPILOT_PLUGIN_ROOT` if set, falls back to the hardcoded installed-plugins path.

**To verify**: Run a test hook with `env | grep -i plugin` and inspect the output, or check the Copilot CLI source for env var injection.

### 2. Hook output format for context injection
**Gap**: The Copilot CLI hooks reference does not document a `PostToolUse` or `PostToolUseFailure` output schema for injecting context into the conversation. The `notification` event documents `{ "additionalContext": "..." }`, and `claude` / `codex` hooks use `{ "hookSpecificOutput": { "hookEventName": "...", "additionalContext": "..." } }`.

**Current approach**: All hook scripts output the `hookSpecificOutput.additionalContext` format (matching `claude` and `codex`), on the assumption that Copilot uses the same plugin infrastructure and therefore the same hook output contract.

**To verify**: Run the hooks manually during a session and confirm that `additionalContext` is injected as a prepended message. If not, try `{ "additionalContext": "..." }` at the top level (as documented for the `notification` event).

### 3. Wiring — is a symlink to `installed-plugins/` sufficient?
**Gap**: The Copilot CLI configuration directory reference returned a 404 during authoring. It is unclear whether placing a symlink at `~/.copilot/installed-plugins/nolabs-ai/nono/` is enough for Copilot to discover and load the plugin, or whether additional registration (e.g. via `copilot plugin marketplace add`) is also required.

**Current approach**: `package.json` wiring creates only the symlink. The `wiring/marketplace.json` is shipped as a plugin artifact for potential manual use.

**To verify**: After `nono pull nolabs-ai/nono`, run `copilot plugin list` (or equivalent) and confirm the plugin appears. If not, try `copilot plugin marketplace add ~/.copilot/installed-plugins/nolabs-ai/nono/wiring/marketplace.json`.

### 4. `policy.json` — `add_deny_access` field
**Gap**: The `copilot-cli/policy.json` uses `"policy": { "add_deny_access": ["$HOME/.nono"] }`. This field does not appear in the `claude` or `codex` profiles. It may be an outdated or non-standard field name.

**To verify**: Check the nono profile schema (run `nono profile guide`) to confirm whether `add_deny_access` is a valid key. If not, the correct equivalent may be using a `deny` or `policy.override_deny` key depending on the nono version.

### 5. Linux support
**Current state**: `"platforms": ["macos"]` only.

The `policy.json` allows `~/Library/Caches/copilot` (macOS-only) and `/usr/local/Caskroom/copilot-cli` (Homebrew Cask path). On Linux, Copilot's cache lives at `~/.cache/copilot/` and the binary installs elsewhere.

**To add Linux support**: extend `policy.json` with `$HOME/.cache/copilot` and the relevant Linux binary path, then add `"linux"` to `platforms`.

### 6. `plugin.json` — `skills` path resolution
**Gap**: The reference states skills default to `skills/`. The manifest sets `"skills": "./skills/"`. Whether Copilot resolves this path relative to the plugin manifest's location (the pack root) or the current working directory needs confirming.

**To verify**: Load the plugin and run `copilot /list-skills` (or equivalent) to confirm the `copilot-sandbox` skill appears.

---

## Directory Layout

```
copilot-cli/
├── NOTES.md                          (this file)
├── README.md
├── package.json                      (nono pack manifest)
├── plugin.json                       (Copilot CLI plugin manifest — found at pack root)
├── policy.json                       (nono sandbox profile, installed as "copilot-cli")
├── bin/
│   ├── nono-hook.sh                  (PostToolUseFailure)
│   ├── nono-hook-bash.sh             (PostToolUse — bash tool only)
│   └── nono-hook-session.sh          (SessionStart)
├── hooks/
│   └── hooks.json                    (Copilot hook registrations, referenced from plugin.json)
├── skills/
│   └── copilot-sandbox/
│       └── SKILL.md
└── wiring/
    └── marketplace.json              (Copilot marketplace entry — for manual registration)
```

---

## Release

Add a trusted publisher entry in the nono registry for:

| Field        | Value                                          |
|-------------|------------------------------------------------|
| Repository  | `nolabs-ai/nono-packs` (or your repo)    |
| Workflow    | `.github/workflows/publish-copilot-cli.yml`   |
| Ref pattern | `refs/tags/copilot-cli-v*`                    |

Then release with:

```bash
scripts/release.sh copilot-cli 1.0.0 --release
```

To verify after release:

```bash
nono pull nolabs-ai/nono --force
```
