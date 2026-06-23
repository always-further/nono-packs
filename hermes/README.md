<p align="center">
  <img src="./assets/logo.png" alt="nono codex" width="500" />
</p>


AI agents are powerful - and that's the problem. An agent with access to your shell, your files, and your API keys is also a target. A malicious prompt, a compromised tool, or a supply-chain attack in a dependency can turn Hermes against you: exfiltrating source code, leaking credentials, or making API calls you never authorised.

This plugin runs [Hermes Agent](https://hermes-agent.nousresearch.com/) inside a [nono](https://nono.sh) security sandbox to limit the damage if something goes wrong:

- **Your API keys stay out of the process.** nono uses a phantom credential model — Hermes never sees your real keys. The proxy swaps in the real credential only at the network boundary, so a compromised agent or tool cannot steal and reuse them elsewhere.
- **File access is locked to what you allow.** The OS kernel (Landlock on Linux, Seatbelt on macOS) enforces which paths Hermes can read or write. It cannot reach your SSH keys, dotfiles, or anything outside the declared scope — regardless of what it's instructed to do.
- **Credential misuse is blocked at the API level.** Even when Hermes has network access, each credential route can be locked to a specific set of API endpoints. A phantom token for your OpenAI key can be restricted to `/v1/chat/completions` only — so a compromised agent cannot use it to query billing, enumerate your organisation, or hit any other API surface you haven't explicitly permitted.
- **Every session is audited.** nono writes a tamper-evident, append-only log of everything Hermes did — commands, capability decisions, network events, and filesystem paths — so you can review exactly what happened after the fact.
- **Undo agent sessions with rollbacks.** nono can snapshot the filesystem before Hermes runs and give you a per-file diff and interactive restore prompt when it exits, so you can reverse changes without having to work out what the agent touched by hand.


## Installation

### Installing nono

Installation instructions are available on [nono's documentation site](https://nono.sh/docs), after intstalling nono, you can install the hermes plugin.

### Installing the hermes plugin

Pull the package first, then create a custom profile before running. This avoids the interactive grants prompt that appears when nono encounters paths the base profile doesn't cover:

**Step 1 — pull the package:**

```bash
nono pull nolabs-ai/hermes
```

**Step 2 — create a custom profile:**

```bash
nono profile init hermes --extends nolabs-ai/hermes --full
```

**Step 3 — run Hermes:**

```bash
nono run --profile hermes --allow-cwd -- hermes
```

A custom profile is also where you add credential routes, extra filesystem grants, and any other customizations — see the sections below.

### First-run grants prompt

If you run nono before creating a custom profile, nono may detect paths that Hermes needs but that the base profile doesn't cover — your shell config, a tool on a non-standard path, etc. When this happens you'll see a prompt like:

```
Sandbox denial: 3 paths blocked.
  ~/.config/gh (read)
  ~/dev/dotfiles/zsh (read)
  /usr/local/sbin (read)

[nono] Choose suppress to keep denying all listed paths and stop future save suggestions.
Save suggestions to a user profile? [g] grant / [s] suppress / [Enter] skip:
```

- **`g` (grant)** — saves the extra path grants to a user profile. Use the same name you plan to use for your custom profile (e.g. `hermes-agent`) so both sets of grants live in one place.
- **`s` (suppress)** — stops nono from suggesting these paths in future. The paths remain denied.
- **Enter (skip)** — skips saving for now. You'll be prompted again next time.

The cleanest approach is to skip (`Enter`) and add any extra paths manually to your child profile's `filesystem.read` or `filesystem.allow` block.

## Activating the plugin

Plugin activation happens automatically on first run, the package symlinks itself into:

```text
~/.hermes/plugins/nono-sandbox
```

and merges this into `~/.hermes/config.yaml`:

```yaml
plugins:
  enabled:
    - nono-sandbox
```

## Custom profiles

To create your own custom profile that extends the base `nolabs-ai/hermes` profile, use the `nono profile init` command with the `--extends` flag. This allows you to inherit from the base profile while customizing specific aspects such as credential routes and network filtering.

> If you already created a profile via the first-run grants prompt, use that same name here — `nono profile init` will extend it rather than creating a second one.

```bash
nono profile init hermes --extends nolabs-ai/hermes --full
```

This will create a `~/.config/nono/profile/hermes.json` file that you can then customize to your needs. The `--full` flag ensures that the generated profile includes all sections, making it easier to see what you can customize.

## Credential Protection

nono protects API keys using a **phantom credential** model. Rather than passing your real key into the sandbox, nono generates a short-lived random token and injects that into Hermes instead. When Hermes makes an outbound API call carrying the phantom token, nono's proxy intercepts the request, validates the token, fetches the real key from your system keystore (macOS Keychain, Linux Secret Service, 1Password, etc.), and swaps it in before the request leaves the machine. The real key is never visible to the sandboxed process, so even if Hermes or a tool it runs were compromised, an attacker would obtain only the useless phantom — not the credential itself.

> **Do not store API keys in `~/.hermes/.env`.** Hermes' own documentation suggests this as a general approach, but doing so places the real key directly in Hermes' environment and bypasses nono's phantom credential protection entirely. Keep keys in nono's keychain (or a URI ref source) and let nono inject them.

### Built-in providers

The base `hermes` profile does not enable provider credentials by default. This avoids warnings for unused providers from becoming part of the session boundary.

The following providers are built in and ready to use. How you store the key depends on the route — some read from the system keychain, others read from an environment variable in nono's own process

| Route Name  | Provider   | Storage method       | Key name / account  |
|-------------|------------|----------------------|---------------------|
| `openai`    | OpenAI     | nono keychain        | `OPENAI_API_KEY`    |
| `anthropic` | Anthropic  | nono keychain        | `ANTHROPIC_API_KEY` |
| `gemini`    | Gemini     | nono keychain        | `GOOGLE_API_KEY`    |
| `github`    | GitHub     | nono keychain        | `GITHUB_TOKEN`      |
| `gitlab`    | GitLab     | nono keychain        | `GITLAB_TOKEN`      |

Store each key in the nono keychain service using the exact account name shown in the table above. Then add the route name to the `credentials` array in your child profile's `network` block to activate it (see "Step 2 - enable the route in your profile"). The proxy will handle the rest — when Hermes makes a request to an API endpoint matching the route, nono swaps in the real key from the keychain before forwarding the request upstream.

#### Step 1 — store the key

**For keychain-backed routes** (`openai`, `gemini`):

macOS Keychain:

You can add the key with `security` or the Keychain UI. The `-a` flag sets the account name, which is how nono looks up the key at runtime. The `-s` flag sets the service, which nono uses to group related credentials together in the UI. The Apple keychain provides a secure level of isolation by service and account, so as long as you use a unique combination for your nono credentials they won't be visible to other apps on the system.

```bash
security add-generic-password -U -s "nono" -a "OPENAI_API_KEY" -w
security add-generic-password -U -s "nono" -a "ANTHROPIC_API_KEY" -w
security add-generic-password -U -s "nono" -a "GOOGLE_API_KEY" -w
security add-generic-password -U -s "nono" -a "GITHUB_TOKEN" -w
security add-generic-password -U -s "nono" -a "GITLAB_TOKEN" -w
```

Keep `-w` last so macOS prompts for the value instead of recording it in shell history.

Linux Secret Service:

```bash
secret-tool store --label="nono: OPENAI_API_KEY" \
  service nono username OPENAI_API_KEY target default

secret-tool store --label="nono: GOOGLE_API_KEY" \
  service nono username GOOGLE_API_KEY target default
```

On Linux this requires a running Secret Service provider such as GNOME Keyring or KWallet. In SSH-only or headless environments, check the nono credential docs before choosing a storage backend.

If your keys live in 1Password, a file, or an environment variable, you can override any built-in route using `custom_credentials` — see the [Custom providers](#custom-providers) section below for field details and examples.

For the full credential URI ref model (`op://`, `apple-password://`, `file://`, `env://`), see:

- https://nono.sh/docs/cli/features/credential-injection

#### Step 2 — enable the route in your profile

Open your child profile (`~/.config/nono/profile/hermes.json`) and add the route name to the `credentials` array in the `network` block:

```json
"network": {
  "block": false,
  "allow_domain": [],
  "credentials": ["anthropic"],
  "open_port": [],
  "listen_port": [],
  "custom_credentials": {}
}
```

You can enable multiple providers at once:

```json
"credentials": ["anthropic", "github"]
```

Then run Hermes with your child profile:

```bash
nono run --profile hermes-agent -- hermes
```

### Custom providers

If the provider you need isn't in the built-in list, you can add it with `custom_credentials`. The same phantom-token swap mechanism applies — you define the upstream URL, the keychain account to use, and optionally which API endpoints are permitted.

This example adds [OpenRouter](https://openrouter.ai) — an OpenAI-compatible model-routing API that authenticates with `Authorization: Bearer <key>`.

#### How phantom credentials work

nono generates a phantom token and injects it into Hermes as an environment variable. When Hermes makes an outbound call, the proxy validates the phantom, fetches the real key from the keystore, and swaps it in before the request leaves the machine. The credential never enters the sandbox — Hermes only ever sees the short-lived phantom.

#### Step 1 — store the key

Store the key in your system keyring under the account name you'll reference in the profile (`OPENROUTER_API_KEY` here).

macOS Keychain:

```bash
security add-generic-password -U -s "nono" -a "OPENROUTER_API_KEY" -w
```

Linux Secret Service:

```bash
secret-tool store --label="nono: OPENROUTER_API_KEY" \
  service nono username OPENROUTER_API_KEY target default
```

If the key lives somewhere other than the system keyring, point `credential_key` at it with a URI ref instead:

```json
"credential_key": "env://OPENROUTER_API_KEY"
```
Reads the key from `OPENROUTER_API_KEY` in nono's own environment. `env_var` is not required for this form.

```json
"credential_key": "op://Personal/OpenRouter/credential",
"env_var": "OPENAI_API_KEY"
```
Fetches the key from 1Password at runtime. `env_var` is required for `op://` so nono knows which variable to inject into the sandbox.

```json
"credential_key": "file:///run/secrets/openrouter.key",
"env_var": "OPENAI_API_KEY"
```
Reads the key from a file. `env_var` is required for `file://`.

#### Step 2 — add the route to your profile

Open your child profile (`~/.config/nono/profile/hermes.json`) and update the `network` block:

```json
"network": {
  "block": false,
  "allow_domain": [],
  "credentials": ["openrouter"],
  "open_port": [],
  "listen_port": [],
  "custom_credentials": {
    "openrouter": {
      "upstream": "https://openrouter.ai/api/v1",
      "credential_key": "OPENROUTER_API_KEY",
      "env_var": "OPENAI_API_KEY"
    }
  }
}
```

Note: keep the real OpenRouter secret stored under `OPENROUTER_API_KEY`, but inject the phantom token into `OPENAI_API_KEY` for Hermes. Hermes currently chooses API-key environment variables by inspecting the configured base URL host. Inside nono, Hermes sees the local proxy URL (`http://127.0.0.1:<port>/openrouter`), not `openrouter.ai`, so it follows its OpenAI-compatible fallback path and reads `OPENAI_API_KEY` before `OPENROUTER_API_KEY`.

The map key (`"openrouter"`) is the route name. **It must also appear in the `credentials` array** — nono only activates routes explicitly listed there. `inject_header` and `credential_format` are omitted because the defaults (`"Authorization"` and `"Bearer {}"`) already match what OpenRouter expects.

For tighter control you can add `endpoint_rules` — a list of `{"method", "path"}` pairs that act as an L7 allow-list. When non-empty, the proxy rejects any request that doesn't match, even with a valid phantom token. This is useful if you want to restrict a credential to inference-only endpoints and block billing, account management, or other API surfaces the agent should never reach. Omit it, as above, to allow all paths under the route.

Run Hermes with your child profile:

```bash
nono run --profile hermes -- hermes
```

## Audit Logging

Every nono session produces an append-only audit log recording what Hermes did: the command and arguments (with secrets redacted), start/end timestamps, exit code, capability decisions, network events, and the filesystem paths it touched. Logs are written to `~/.nono/audit/` as `session.json` and `audit-events.ndjson`, and are tamper-evident by default.

```bash
nono audit list                          # all sessions
nono audit list --today                  # today only
nono audit list --command hermes         # filter by command
nono audit show <session-id>             # inspect a session
nono audit show <session-id> --json      # machine-readable
nono audit verify <session-id>           # verify log integrity
nono audit cleanup                       # remove old sessions
```

To disable audit logging for a session, pass `--no-audit`:

```bash
nono run --profile hermes --no-audit -- hermes
```

If you want the session log but don't need tamper-evident protection:

```bash
nono run --profile hermes --no-audit-integrity -- hermes
```

If you add secrets-adjacent flags to your Hermes invocation, you can extend nono's redaction rules so they never appear in the log. Add to `~/.config/nono/config.toml`:

```toml
[redaction]
extra_flags = ["--private-token", "--pat"]
extra_headers = ["Private-Token"]
extra_query_keys = ["sig", "signature"]
```

## Rollbacks

nono can snapshot the filesystem before Hermes runs and let you selectively restore any files it changed or deleted. This is useful when you want to review or undo an agent session without having to figure out what changed by hand.

```bash
nono run --rollback --profile hermes  -- hermes
```

With `--rollback` active, nono takes a baseline snapshot before execution and a final snapshot after. When Hermes exits, if any files were modified or deleted you get an interactive review showing a per-file diff and a prompt to restore whichever files you want back.

Snapshots are stored in `~/.nono/rollbacks/<session-id>/` using SHA-256 content-addressable storage with Merkle tree verification. On macOS (APFS) this is copy-on-write via `clonefile()`, so storage cost is low for sessions with few changes. nono keeps a maximum of 10 sessions and 5 GB by default.

```bash
nono rollback list                        # past sessions grouped by project
nono rollback show <id> --diff            # inspect what changed
nono rollback restore <id>                # interactive restore
nono rollback restore <id> --dry-run      # preview without writing
nono rollback verify <id>                 # check Merkle integrity
nono rollback cleanup --older-than 7      # remove sessions older than 7 days
```

To suppress the interactive review prompt (for scripting):

```bash
nono run --rollback --no-rollback-prompt --profile hermes -- hermes
```

Exclude noisy paths from snapshot tracking in your child profile:

```json
"rollback": {
  "exclude_patterns": ["node_modules", ".next", "__pycache__"],
  "exclude_globs": ["*.tmp.[0-9]*.[0-9]*"]
}
```

`.gitignore` entries in the working directory are also respected automatically.

## Run detached

By default, nono runs Hermes as a child process. This means if you stop the nono session, you also stop Hermes and any subprocesses it spawned. If you want Hermes to keep running after you exit nono, use `--detached`:

```bash
nono run --profile hermes --detached -- hermes
```

You can now attach to the running session later to review logs, check status, or run `nono why` queries:

```bash
nono attach <session-id>
```

To view details of all running sessions:

```bash
nono ps
```

## nono inbuilt helper commands

The plugin then exposes `/nono-status` and the `nono_status` tool after Hermes reloads.

Inside a running Hermes sandbox, use `nono why --self` so the query uses the sandbox context for any particular file or network access check:

```bash
nono why --self --path /path/to/some/file --op read
```



### Agent Profile Expansion and Promotion

When a sandbox denial occurs, the agent can draft profile changes, but it cannot directly edit active profiles under `~/.config/nono/profiles`. This keeps policy changes behind an explicit user promotion step. When the agent drafts a profile change, it writes the proposed profile to `~/.config/nono/drafts/<name>.json`. Review the draft, then promote it to make it active:

```bash
nono profile validate --draft hermes-agent
nono profile promote hermes-agent
```



### Uninstalling the plugin

```bash
nono remove nolabs-ai/hermes
```
