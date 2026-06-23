# nono goose

Sandbox profile and Goose Open Plugin for running [Goose](https://goose-docs.ai/) inside a [nono](https://nono.sh) security sandbox.

Install:

```bash
nono run --profile nolabs-ai/goose -- goose
```

If the pack is not already installed, nono will prompt to pull it.

## What's in the pack

- **`policy.json`** - sandbox profile loaded as `--profile goose`. Grants Goose config/cache/state, `~/.agents` for plugins and skills, standard Node/Rust/Python/Nix runtime groups, common provider auth origins, and read access to nono packages/profiles.
- **`plugin.json`** - Goose Open Plugin manifest. Goose discovers this pack from `~/.agents/plugins/nono`.
- **`hooks/hooks.json`** - Goose hook wiring for shell and tool-failure diagnostics.
- **`bin/nono-hook.sh`** - hook command that detects likely sandbox-denial output and prints nono-specific remediation guidance.
- **`skills/nono-sandbox/SKILL.md`** - Goose-native skill loaded as `nono:nono-sandbox`.
