# antigravity

A [`nono`](https://nono.sh) pack for the **Antigravity CLI** (`agy`, Google's
terminal coding agent — the successor to Gemini CLI).

It teaches `agy` how to behave inside a `nono` security sandbox: a
sandbox-awareness **skill** plus a **`PostToolUse` hook** that detects
kernel-level permission denials and injects precise diagnostics instead of
letting the agent flail with `sudo`/`chmod`/"let me try another approach".

This is a real Antigravity plugin — it passes `agy plugin validate` and appears
in `agy plugin list` (components: `skills`, `hooks`).

## What's in the pack

```
antigravity/
├── package.json                 # nono pack manifest + profile/wiring
├── policy.json                  # nono profile for agy (installed as antigravity / agy)
├── plugin.json                  # Antigravity plugin manifest (name, version, metadata)
├── hooks.json                   # PostToolUse hook registration (must be at plugin root)
├── bin/
│   ├── nono-hook.sh             # PostToolUse: detect sandbox denial → systemMessage
│   └── denial.txt               # diagnostic template (__CAPS__ / __NET__ substituted)
├── skills/
│   └── nono-sandbox/SKILL.md    # "/nono-sandbox" skill — how to work in the sandbox
└── wiring/
    ├── profile-drafts-dir-marker  # ensures ~/.config/nono/profile-drafts exists
    └── import-entry.json          # plugin record merged into agy's import manifest
```

### Skill

`skills/nono-sandbox/SKILL.md` is a standard Antigravity skill (`name` +
`description` frontmatter). It explains how the sandbox works, what to do on a
denial (run `nono why`, then offer a quick `--allow` restart or a drafted
profile), and how to inspect `$NONO_CAP_FILE`. It is exposed as the
`/nono-sandbox` slash command in `agy` and as a skill in the Antigravity IDE.

### Hook

`hooks.json` lives at the **plugin root** (`agy` ignores a `hooks/`
subdirectory) and registers one hook:

| Event         | Script             | Behaviour |
|---------------|--------------------|-----------|
| `PostToolUse` | `bin/nono-hook.sh` | Runs after every tool call. Scans the entire tool-result payload for a sandbox-denial signature (`Operation not permitted`, `EPERM`, `EACCES`, `landlock`, …). Only when one is found does it return `{ "systemMessage": "…" }` with the live capability list and the two recovery options. |

The payload is scanned wholesale (rather than reading specific fields) because
`agy`'s hook input is proto-backed and field names vary across versions.
Supported hook events are `PreToolUse`, `PostToolUse`, `Stop`, `Notification`
(there is no `SessionStart`/`AfterTool`), and the output channel is
`systemMessage`.

The hook is a no-op outside a sandbox: it exits `0` immediately when
`NONO_CAP_FILE` is unset/missing or `jq` is unavailable, so the plugin is safe
even when `agy` runs outside `nono`. The hook command points at
`~/.gemini/config/plugins/nono/bin/nono-hook.sh` (where `agy` installs the
plugin), and the script self-locates `denial.txt` via `dirname "$0"`.

Set `NONO_HOOK_DEBUG=1` (optionally `NONO_HOOK_LOG=/path`) to trace hook
decisions to `~/.gemini/antigravity-cli/nono-hook.log`.

## Install paths / wiring

`agy` stores plugins as **copies** under `~/.gemini/config/plugins/<name>/` and
records them in `~/.gemini/config/import_manifest.json`. The pack reproduces
that with file copies — never a symlink into the plugin store, because
`agy plugin install` copies onto its target and would clobber a symlinked
source.

| Wiring | Type | Purpose |
|--------|------|---------|
| `~/.gemini/config/plugins/nono/**` ← plugin files | `write_file` | Installs `plugin.json`, `hooks.json`, `bin/`, and the skill as real copies where `agy` discovers them. |
| `~/.gemini/config/import_manifest.json` `imports[]` ← `wiring/import-entry.json` | `json_array_append` | Registers the plugin so it appears in `agy plugin list` (deduped by `name`). |
| `~/.agents/skills/nono-sandbox` → `skills/nono-sandbox` | `symlink` | Also exposes the skill in the Antigravity IDE / workspace layout. |
| `~/.config/nono/profile-drafts/.nono-antigravity-pack-marker` ← marker | `write_file` | Ensures the profile-drafts directory exists so the agent can draft profiles. |

Verify with `agy plugin list` and `agy plugin validate ~/.gemini/config/plugins/nono`.

## The nono profile

The pack ships `policy.json`, the `nono` profile for `agy` (installed as
`antigravity`, alias `agy`). Launch a sandboxed session with:

```bash
nono run --profile antigravity -- agy
```

The profile is captured from runtime-discovered `agy` access (config under
`~/.gemini/antigravity-cli`, caches, language runtimes).

## Uninstalling

```bash
nono remove nolabs-ai/antigravity
```
