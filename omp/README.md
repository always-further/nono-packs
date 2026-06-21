# omp

Oh My Pi coding harness plugin and matching nono profile for working inside the [nono](https://nono.sh) security sandbox.

## What this pack provides

- **Sandbox profile** (`omp`) — filesystem, network, and runtime toolchain grants so OMP can operate inside nono
- **Sandbox awareness extension** — hooks into OMP's event system to detect permission denials and inject diagnostic guidance
- **Sandbox skill** — detailed diagnosis and remediation documentation reachable via `skill://nono-sandbox`

## Quick start

```bash
# Install the pack
nono pack install omp

# Run OMP inside the sandbox
nono run --profile omp -- omp
```

## What the profile grants

| Resource | Access | Reason |
|----------|--------|--------|
| `~/.omp/` | read/write | OMP config, sessions, plugins, logs, extensions, skills |
| `$NONO_CONFIG/profile-drafts/` | read/write | User-authored profile extensions |
| `$NONO_PACKAGES`, `$NONO_CONFIG/profiles` | read | Registry-managed pack files |
| Network | all outbound | Provider APIs, MCP servers, package registries |

The profile is intentionally minimal — no credential routes, no provider-specific URL allowlists. Extend with `"extends": "omp"` in a profile draft for tighter controls.

## Sandbox awareness

When OMP starts inside nono (`NONO_CAP_FILE` is set), the extension:

1. Injects sandbox context into the system prompt so the agent knows it's sandboxed
2. Detects permission denials in tool results and appends diagnostic guidance
3. Registers a `/nono-status` command to inspect the current sandbox

When a tool fails with `Operation not permitted`, `Permission denied`, `EACCES`, `EPERM`, `landlock`, or `sandbox denied`, the extension attaches remediation steps directly to the tool output.

## Status indicator

When running inside nono, the extension shows a "nono sandbox" entry above the status panel so the agent and user are always aware of the sandbox boundary. This is on by default (`OMP_NONO_STATUS_INDICATOR=true`, injected by the profile via `environment.set_vars`).

To disable it, edit the installed profile (`~/.config/nono/profiles/omp.json`, or `omp-dev.json` for local dev installs) and set the variable to `"false"`:

```json
"environment": {
  "set_vars": { "OMP_NONO_STATUS_INDICATOR": "false" }
}
```

Denial detection and system-prompt context injection remain active either way; only the status entry is suppressed.

## Extending the profile

Create a profile draft to add grants:

```json
{
  "extends": "omp",
  "meta": { "name": "omp-extra", "version": "1.0.0" },
  "filesystem": {
    "read": ["/path/to/data"]
  },
  "network": {
    "credentials": ["openai", "anthropic"]
  }
}
```

Then promote it outside the sandbox:

```bash
nono profile validate --draft omp-extra
nono profile promote omp-extra
nono run --profile omp-extra -- omp
```

## License

Apache-2.0
