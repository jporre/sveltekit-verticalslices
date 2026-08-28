/**
 * b-pipeline — port de los hooks de Claude Code a una extensión de pi.
 *
 * El plugin b-pipeline incluye hooks que Claude Code ejecuta desde hooks.json.
 * En pi no hay hooks: los equivalentes se implementan como eventos de extensión:
 *
 *   Claude Code                          pi
 *   ────────────────────────────        ──────────────────────────────
 *   SessionStart                        session_start
 *     write-root-marker.sh                persiste la raíz del plugin en
 *                                         ~/.claude/b-pipeline.root (los
 *                                         snippets de los SKILL.md resuelven
 *                                         PLUGIN_ROOT desde ese archivo).
 *   PreToolUse (Bash)                   tool_call (toolName === "bash")
 *     block-git-worktree-add.sh           bloquea `git worktree add` directo
 *     block-env-dump.sh                   bloquea dumps de .env*
 *   PreToolUse (Read)                   tool_call (toolName === "read")
 *     block-env-dump.sh                   bloquea Read de .env*
 *   PostToolUse (Bash)                  tool_execution_end (bash + flag)
 *     link-worktree-env.sh                symlink .env* hacia el worktree
 *
 * Reutiliza los scripts bash originales tal cual (hooks/*.sh): reciben el
 * JSON de hook de Claude por stdin y bloquean con exit 2. Esta extensión
 * arma ese JSON (tool_name + tool_input) y mapea exit 2 -> { block: true }.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = dirname(HERE);

function hookEnv(): NodeJS.ProcessEnv {
	return { ...process.env, CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT };
}

/** Ejecuta un hook script con payload estilo Claude Code por stdin. exit 2 => bloquea. */
function runHook(script: string, payload: unknown): { blocked: boolean; reason: string } {
	try {
		const r = spawnSync(script, [], {
			input: JSON.stringify(payload),
			encoding: "utf8",
			env: hookEnv(),
		});
		if (r.status === 2) {
			return {
				blocked: true,
				reason: (r.stderr || "Blocked by b-pipeline hook").trim(),
			};
		}
	} catch {
		// No bloquear por fallas del hook en sí: fail-open como en los no-bloqueantes.
	}
	return { blocked: false, reason: "" };
}

let pendingWorktreeSetup = false;

export default function activate(pi: ExtensionAPI) {
	// SessionStart -> write-root-marker.sh (rescritura directa del marker, mismo archivo).
	pi.on("session_start", async () => {
		try {
			if (!existsSync(join(PLUGIN_ROOT, "skills"))) return; // sanity del script original
			const dir = join(homedir(), ".claude");
			mkdirSync(dir, { recursive: true });
			writeFileSync(join(dir, "b-pipeline.root"), PLUGIN_ROOT + "\n");
		} catch {
			// Silencioso a propósito.
		}
	});

	// PreToolUse (Bash + Read) -> tool_call con { block: true, reason }.
	pi.on("tool_call", async (event) => {
		const toolName = String(event.toolName ?? "").toLowerCase();

		if (toolName === "bash") {
			const command = String((event.input as { command?: unknown } | undefined)?.command ?? "");
			const payload = { tool_name: "Bash", tool_input: { command } };

			const wt = runHook(join(HERE, "..", "hooks", "block-git-worktree-add.sh"), payload);
			if (wt.blocked) return { block: true, reason: wt.reason };

			const env = runHook(join(HERE, "..", "hooks", "block-env-dump.sh"), payload);
			if (env.blocked) return { block: true, reason: env.reason };

			// PostToolUse: link-worktree-env.sh corre tras setup-worktree.sh.
			if (/setup-worktree\.sh/.test(command)) {
				pendingWorktreeSetup = true;
			}
			return;
		}

		if (toolName === "read") {
			const input = event.input as { file_path?: unknown; path?: unknown } | undefined;
			const file_path = String(input?.file_path ?? input?.path ?? "");
			if (!file_path) return;
			const env = runHook(join(HERE, "..", "hooks", "block-env-dump.sh"), {
				tool_name: "Read",
				tool_input: { file_path },
			});
			if (env.blocked) return { block: true, reason: env.reason };
		}
	});

	// PostToolUse (Bash) -> tool_execution_end. El hook es NO-FATAL (siempre exit 0).
	pi.on("tool_execution_end", async (event) => {
		if (!pendingWorktreeSetup) return;
		if (String(event.toolName ?? "").toLowerCase() !== "bash") return;
		pendingWorktreeSetup = false;
		try {
			spawnSync(join(PLUGIN_ROOT, "hooks", "link-worktree-env.sh"), {
				encoding: "utf8",
				env: hookEnv(),
			});
		} catch {
			// Non-fatal a propósito.
		}
	});
}
