import * as fs from "fs"

const DENIAL_PATTERN =
  /operation not permitted|permission denied|eperm|eacces|sandbox.*denied|landlock/i

const PATH_RE = /(?:~\/|\/)[^\s"'`,;:]+/

type CredentialRoute = {
  upstream: string
  credential_key: string
  inject_header: string
  env_var?: string
}

type Caps = {
  fs?: Array<{ path: string; resolved?: string; access: string }>
  net_blocked?: boolean
  allowed_domains?: string[]
  credentials?: Record<string, CredentialRoute>
  session_id?: string
}

function insideNono(): boolean {
  return Boolean(process.env.NONO_CAP_FILE)
}

function readCaps(): Caps | null {
  const capFile = process.env.NONO_CAP_FILE
  if (!capFile) return null
  try {
    return JSON.parse(fs.readFileSync(capFile, "utf8")) as Caps
  } catch {
    return null
  }
}

function extractPath(text: string): string | null {
  const match = PATH_RE.exec(text)
  if (!match) return null
  let candidate = match[0].replace(/[).\]]+$/, "")
  if (candidate.startsWith("~/")) {
    candidate = (process.env.HOME ?? "~") + "/" + candidate.slice(2)
  }
  return candidate || null
}

function nonoConfigHome(): string {
  return (process.env.XDG_CONFIG_HOME ?? `${process.env.HOME ?? "~"}/.config`) + "/nono"
}

function profileDraftsDir(): string {
  return nonoConfigHome() + "/profile-drafts"
}

function buildCredentialLines(caps: Caps): string {
  const routes = caps.credentials ?? {}
  const keys = Object.keys(routes)
  if (keys.length === 0) return "  (none enabled — add routes to network.credentials in your profile)"
  return keys
    .map(name => {
      const r = routes[name]
      const envVar = r.env_var ?? r.credential_key
      const present = Boolean(process.env[envVar])
      return `  ${name}: ${r.upstream}  [${present ? "key present" : "key missing — set " + envVar}]`
    })
    .join("\n")
}

function buildDomainLines(caps: Caps): string {
  const domains = caps.allowed_domains ?? []
  if (domains.length === 0) {
    return caps.net_blocked
      ? "  (all outbound network blocked)"
      : "  (no allowlist — all outbound network allowed)"
  }
  return domains.map(d => "  " + d).join("\n")
}

function buildEgressGuidance(caps: Caps): string {
  const domains = caps.allowed_domains ?? []
  if (caps.net_blocked) {
    return "All outbound network is blocked. Retries, alternate endpoints, or proxies cannot bypass this — do not attempt workarounds."
  }
  if (domains.length === 0) {
    return "No host allowlist is in effect; all outbound network is allowed."
  }
  return [
    "Network egress is default-deny; only these hosts are reachable. Any other outbound connection fails by design — retries, alternate endpoints, or proxies cannot bypass it, so do not attempt workarounds:",
    buildDomainLines(caps),
  ].join("\n")
}

function buildGuidance(caps: Caps, blockedPath: string | null): string {
  const pathLines =
    (caps.fs ?? [])
      .map(e => "  " + (e.resolved ?? e.path) + " (" + e.access + ")")
      .join("\n") || "  (none)"
  const net = caps.net_blocked ? "blocked" : "allowed"
  const display = blockedPath ?? "<blocked-path>"
  const whyCmd = blockedPath
    ? `nono why --path ${blockedPath} --op read`
    : "nono why --path <blocked-path> --op read"
  const allowCmd = blockedPath
    ? `nono run --allow ${blockedPath} -- opencode`
    : "nono run --allow <blocked-path> -- opencode"

  return [
    "",
    "---",
    "**[nono sandbox]** This is a sandbox permission denial — not a Unix or macOS permissions issue.",
    "Do NOT suggest sudo, chmod, or system permission changes.",
    "",
    "Blocked path: " + display,
    "",
    "Allowed paths in this session:",
    pathLines,
    "Network: " + net,
    "",
    "Reachable hosts (allowlist):",
    buildDomainLines(caps),
    "",
    "Active credential routes:",
    buildCredentialLines(caps),
    "",
    "Next steps (in order):",
    "1. Run `" + whyCmd + "` and include output verbatim.",
    "2. Present the user with exactly these two options:",
    "   Option A (quick fix):  " + allowCmd,
    "   Option B (persistent): draft a profile to " + profileDraftsDir() + "/<name>.json",
    "                          extending `opencode`, add the path under `\"allow\"` or `\"read\"`,",
    "                          then tell the user: run `nono profile promote <name>`",
    "                          and start future sessions with `nono run --profile <name> -- opencode`",
  ].join("\n")
}

function buildSystemContext(caps: Caps): string {
  const sessionId = caps.session_id ?? process.env.NONO_SESSION_ID
  const reattachNote = sessionId
    ? `\nSession ID: ${sessionId}. To reattach after detaching: nono attach ${sessionId}`
    : ""

  return `
You are running inside nono, an OS-level security sandbox. nono enforces filesystem and network limits via Landlock (Linux) or Seatbelt (macOS) before opencode starts.

sudo, chmod, chown, retries, or macOS Full Disk Access cannot grant access that nono has not allowed.${reattachNote}

If a tool or shell command fails with "Operation not permitted", "Permission denied", EACCES, EPERM, landlock, or sandbox denied:
1. Run: nono why --path <blocked-path> --op <read|write|readwrite>
2. Offer the user exactly two options:
   Option A: nono run --allow /path/to/needed -- opencode
   Option B: draft ${profileDraftsDir()}/<name>.json extending "opencode", then have the user run nono profile promote <name>

Credential injection is active for configured routes. Do not read or write API keys directly — nono injects them transparently via its proxy.

${buildEgressGuidance(caps)}

Do not edit ${nonoConfigHome()}/profiles or ${nonoConfigHome()}/packages from inside the sandbox.
`.trim()
}

function buildStatusReport(caps: Caps | null): string {
  if (!caps) return "Not running inside a nono session (NONO_CAP_FILE is not set)."

  const sessionId = caps.session_id ?? process.env.NONO_SESSION_ID
  const net = caps.net_blocked ? "blocked" : "allowed"
  const fsPaths = (caps.fs ?? [])
    .map(e => "  " + (e.resolved ?? e.path) + " (" + e.access + ")")
    .join("\n") || "  (none)"

  const lines = [
    "nono sandbox: active",
    sessionId ? "session: " + sessionId + "  (reattach: nono attach " + sessionId + ")" : "",
    "network: " + net,
    "reachable hosts:",
    buildDomainLines(caps),
    "filesystem:",
    fsPaths,
    "credential routes:",
    buildCredentialLines(caps),
  ]
  return lines.filter(Boolean).join("\n")
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function appendGuidance(result: any, guidance: string): unknown {
  if (!result || typeof result !== "object") return result
  const r = result as Record<string, unknown>
  if (typeof r.content === "string") {
    return { ...r, content: r.content + guidance }
  }
  if (Array.isArray(r.content)) {
    const parts = [...r.content]
    const lastText = parts
      .map(p => typeof (p as { text?: unknown }).text === "string")
      .lastIndexOf(true)
    if (lastText >= 0) {
      parts[lastText] = {
        ...(parts[lastText] as object),
        text: (parts[lastText] as { text: string }).text + guidance,
      }
    } else {
      parts.push({ type: "text", text: guidance })
    }
    return { ...r, content: parts }
  }
  return result
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const NonoSandboxPlugin = async (ctx: any) => {
  if (!insideNono()) return {}

  const caps = readCaps()

  // Register nono-status command if the context supports it
  if (ctx && typeof ctx.registerCommand === "function") {
    ctx.registerCommand("nono-status", {
      description: "Show nono sandbox status for this opencode session",
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      handler: async (_args: any) => buildStatusReport(readCaps()),
    })
  }

  return {
    // Inject nono context into the system prompt so the model knows the rules
    // before the first tool call. Fall back gracefully if opencode's plugin API
    // doesn't support this field yet.
    ...(caps ? { system: { inject: buildSystemContext(caps) } } : {}),

    tool: {
      execute: {
        description: "Internal middleware hook for the nono sandbox interception layer. Do not invoke directly.",
        // Fires after every tool call. When the result contains a denial
        // signature we append capability context and Option A/B remediation.
        after: async (input: unknown, result: unknown) => {
          if (!DENIAL_PATTERN.test(JSON.stringify(result))) return result

          const liveCaps = readCaps()
          if (!liveCaps) return result

          const inputText = JSON.stringify(input)
          const resultText = JSON.stringify(result)
          const blockedPath = extractPath(inputText) ?? extractPath(resultText)

          return appendGuidance(result, buildGuidance(liveCaps, blockedPath))
        },
      },
    },
  }
}
