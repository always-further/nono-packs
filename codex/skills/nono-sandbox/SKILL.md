---
name: nono-sandbox
description: Diagnose and resolve permission denials when Codex runs inside a nono security sandbox. Use this when a Bash command, apply_patch, or MCP tool fails with "sandbox-exec: sandbox_apply: Operation not permitted", "Operation not permitted", "Permission denied", EACCES, EPERM, landlock, or sandbox-denied output. Do not merely report the failure: explain it is a nono OS sandbox boundary, avoid TCC/chmod/sudo advice, and offer the two fixes: restart once with nono run --allow, or draft a persistent profile in ~/.config/nono/profile-drafts for nono profile promote.
---

# Working inside a nono sandbox

The user has launched you with `nono run --profile <name> -- codex`. nono enforces filesystem and network limits at the OS level (Landlock on Linux, Seatbelt on macOS). Approval flows inside Codex cannot grant access that nono hasn't already permitted.

## Identifying a sandbox denial

The denial signature is in the failed tool's output:

- "sandbox-exec: sandbox_apply: Operation not permitted"
- "Operation not permitted"
- "Permission denied"
- "EACCES" / "EPERM"
- "landlock"
- "sandbox: deny"

When you see any of these on a Bash, apply_patch, or MCP file-tool failure, it is a nono boundary — not macOS TCC, not Full Disk Access, not Unix file permissions, not a Codex approval. On macOS, `sandbox-exec: sandbox_apply: Operation not permitted` often means Codex tried to apply its own sandbox inside the already-running nono Seatbelt sandbox; treat it as the same capability problem.

Do NOT suggest:

- System Settings / Privacy & Security
- `chmod`, `chown`, `sudo`
- "grant Full Disk Access to your terminal"
- Bypassing with `--dangerously-skip-permissions`

## Diagnosing

Run `nono why` to see exactly why access was denied:

    nono why --path /the/blocked/path --op read

The output names the rule that blocked the path and suggests the minimum grant to allow it.

## Two options to present to the user

### Option A — quick fix (one-off)

Exit Codex and restart with the path explicitly allowed:

    nono run --allow /path/to/needed -- codex

Use this for paths the user only needs occasionally.

### Option B — persistent fix (draft a profile)

The active profile directory `~/.config/nono/profiles/` is read-only from inside the sandbox by design. Drafts are written to `~/.config/nono/profile-drafts/` and the user promotes them out-of-band with `nono profile promote`.

If `~/.config/nono/profile-drafts` does not exist or cannot be written, or `nono profile promote --help` is unavailable, do not try to modify profiles directly. Tell the user to upgrade nono, then rerun the draft flow.

Create the draft with the pack helper. Do not use `mkdir`, `printf`, `cat`, heredocs, shell redirection, or inline JSON to write profile drafts.

Do not run shell/file checks to discover the active profile; those checks may themselves be blocked by the current sandbox. For this local dev install, assume `codex-dev` unless the user says they launched Codex with a custom profile. Registry installs should use `codex`. Ask which profile they started with only when the user says they launched Codex with a custom profile.

For read-only directory access, run:

    ~/.codex/bin/nono-draft-profile --name codex-documents --extends codex-dev --read /path/to/needed

For read+write directory access, use `--allow` instead of `--read`. For a single file, use `--read-file` or `--allow-file`.

The helper writes this JSON shape to `~/.config/nono/profile-drafts/<chosen-name>.json`:

    {
      "extends": "<active-profile>",
      "meta": { "name": "<chosen-name>", "version": "1.0.0" },
      "filesystem": { "read": ["/path/to/needed"] }
    }

If the user is on a custom intermediate profile (e.g. `--profile codex-with-docs` extending `codex`), pass that profile name to `--extends` so the new profile inherits all their customisations.

The helper writes a `.base` hash automatically when updating an existing user profile. Do not draft a replacement with the active pack profile name; use a derived profile name such as `codex-documents`.

Always use the helper or a structured file-edit tool; never redirect to the `profile-drafts/` directory itself.

Filesystem field choices:
- `"read"` — read-only directory or file access
- `"write"` — write-only access (rare)
- `"allow"` — read+write directory access

For a single file rather than a directory, use `"allow_file"` / `"read_file"` / `"write_file"` instead.

After drafting, tell the user:

    Drafted profile <chosen-name>. Run `nono profile promote <chosen-name>` to review and apply, then start sessions with `nono run --profile <chosen-name> -- codex`.

## Validating the new profile

`nono profile promote` shows a diff and validates before applying. If the user wants to validate the draft directly:

    nono profile validate --draft <chosen-name>

## What you should NOT do

- Do not write the profile yourself unless the user explicitly asks for Option B. Present both options first.
- Do not edit the pack-installed profile at `~/.config/nono/packages/nolabs-ai/codex/policy.json` — it's overwritten on every `nono pull`.
- Do not retry the failing operation in a different way. The sandbox is OS-enforced; alternative paths or commands hit the same boundary.
