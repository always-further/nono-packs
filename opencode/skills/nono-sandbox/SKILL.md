---
name: nono-sandbox
description: Diagnose and resolve permission denials when OpenCode runs inside a nono security sandbox. Use this when a Bash command, file read/write/edit, or MCP tool fails with "Operation not permitted", "Permission denied", EACCES, or EPERM — the cause is almost certainly the outer nono sandbox.
---

# Working inside a nono sandbox

The user has launched you with `nono run --profile <name> -- opencode`. nono enforces filesystem and network limits at the OS level (Landlock on Linux, Seatbelt on macOS). Approval flows inside OpenCode cannot grant access that nono hasn't already permitted.

## Identifying a sandbox denial

The denial signature is in the failed tool's output:

- "Operation not permitted"
- "Permission denied"
- "EACCES" / "EPERM"
- "landlock"
- "sandbox: deny"

When you see any of these on a Bash, read/write/edit, or MCP file-tool failure, it is a nono boundary — not macOS TCC, not Full Disk Access, not Unix file permissions, not an OpenCode approval. Do NOT suggest:

- System Settings / Privacy & Security
- `chmod`, `chown`, `sudo`
- "grant Full Disk Access to your terminal"
- Bypassing with a permission flag

## Diagnosing

Run `nono why` to see exactly why access was denied:

    nono why --path /the/blocked/path --op read

The output names the rule that blocked the path and suggests the minimum grant to allow it.

## Two options to present to the user

### Option A — quick fix (one-off)

Exit OpenCode and restart with the path explicitly allowed:

    nono run --allow /path/to/needed -- opencode

Use this for paths the user only needs occasionally.

### Option B — persistent fix (write a profile)

Save a JSON file at `~/.config/nono/profiles/<chosen-name>.json` extending the active profile and adding the path. Minimal example for read-only access:

    {
      "extends": "opencode",
      "meta": { "name": "<chosen-name>", "version": "1.0.0" },
      "filesystem": { "read": ["/path/to/needed"] }
    }

If the user is on a custom intermediate profile (e.g. `--profile opencode-with-docs` extending `opencode`), change `extends` to that profile's name so the new profile inherits all their customisations.

Filesystem field choices:
- `"read"` — read-only directory or file access
- `"write"` — write-only access (rare)
- `"allow"` — read+write directory access

For a single file rather than a directory, use `"allow_file"` / `"read_file"` / `"write_file"` instead.

After saving, the user starts sessions with:

    nono run --profile <chosen-name> -- opencode

## Validating the new profile

If the user wants to verify the JSON before using it:

    nono profile validate <chosen-name>

## Checking what is currently allowed

If `NONO_CAP_FILE` is set, it points to a JSON file listing the active capabilities:

    cat "$NONO_CAP_FILE" | jq .

The file contains `fs` (array of `{ path, resolved, access }`) and `net_blocked` (boolean).

## What you should NOT do

- Do not write the profile yourself unless the user explicitly asks for Option B. Present both options first.
- Do not edit the pack-installed profile at `~/.config/nono/packages/always-further/opencode/policy.json` — it is overwritten on every `nono pull`.
- Do not retry the failing operation in a different way. The sandbox is OS-enforced; alternative paths or commands hit the same boundary.
