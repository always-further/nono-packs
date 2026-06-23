# openclaw nono Pack

`openclaw` is a `nono` package for running OpenClaw AI agents inside a nono security sandbox.

It ships a nono profile covering all standard OpenClaw instance directories, a skill that teaches agents their sandbox constraints, and a hook that fires contextual diagnostics on permission failures.

## What It Does

**Multi-instance filesystem coverage**

The built-in `openclaw` profile only allows `~/.openclaw`. Running a second or third agent instance (`~/.openclaw-agent1`, `~/.openclaw-agent2`, `~/.openclaw-agent3`) would otherwise be blocked. This pack's profile covers all standard instance directories so any agent variant runs without filesystem errors out of the box.

**Sandbox-aware diagnostics for all model types**

When a tool call hits a sandbox boundary, the installed hooks detect the denial and inject the exact blocked path, the current capability set, and a ready-to-use profile template — so the agent presents the user with the two right options instead of guessing.

Two hooks run in tandem to cover every session type:
- **PostToolUseFailure** (`settings.json`): fires immediately after a tool fails in Claude/pi-embedded sessions — injects context before the agent responds
- **message_sending** (`nono-hooks/index.js`): fires on outgoing messages in native gateway sessions (Gemini, etc.) — appends context when the agent reports a denial

**Multi-agent coordination**

All sandboxed OpenClaw instances on the same machine share `$TMPDIR/openclaw-$UID` as a lightweight coordination bus. This lets peer agents signal task ownership, share state, and avoid duplicate work without network calls or breaking sandbox isolation.

## Installation

Requires nono ≥ 0.44.0.

```bash
nono pull nolabs-ai/openclaw
```

## Usage

**Single agent**

```bash
nono run --profile openclaw -- openclaw
```

**Named agent instance**

```bash
nono run --profile openclaw --home ~/.openclaw-agent1 -- openclaw
```

## Included Artifacts

| Artifact | Type | Purpose |
|---|---|---|
| `policy.json` | `profile` | nono sandbox profile covering all standard OpenClaw directories and coordination bus |
| `.openclaw-plugin/plugin.json` | `plugin` | OpenClaw bundle manifest — declares the plugin name, version, and skills directory |
| `skills/nono-sandbox/SKILL.md` | `plugin` | Teaches the agent its constraints and how to diagnose permission failures (all sessions) |
| `settings.json` | `plugin` | Pi-embedded settings that wire the PostToolUseFailure hook for Claude/Anthropic sessions |
| `bin/nono-hook.sh` | `plugin` | Shell hook: injects capability context and remediation options on permission denial |
| `nono-hooks/openclaw.plugin.json` | `plugin` | Native plugin manifest for the nono-hooks plugin |
| `nono-hooks/index.js` | `plugin` | Native message_sending hook: fires for Gemini and all non-Claude model sessions |
| `wiring/marketplace.json` | `plugin` | Marketplace manifest describing the `nolabs-ai` plugin registry |
| `wiring/known-marketplaces.json` | `plugin` | Registers the `nolabs-ai` marketplace in OpenClaw's known-marketplaces list |
| `wiring/installed-plugin.json` | `plugin` | Marks both plugins as installed in OpenClaw's plugin registry |

## Policy Details

The profile:
- Extends `default` (inherits all standard security groups)
- Allows `~/.openclaw`, `~/.openclaw-agent1/2/3`, `~/.config/openclaw`, `~/.config/nono/profile-drafts`, `~/.openclaw.json`
- Reads `~/.config/nono/packages`, `~/.config/nono/profiles`
- Allows `$TMPDIR/openclaw-$UID` as the coordination bus
- Adds `node_runtime`, `linux_runtime_state`, `linux_sysfs_read`, `git_config` security groups
- Sets `signal_mode: isolated` and `ipc_mode: shared_memory_only`
- Network: not blocked
- Workdir: read-only
- Non-interactive

## Package Metadata

- Name: `openclaw`
- Platforms: `macos`, `linux`
- License: `Apache-2.0`
- Min nono version: `0.44.0`

## Directory Layout

```
openclaw/
├── .openclaw-plugin/
│   └── plugin.json
├── bin/
│   └── nono-hook.sh
├── nono-hooks/
│   ├── index.js
│   └── openclaw.plugin.json
├── package.json
├── policy.json
├── README.md
├── settings.json
├── skills/
│   └── nono-sandbox/
│       └── SKILL.md
└── wiring/
    ├── installed-plugin.json
    ├── known-marketplaces.json
    └── marketplace.json
```
