// Extensión de compatibilidad pi para el plugin b-pipeline (Claude Code).
//
// Equivale funcionalmente a hooks/hooks.json de Claude Code, reutilizando los
// MISMOS scripts bash (un solo lugar que mantener):
//
//   Claude Code                          pi
//   ------------------------------       ------------------------------------
//   SessionStart write-root-marker.sh -> exporta CLAUDE_PLUGIN_ROOT en el
//                                        proceso + escribe ~/.claude/b-pipeline.root
//   PreToolUse(Bash)  block-*.sh     -> pi.on("tool_call", toolName "bash")
//   PreToolUse(Read)  block-env-dump -> pi.on("tool_call", toolName "read")
//   PostToolUse(Bash) link-worktree  -> pi.on("tool_execution_end", "bash", no-fatal)
//
// Los scripts de hooks/ leen JSON por stdin con la forma { tool_input, cwd }
// (el payload de Claude Code) — se les alimenta exactamente ese payload desde
// los eventos de pi. Semántica de salida igual: exit 2 = bloquear; cualquier
// otro error = no bloquear (fail-open, como el harness de Claude Code).

import { spawn } from "node:child_process";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const extensionDir = dirname(fileURLToPath(import.meta.url)); // <root>/pi/
const pluginRoot = dirname(extensionDir);

function findPluginRoot(): string | null {
  if (existsSync(join(pluginRoot, "skills")) && existsSync(join(pluginRoot, "hooks"))) {
    return pluginRoot;
  }
  return null;
}

// Wrapper único: los hooks de Claude Code leen su payload por stdin, así que
// hay que alimentar el stdin del proceso hijo (spawn, no execFile). Semántica:
// exit 2 = bloquear; cualquier otra salida o error = fail-open.
function runHook(
  root: string,
  script: string,
  payload: unknown,
): Promise<{ blocked: boolean; reason?: string }> {
  return new Promise((resolve) => {
    const child = spawn("bash", [join(root, "hooks", script)], {
      cwd: root,
      env: process.env,
      stdio: ["pipe", "ignore", "pipe"],
    });
    let stderr = "";
    let settled = false;
    const done = (blocked: boolean, reason?: string) => {
      if (!settled) {
        settled = true;
        resolve({ blocked, reason });
      }
    };
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      done(false);
    }, 15_000);
    child.stderr?.on("data", (chunk: Buffer) => {
      stderr += chunk.toString();
    });
    child.on("error", () => {
      clearTimeout(timer);
      done(false);
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      if (code === 2) done(true, stderr.trim() || `Blocked by ${script}`);
      else done(false);
    });
    child.stdin?.end(JSON.stringify(payload));
  });
}

export default function bPipelineCompat(pi: ExtensionAPI) {
  const root = findPluginRoot();
  if (!root) return;

  // --- Equivalente de SessionStart write-root-marker.sh -----------------------
  // CLAUDE_PLUGIN_ROOT en el entorno del proceso: los snippets bash de los
  // SKILL.md y todos los scripts del plugin lo leen igual que en Claude Code.
  pi.on("session_start", async () => {
    process.env.CLAUDE_PLUGIN_ROOT = root;
    try {
      const markerDir = join(homedir(), ".claude");
      mkdirSync(markerDir, { recursive: true });
      writeFileSync(join(markerDir, "b-pipeline.root"), `${root}\n`);
    } catch {
      // No-fatal: el fallback de los scripts (glob del marketplace) sigue vivo.
    }
  });

  // --- Equivalente de PreToolUse (Bash y Read) --------------------------------
  pi.on("tool_call", async (event) => {
    if (event.toolName === "bash") {
      const cmd = (event.input as { command?: unknown } | undefined)?.command;
      if (typeof cmd !== "string" || cmd.length === 0) return;
      const payload = { tool_input: { command: cmd }, cwd: process.cwd() };
      const worktreeGate = await runHook(root, "block-git-worktree-add.sh", payload);
      if (worktreeGate.blocked) return { block: true, reason: worktreeGate.reason };
      const envGate = await runHook(root, "block-env-dump.sh", payload);
      if (envGate.blocked) return { block: true, reason: envGate.reason };
      return;
    }
    if (event.toolName === "read") {
      const filePath = (event.input as { path?: unknown } | undefined)?.path;
      if (typeof filePath !== "string" || filePath.length === 0) return;
      const envGate = await runHook(root, "block-env-dump.sh", {
        tool_input: { file_path: filePath },
        cwd: process.cwd(),
      });
      if (envGate.blocked) return { block: true, reason: envGate.reason };
    }
  });

  // --- Equivalente de PostToolUse(Bash) link-worktree-env.sh ------------------
  // No-fatal e idempotente: el propio script decide si aplica.
  pi.on("tool_execution_end", async (event) => {
    if (event.toolName !== "bash") return;
    const cmd = (event.args as { command?: unknown } | undefined)?.command;
    if (typeof cmd !== "string" || !cmd.includes("setup-worktree.sh")) return;
    try {
      await runHook(root, "link-worktree-env.sh", {
        tool_input: { command: cmd },
        cwd: process.cwd(),
      });
    } catch {
      // No-fatal por diseño (espejo del hook PostToolUse).
    }
  });
}
