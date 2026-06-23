---
name: nono-sandbox
description: Diagnose and resolve permission denials when Hermes Agent runs inside a nono security sandbox. Use when terminal, file, browser, MCP, plugin, or skill operations fail with "Operation not permitted", "Permission denied", EACCES, EPERM, landlock, or sandbox-denied errors.
version: 1.2.0
platforms: [macos, linux]
metadata:
  hermes:
    tags: [security, sandbox, nono, diagnostics]
    category: devops
---

# Working inside a nono sandbox

nono applies OS-level filesystem and network restrictions before Hermes starts. Landlock on Linux and Seatbelt on macOS enforce those restrictions outside the Hermes approval system.

Hermes cannot expand nono access from inside the session. YOLO mode, `/yolo`, `approvals.mode: off`, `chmod`, `sudo`, or macOS privacy prompts do not grant new nono capabilities.

## Provenance

This skill is bundled by the `nono-sandbox` Hermes plugin from the signed `nolabs-ai/hermes` nono pack. Load it explicitly as `skill_view("nono-sandbox:nono-sandbox")` when provenance matters.

## When to use this skill

Use this skill when a Hermes tool or subprocess fails with:

- `Operation not permitted`
- `Permission denied`
- `EACCES` or `EPERM`
- `landlock`
- `sandbox: deny` or `sandbox denied`

Common affected tools include `terminal`, `execute_code`, file read/write/edit tools, browser downloads, MCP subprocesses, plugin tools, and skill helper scripts.

## Diagnosis

1. Identify the concrete blocked path from the failed tool call, stderr, traceback, or command arguments.
2. Run:

   ```bash
   nono why --self --path /the/blocked/path --op read
   ```

3. Use `--op write` for write-only failures and `--op readwrite` when the operation needs both.
4. If `NONO_CAP_FILE` is set, inspect the current sandbox:

   ```bash
   nono_status
   ```

   If the plugin is not enabled, use:

   ```bash
   cat "$NONO_CAP_FILE"
   ```

## Remediation options

Present exactly two options to the user.

### Option A: one-off restart

Use this for a path needed only once:

```bash
nono run --profile hermes --allow /path/to/needed -- hermes
```

Use `--read` instead of `--allow` when Hermes only needs view access.

### Option B: profile draft

Create a profile draft under `~/.config/nono/profile-drafts/<name>.json`:

```json
{
  "extends": "hermes",
  "meta": { "name": "hermes-extra", "version": "1.0.0" },
  "filesystem": {
    "read": ["/path/to/needed"]
  }
}
```

Do not write directly to `~/.config/nono/profiles` from inside the sandbox. Active profiles control future sandbox policy and must stay behind a user review step.

The user reviews and promotes the draft outside the sandbox:

```bash
nono profile validate --draft hermes-extra
nono profile promote hermes-extra
```

Start future sessions with:

```bash
nono run --profile hermes-extra -- hermes
```

Use `read_file`, `write_file`, or `allow_file` only for exact single-file grants. Use `read`, `write`, or `allow` for directories.

## Hermes-specific notes

- The Hermes launcher may be a symlink under `~/.local/bin` pointing into `~/.hermes/hermes-agent/venv/bin`.
- uv-managed Python installs often live under `~/.local/share/uv`; Hermes needs read access to the interpreter and standard library there.
- Hermes state, logs, skills, sessions, pairing files, and `.env` live under `~/.hermes`. The base nono Hermes profile grants that directory read/write because Hermes needs its own state.
- The base Hermes profile defines provider credential routes but enables none by default. Users should create an extending profile and list only the needed routes in `network.credentials`.
- The Hermes nono profile uses env-var-shaped keychain accounts for provider credentials: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`, `GITHUB_TOKEN`, and `GITLAB_TOKEN`. `GEMINI_API_KEY` is only a Hermes alias; prefer `GOOGLE_API_KEY`.
- With nono v0.51 or newer, TLS CONNECT traffic to credentialed or endpoint-filtered routes is intercepted with a session-scoped CA bundle. L7 endpoint rules and credential injection apply to ordinary HTTPS SDK calls as long as the client honors `HTTP_PROXY`, `HTTPS_PROXY`, and the injected CA variables.
- If Python asks to write `__pycache__` under `~/.config/nono/packages/.../plugin/nono-sandbox`, do not grant it. Restart Hermes with `PYTHONDONTWRITEBYTECODE=1` instead so signed package contents stay read-only.
- For gateway deployments, prefer Hermes' container backends and keep explicit allowlists enabled.
- Do not add Hermes infrastructure secrets to generic env passthrough. Prefer Hermes' dedicated credential mechanisms and nono proxy credentials.

## Do not do

- Do not suggest Full Disk Access, chmod, chown, or sudo for nono denials.
- Do not retry a blocked tool through a different path.
- Do not tell the user Hermes approval can fix a nono denial.
- Do not edit registry-managed package files under `~/.config/nono/packages`; create a profile extension instead.
