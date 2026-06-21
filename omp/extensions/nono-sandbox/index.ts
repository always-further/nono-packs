import { existsSync, readFileSync } from "node:fs";
import type { ExtensionAPI, ToolResultEvent } from "@oh-my-pi/pi-coding-agent";

const DENIAL_PATTERNS = [
	/operation not permitted/i,
	/permission denied/i,
	/\bEACCES\b/i,
	/\bEPERM\b/i,
	/landlock/i,
	/sandbox(?:ed)?:?\s+deny/i,
	/sandbox denied/i,
];

const SYSTEM_CONTEXT = `
You are running inside nono, an outer OS-level sandbox. nono filesystem and network limits are enforced by the operating system before OMP starts. OMP approvals, retries, chmod, chown, sudo, or macOS Full Disk Access cannot grant access that nono has not allowed.

If a tool or shell command fails with Operation not permitted, Permission denied, EACCES, EPERM, landlock, sandbox deny, or sandbox denied, treat it as a nono sandbox boundary. Diagnose with:

    nono why --self --path <blocked-path> --op <read|write|readwrite>

Then present exactly two remediation options:

    Option A: restart with a one-off grant, for example:
    nono run --profile omp --allow /path/to/needed -- omp

    Option B: draft a persistent profile under ~/.config/nono/profile-drafts/<name>.json, ask the user to run nono profile promote <name>, then start future sessions with that profile.

Do not edit ~/.config/nono/profiles or registry-managed files under ~/.config/nono/packages from inside the sandbox.
`.trim();

const DENIAL_GUIDANCE = `

[nono sandbox diagnostic]
This looks like an outer nono sandbox denial, not a Unix permission problem.

Next step:
  nono why --self --path <blocked-path> --op <read|write|readwrite>

Offer the user:
  Option A: one-off restart with nono run --profile omp --allow /path/to/needed -- omp
  Option B: draft ~/.config/nono/profile-drafts/<name>.json and have the user run nono profile promote <name>

Do not suggest sudo, chmod, chown, Full Disk Access, or OMP approval changes for this denial.
`.trim();

function insideNono(): boolean {
	return Boolean(process.env.NONO_CAP_FILE);
}

function textFromEvent(event: ToolResultEvent): string {
	return event.content
		.filter((item) => item.type === "text")
		.map((item) => item.text)
		.join("\n");
}

function looksLikeDenial(event: ToolResultEvent): boolean {
	if (!event.isError) return false;
	const haystack = [event.toolName, textFromEvent(event), JSON.stringify(event.details ?? {})].join("\n");
	return DENIAL_PATTERNS.some((pattern) => pattern.test(haystack));
}

export default function (omp: ExtensionAPI) {
	omp.on("session_start", async (_event, ctx) => {
		if (!insideNono() || !ctx.hasUI) return;
	if (process.env.OMP_NONO_STATUS_INDICATOR === "false") return;
		ctx.ui.setStatus("nono", "nono sandbox");
	});

	omp.on("before_agent_start", async (event) => {
		if (!insideNono()) return undefined;
		return {
			systemPrompt: `${event.systemPrompt}\n\n${SYSTEM_CONTEXT}`,
		};
	});

	omp.on("tool_result", async (event, ctx) => {
		if (!insideNono() || !looksLikeDenial(event)) return undefined;

		if (ctx.hasUI) {
			ctx.ui.notify("nono sandbox denial detected", "warning");
		}

		return {
			content: [
				...event.content,
				{
					type: "text" as const,
					text: DENIAL_GUIDANCE,
				},
			],
			isError: true,
		};
	});

	omp.registerCommand("nono-status", {
		description: "Show nono sandbox status for this OMP session",
		handler: async (_args, ctx) => {
			const capFile = process.env.NONO_CAP_FILE;
			if (!capFile) {
				ctx.ui.notify("OMP is not running inside a nono session.", "info");
				return;
			}

			if (!existsSync(capFile)) {
				ctx.ui.notify(`nono capability file is not readable: ${capFile}`, "warning");
				return;
			}

			const summary = readFileSync(capFile, "utf8")
				.split("\n")
				.slice(0, 12)
				.join("\n")
				.trim();
			ctx.ui.notify(summary || `nono capability file is empty: ${capFile}`, "info");
		},
	});
}
