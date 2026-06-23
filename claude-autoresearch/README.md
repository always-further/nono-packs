# claude-autoresearch

nono profile and Claude Code plugin for running [autoresearch](https://github.com/karpathy/autoresearch) autonomous ML loops inside a kernel-level security sandbox.

autoresearch gives Claude autonomous write access to a training codebase and spawns GPU training subprocesses overnight. This pack enforces filesystem and network restrictions at the kernel level via Linux Landlock — restrictions that cascade to all child processes and cannot be bypassed.

## What it provides

- **`claude-code-autoresearch` profile** — GPU-enabled nono profile for A100/CUDA workloads (IBD, TCGA, climbmix corpora)
- **Claude Code plugin** — sandbox-aware diagnostics for permission failures during ML training
- **Skill** — guides Claude through autoresearch setup, attestation, and experiment workflow

## Install

```bash
# The claude pack provides the base profile this pack extends
nono pull nolabs-ai/claude
nono pull Kexin-xu-01/claude-autoresearch
```

This installs the `claude-code-autoresearch` profile and wires the plugin into Claude Code.

## Usage

See [autoresearch-nono](https://github.com/nolabs-ai/autoresearch-nono) for the full setup guide including attestation, data preparation, and launching.


## What nono adds

| Without nono | With nono |
|---|---|
| Agent can read `~/.aws`, `~/.ssh` | Blocked at kernel level |
| Agent can write to any file | Write access limited to repo + cache dirs |
| Training subprocess has full network access | Network restricted to LLM API + HuggingFace |
| No record of what the agent actually accessed | Structured audit log of every syscall |
| `program.md` instructions can be silently modified | Tamper detection via Sigstore attestation |

## Platform

Linux only (requires kernel ≥ 5.13 for Landlock support).
