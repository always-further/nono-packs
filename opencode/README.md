# opencode nono

`opencode` is a `nono` package for [opencode](https://github.com/opencode-ai/opencode).

It installs a sandbox profile, a TypeScript plugin, and a skill that make opencode behave correctly when running inside a `nono` security sandbox — including credential injection, detach/attach session support, and denial diagnostics.

## What It Does

The pack provides:

- a sandbox profile (`policy.json`) granting the correct filesystem and network access, with credential injection routes for OpenAI, Anthropic, Gemini, GitHub, and GitLab
- a TypeScript plugin (`plugin/nono-sandbox.ts`) that injects nono sandbox context at session start, detects denial signatures in tool results, appends capability context and Option A/B remediation guidance, surfaces the network egress allowlist, and registers a `nono-status` command
- a `nono-sandbox` skill that teaches the correct diagnostic flow for filesystem and network-egress denials, credential route setup, and detach/attach usage

## Behavior

When opencode is running inside a `nono` sandbox the installed plugin:

- no-ops if `NONO_CAP_FILE` is not set (not inside a nono session)
- injects sandbox context into the system prompt at session start so the model knows the rules before its first tool call
- surfaces the session ID (for `nono attach`) when running detached
- detects sandbox-denial signatures in tool results (`Operation not permitted`, `EACCES`, `EPERM`, `landlock`)
- appends the active capability set, credential route summary, and remediation instructions so the model always receives correct guidance
- reports the network egress allowlist (reachable hosts) with state-aware guidance for blocked, allowlisted, and unrestricted networking
- steers the model toward the two valid remediations: `--allow` restart or a persistent profile draft

This prevents common bad guidance such as retrying the same action, suggesting `chmod`, attempting network workarounds, or treating the failure as a macOS TCC issue.

## Credential Injection

nono intercepts outbound HTTPS and injects API keys from its keychain — opencode never sees the raw secret. Routes are defined in the profile but **disabled by default**.

To enable a route, create an extending profile:

```json
{
  "extends": "opencode",
  "meta": { "name": "opencode-with-anthropic", "version": "1.0.0" },
  "network": { "credentials": ["anthropic"] }
}
```

Built-in route names: `openai`, `anthropic`, `gemini`, `github`, `gitlab`.

Store the corresponding secret in the nono keychain under the env-var-shaped account name (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.).

## Detach and Attach

Run opencode in a detached session that survives terminal disconnects:

```bash
nono run --profile opencode --detach -- opencode
```

Reattach from any terminal:

```bash
nono attach <session-id>
```

The `nono-status` command (registered by the plugin) shows the active session ID and capability set.

## Install

```bash
nono pull always-further/opencode
```

Or let nono prompt you on first use:

```bash
nono run --profile opencode -- opencode
```

## Activation

After pulling, opencode reads the plugin from `$XDG_CONFIG_HOME/opencode/plugins/nono-sandbox.ts` and the skill from `$XDG_CONFIG_HOME/opencode/skills/nono-sandbox/SKILL.md`. Both are symlinked from the pack store and update automatically on `nono pull`. If `XDG_CONFIG_HOME` is unset, the default `~/.config` applies.

## Removing

```bash
nono remove always-further/opencode
```

## Package Metadata

- Name: `opencode`
- Version: `0.0.6`
- Pack type: `agent`
- Platforms: `macos`, `linux`
- License: `Apache-2.0`
