# nono opencode

Sandbox profile and OpenCode plugin for running [OpenCode](https://opencode.ai) inside a [nono](https://nono.sh) security sandbox.

Install:

```
nono run --profile opencode -- opencode
```

If the pack isn't already installed, nono will prompt to pull it.

## What's in the pack

- **`policy.json`** — sandbox profile (loaded as `--profile opencode`). Grants `~/.opencode`, `~/.config/opencode`, `~/.cache/opencode`, `~/.local/share/{opencode,opentui}`, `~/.local/state/opencode`, `~/.config/nono/{profiles,packages}` (profiles writeable, packages read-only), and runtime groups for Node, opencode-linux, git config, and unlink protection.
- **`plugin/nono-sandbox.ts`** — OpenCode plugin. Hooks `tool.execute.after` and, when a tool result contains a sandbox-denial signature (`Operation not permitted`, `EACCES`, `EPERM`, `landlock`, etc.), appends a structured diagnostic to the result so the model sees the boundary, the allow-list, and the two remediation options on its next turn.
- **`skills/nono-sandbox/SKILL.md`** — skill describing how to diagnose and resolve sandbox denials. OpenCode loads it via the native `skill` tool.

## Activating the plugin

`nono pull always-further/opencode` symlinks the plugin into `~/.config/opencode/plugins/nono-sandbox.ts` and the skill into `~/.config/opencode/skills/nono-sandbox/`. OpenCode auto-discovers both at startup — no `opencode.json` edit required.

The plugin is silent outside a nono session (it checks `NONO_CAP_FILE` and exits early if unset), so it stays out of the way for ordinary OpenCode runs.

## Source

`https://github.com/always-further/nono-packs/tree/main/opencode`

Published via Sigstore-signed releases triggered by tags matching `opencode-v*`.
