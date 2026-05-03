// nono-sandbox.ts — OpenCode plugin for nono sandbox diagnostics
// Version: 1.0.0
//
// When OpenCode runs inside `nono run --profile opencode -- opencode`, the OS
// (Landlock/Seatbelt) blocks unauthorised filesystem and network access at the
// kernel boundary. The model otherwise reads these denials as ordinary Unix
// permission errors and suggests chmod / sudo / "try a different path", none of
// which can succeed.
//
// This plugin watches `tool.execute.after`, detects sandbox-denial signatures
// in the tool result, and appends a structured diagnostic + remediation block
// to the result text so the model sees it on the next turn.
//
// The plugin no-ops outside a nono session (NONO_CAP_FILE unset).
//
// API caveat: OpenCode's plugin hook input/output shapes are not fully
// documented at the time of writing. The mutation below targets the most
// likely shape (`output.output` is the tool's result string) behind a defensive
// cast. Revisit once the hook contract is published.

import type { Plugin } from "@opencode-ai/plugin"
import * as fs from "node:fs"

const DENIAL_RE =
  /operation not permitted|permission denied|EPERM|EACCES|sandbox.*denied|landlock/i

const PATH_RE = /(~\/|\/)[^\s"',]+/

type Capability = { path?: string; resolved?: string; access?: string }
type CapFile = { fs?: Capability[]; net_blocked?: boolean }

function readCapFile(capFile: string): { caps: string; net: string } {
  try {
    const data = JSON.parse(fs.readFileSync(capFile, "utf8")) as CapFile
    const caps = (data.fs ?? [])
      .map((c) => `  ${c.resolved ?? c.path} (${c.access})`)
      .join("\n")
    const net = data.net_blocked ? "blocked" : "allowed"
    return { caps, net }
  } catch {
    return { caps: "  (unreadable)", net: "unknown" }
  }
}

function extractFailedPath(result: string, args: unknown): string {
  const argsStr = typeof args === "string" ? args : JSON.stringify(args ?? "")
  const fromArgs = argsStr.match(PATH_RE)?.[0]
  const fromResult = result.match(PATH_RE)?.[0]
  let p = fromArgs ?? fromResult ?? "<blocked-path>"
  if (p.startsWith("~/")) p = `${process.env.HOME}/${p.slice(2)}`
  else if (p === "~") p = process.env.HOME ?? p
  return p
}

function buildDiagnostic(failedPath: string, capFile: string): string {
  const { caps, net } = readCapFile(capFile)
  return `

[NONO SANDBOX - PERMISSION DENIED]

This is a nono sandbox denial, not macOS TCC or a Unix permissions issue.
Path blocked: ${failedPath}

Allowed paths:
${caps}
Network: ${net}

DO NOT retry the same operation, suggest chmod/sudo, or try alternative paths
— the boundary is OS-enforced and cannot be bypassed from inside the session.

Take these steps in order:

1. Run \`nono why --path ${failedPath} --op read\` and include the output
   verbatim in your reply so the user sees the precise diagnosis.

2. Then offer the user TWO choices and wait for their answer:

   A) one-off — exit and restart with this path allowed:
        nono run --allow ${failedPath} -- opencode

   B) persistent — write a profile at
      ~/.config/nono/profiles/<chosen-name>.json with:
        {
          "extends": "opencode",
          "meta": { "name": "<chosen-name>", "version": "1.0.0" },
          "filesystem": { "read": ["${failedPath}"] }
        }
      Then restart with: nono run --profile <chosen-name> -- opencode

Stop after either option. The user must restart for the new permissions to
take effect.`
}

export const NonoSandboxPlugin: Plugin = async () => {
  const capFile = process.env.NONO_CAP_FILE
  if (!capFile || !fs.existsSync(capFile)) return {}

  return {
    "tool.execute.after": async (input, output) => {
      const out = output as { output?: string; args?: unknown }
      const result = String(out.output ?? "")
      if (!DENIAL_RE.test(result)) return
      const failedPath = extractFailedPath(result, out.args)
      out.output = result + buildDiagnostic(failedPath, capFile)
    },
  }
}

export default NonoSandboxPlugin
