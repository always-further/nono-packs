# copilot-cli nono Pack

`copilot-cli` is a `nono` pack for running [GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli) (`copilot`) inside a nono security sandbox.


## What It Does

- Confine Copilot CLI to the working directory, its own config (`~/.copilot/`), and cache (`~/Library/Caches/copilot/`, `~/.cache/copilot/`)
- Allow access to the Copilot CLI binary at `/usr/local/Caskroom/copilot-cli`
- Include read-only access to `~/.config/gh`
- Block all other filesystem paths at the kernel level

The pack ships three profiles: a shared base (`copilot-cli-base`) and two authentication-specific profiles that extend it:

| Profile | Auth method | Best for |
|---|---|---|
| `copilot-cli` | `gh auth` session | Users already authenticated with the `gh` CLI |
| `copilot-cli-proxy` | Keychain credential injection | Isolated sessions, CI, or token-based access |
---

### Setup

**Step 1 — Authenticate with `gh`**

```bash
gh auth login
```

Follow the prompts to authenticate with GitHub. The profile reads `~/.config/gh` as read-only to pick up the active session.

**Step 2 — Run**

```bash
nono run --profile copilot-cli -- copilot
```

---

### For profile `copilot-cli-proxy`

Authentication is handled by nono's credential injection. A GitHub token is read from the OS keychain at session start and injected as a `Token` header for requests to `https://github.com`. The token is never passed to the `copilot` process directly.

**Step 1 — Create a fine-grained personal access token**

1. Go to **GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens**
2. Click **Generate new token**
3. Fill in the token name, expiration, and resource owner
4. Under **Permissions**, enable **Copilot Requests**
5. Click **Generate token** and copy the value (`github_pat_...`)

**Step 2 — Add the token to the macOS Keychain**

```bash
security add-generic-password -s "nono" -a "copilot_github_token" -w
```

Omitting the value from the command line causes `security` to prompt for it interactively, keeping the token out of shell history and the process list. The token is stored under service `nono`, account `copilot_github_token`.

**Step 3 — Run**

```bash
nono run --profile copilot-cli-proxy -- copilot
```
---

## Installation

```bash
nono pull nolabs-ai/copilot-cli
```

All three profiles are installed automatically. Use `--profile copilot-cli` or `--profile copilot-cli-proxy` to select one at runtime. `copilot-cli-base` can be used directly but has no auth configuration, so it would requires manual login.

## Included Artifacts

| Artifact | Type | Purpose |
|---|---|---|
| `profiles/copilot-base.json` | profile | Shared base profile (`copilot-cli-base`) — extended by both auth profiles |
| `profiles/copilot-gh.json` | profile | Sandbox profile using `gh` auth (`copilot-cli`) |
| `profiles/copilot-proxy.json` | profile | Sandbox profile using credential injection (`copilot-cli-proxy`) |
| `skills/copilot-sandbox/SKILL.md` | instruction | Teaches the agent its sandbox constraints |
| `bin/nono-hook.sh` | script | `PostToolUseFailure` hook — injects sandbox capability context on tool failure |
| `bin/nono-hook-bash.sh` | script | `PostToolUse` hook — detects denial patterns in bash output and injects context |
| `bin/nono-hook-session.sh` | script | `SessionStart` hook — injects a brief sandbox boundary statement at session start |
| `hooks/hooks.json` | config | Wires the three hooks into the Copilot CLI plugin runtime |

## Package Metadata

- Name: `copilot-cli`
- Pack type: `agent`
- Platforms: `macos`
- License: `Apache-2.0`
- Min nono version: `0.44.0`

## Directory Layout

```
copilot-cli/
├── bin/
│   ├── nono-hook.sh
│   ├── nono-hook-bash.sh
│   └── nono-hook-session.sh
├── hooks/
│   └── hooks.json
├── package.json
├── profiles/
│   ├── copilot-base.json
│   ├── copilot-gh.json
│   └── copilot-proxy.json
├── README.md
├── skills/
│   └── copilot-sandbox/
│       └── SKILL.md
└── wiring/
    ├── enabled-plugin.json
    └── marketplace.json
```
