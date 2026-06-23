# nono-packs

`nono-packs` is the package and plugin registry for the `nono` ecosystem.

This repository is the source for installable packs that extend agent runtimes with `nono`-specific integrations such as:

- agent plugins
- hook definitions
- packaged skills
- support scripts and helper assets

Each top-level directory is an individual pack. Packs are described by a `package.json` manifest and can ship one or more artifacts that are installed into the target agent environment.

## Repository Layout

Current packs in this repository include:

- [`claude`](./claude): Claude Code integration for working inside the `nono` sandbox
- [`claude-autoresearch`](./claude-autoresearch): GPU-enabled profile and plugin for running [autoresearch](https://github.com/Kexin-xu-01/autoresearch-nono) autonomous ML loops inside the `nono` sandbox — A100/CUDA workloads with kernel-level enforcement inherited by training subprocesses
- [`codex`](./codex): Codex integration for working inside the `nono` sandbox
- [`goose`](./goose): Goose CLI profile and Open Plugin for working inside the `nono` sandbox
- [`pi`](./pi): Pi Coding Agent package and profile for working inside the `nono` sandbox

Typical pack contents:

- `package.json`: pack manifest used by the registry
- `README.md`: pack-specific documentation
- `skills/`: packaged skills distributed with the pack
- `hooks/`: hook registrations for the target runtime
- `bin/`: executable helper scripts used by hooks or setup flows

## What This Registry Is For

The goal of this repository is to keep agent-facing integrations versioned, reviewable, and distributable separately from the core `nono` runtime.

That allows a pack to:

- teach an agent how to behave correctly inside the `nono` sandbox
- install runtime-specific hooks
- bundle skills and prompts that improve sandbox diagnostics
- ship small helper scripts without coupling them to the main `nono` repository

## Pack Format

Each pack should define:

- a unique `name`
- a `pack_type`
- a short `description`
- supported `platforms`
- a `min_nono_version`
- an `artifacts` list describing what should be installed

The exact artifact set depends on the target runtime. For example, a Claude-oriented pack can include Claude plugin metadata, hook definitions, and sandbox-awareness skills.

## Local Development

Use `scripts/dev-install.sh` to install, update, or remove a pack directly from your local checkout without publishing to the registry. This is the primary workflow for testing changes before release.

```
scripts/dev-install.sh <command> <pack> [--namespace <ns>] [--dry-run]
```

**Commands:**

| Command | Description |
|---------|-------------|
| `install` | Apply all wiring from `<pack>/package.json` |
| `update` | Re-apply wiring (idempotent; safe to run after content changes) |
| `remove` | Undo all wiring from `<pack>/package.json` |

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--namespace <ns>` | `nolabs-ai` | Value substituted for `$NS` in wiring paths |
| `--dry-run` | — | Print every action without touching the filesystem |

**Examples:**

```bash
# Install the claude pack locally
scripts/dev-install.sh install claude

# Preview what remove would do without making changes
scripts/dev-install.sh remove codex --dry-run

# Re-apply after editing wiring files
scripts/dev-install.sh update copilot-cli

# Install under a custom namespace
scripts/dev-install.sh install openclaw --namespace my-fork
```

The script reads `package.json` from the pack directory, expands the variables `$HOME`, `$XDG_CONFIG_HOME`, `$NONO_CONFIG`, `$NONO_PACKAGES`, `$PACK_DIR`, `$NS`, and `$NOW`, then applies each entry in the `wiring` array. All six wiring types are supported: `symlink`, `write_file`, `json_merge`, `json_array_append`, `toml_block`, and `yaml_merge`. The `remove` command processes entries in reverse order and undoes each operation cleanly.

Profile artifacts are installed under `-dev` names so local testing does not shadow registry-installed profiles. For example, `scripts/dev-install.sh install codex` installs `--profile codex-dev`, and `scripts/dev-install.sh install opencode` installs `--profile opencode-dev`. The installer prints the available `--profile` values at the end.

`yaml_merge` requires PyYAML (`pip install pyyaml`). All other operations use the Python 3 standard library.

## Current Status

This repository is intended to host multiple packs, packages, and skills for the wider `nono` registry. The [`claude`](./claude) pack is the initial example and documents the expected structure for future additions. The [`claude-autoresearch`](./claude-autoresearch) pack extends it with GPU access and ML-specific filesystem grants for overnight autonomous research runs — see [Kexin-xu-01/autoresearch-nono](https://github.com/Kexin-xu-01/autoresearch-nono) for the full workload setup.
