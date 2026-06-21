---
name: nono-sandbox
description: Diagnose and resolve permission denials when Oh My Pi runs inside a nono security sandbox. Use this when a tool call, shell command, file operation, extension, package install, or provider request fails with "Operation not permitted", "Permission denied", EACCES, EPERM, landlock, or sandbox-denied errors.
version: 1.0.0
platforms: [macos, linux]
---

# Working inside a nono sandbox

The user has launched Oh My Pi with `nono run --profile <name> -- omp`. nono enforces filesystem and network limits at the OS level before Oh My Pi starts. Landlock on Linux and Seatbelt on macOS enforce those rules outside Oh My Pi's approval and extension systems.

Oh My Pi cannot expand nono access from inside the session. Retries, approval prompts, chmod, chown, sudo, or macOS privacy settings do not grant new nono capabilities.

## When to use this skill

Use this skill when an Oh My Pi tool, extension, package install, shell command, MCP subprocess, or provider request fails with:

- `Operation not permitted`
- `Permission denied`
- `EACCES` or `EPERM`
- `landlock`
- `sandbox: deny` or `sandbox denied`

## Diagnosis

1. Identify the concrete blocked path or network action from the failed tool call, stderr, traceback, or command arguments.
2. Run:

   ```bash
   nono why --self --path /the/blocked/path --op read
   ```

3. Use `--op write` for write-only failures and `--op readwrite` when the operation needs both.
4. If `NONO_CAP_FILE` is set, inspect the current sandbox:

   ```bash
   cat "$NONO_CAP_FILE"
   ```

## Remediation options

Present exactly two options to the user.

### Option A: one-off restart

Use this for a path needed only once:

```bash
nono run --profile omp --allow /path/to/needed -- omp
```

Use `--read` instead of `--allow` when Oh My Pi only needs view access.

### Option B: profile draft

Create a profile draft under `~/.config/nono/profile-drafts/<name>.json`:

```json
{
  "extends": "omp",
  "meta": { "name": "omp-extra", "version": "1.0.0" },
  "filesystem": {
    "read": ["/path/to/needed"]
  }
}
```

Do not write directly to `~/.config/nono/profiles` from inside the sandbox. Active profiles control future sandbox policy and must stay behind a user review step.

The user reviews and promotes the draft outside the sandbox:

```bash
nono profile validate --draft omp-extra
nono profile promote omp-extra
```

Start future sessions with:

```bash
nono run --profile omp-extra -- omp
```

Use `read_file`, `write_file`, or `allow_file` only for exact single-file grants. Use `read`, `write`, or `allow` for directories.

## OMP-specific notes

- Oh My Pi state and sessions live under `~/.omp`. The base nono OMP profile grants this directory read/write because Oh My Pi needs its own state.
- Oh My Pi discovers extensions and skills natively; no settings.json configuration is required.
- The OMP profile is intentionally minimal. To add filesystem paths or network routes, create an extending profile using Option B above.

## Do not do

- Do not suggest Full Disk Access, chmod, chown, or sudo for nono denials.
- Do not retry a blocked tool through a different path.
- Do not tell the user Oh My Pi approval can fix a nono denial.
- Do not edit registry-managed package files under `~/.config/nono/packages`; create a profile extension instead.
