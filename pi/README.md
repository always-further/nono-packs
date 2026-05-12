# nono pi

Sandbox profile for running [Pi](https://pi.dev/) inside a [nono](https://nono.sh) security sandbox.

Install and run:

```
mkdir -p ~/.pi && nono run --profile pi -- pi
```

The `mkdir` is needed on first run — macOS Seatbelt can only grant access to paths that already exist. After the first run `~/.pi` persists and you can drop it.

If the pack isn't already installed, nono will prompt to pull it.

## What's in the pack

- **`policy.json`** — sandbox profile (loaded as `--profile pi`). Grants `~/.pi`, `~/.agents`, runtime groups for Node, Python, Nix, and git config access. Network is filtered to the `developer` profile (LLM APIs, package registries, GitHub) plus Pi-specific endpoints.

## Network access

The profile uses the `developer` network profile and additionally allows:

- `api.z.ai` — Z.ai model hosting
- `inference.baseten.co` — Baseten model hosting
- `api.cloudflare.com` — Cloudflare APIs
- `api.search.brave.com` — Brave Search API

`openrouter.ai` is already covered by the `developer` profile's `llm_apis` group.

Port `1234` is open for Pi's local IPC.

## fnm users (macOS)

If you use `fnm` for Node version management, the profile already includes the standard fnm paths. No extra flags needed.
