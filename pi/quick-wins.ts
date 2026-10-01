/**
 * quick-wins — modo de trabajo: el usuario dicta el cambio concreto y el agente
 * lo ejecuta. Nada más.
 *
 * Uso:
 *   /quickwins        alterna el modo (on/off)
 *   /quickwins on     activa
 *   /quickwins off    desactiva
 *   /qw               alias de /quickwins
 *
 * El estado vive por sesión (entrada custom en el .jsonl), así que sobrevive a
 * /reload y /resume dentro de la misma sesión. Mientras está activo, el modo
 * inyecta una sección al system prompt en cada turno.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const ENTRY_TYPE = "quick-wins-state";

const PROMPT_QUICK_WINS = `
<modo-quick-wins>
MODO QUICK-WINS ACTIVO. El usuario dicta el cambio concreto y tú lo ejecutas. Nada más.
- No preguntes, no propongas alternativas, no amplíes el alcance: el pedido es completo y cerrado.
- Cambios mínimos que resuelven exactamente lo pedido: cero refactors de paso, cero "de mientras", cero mejoras no pedidas.
- Cierra el ciclo: ejecuta, corre los tests de lo tocado (no la suite completa) y reporta breve qué cambió y el resultado.
- Pregunta solo si el pedido es tan ambiguo que no se puede ejecutar; en ese caso, una pregunta puntual y concreta.
</modo-quick-wins>
`.trim();

type Estado = { active: boolean };

function indicador(ctx: ExtensionContext, activo: boolean): void {
  if (ctx.hasUI) ctx.ui.setStatus("quick-wins", activo ? "⚡ quick-wins" : undefined);
}

function estadoDesdeEntradas(ctx: ExtensionContext): boolean {
  let activo = false;
  for (const entry of ctx.sessionManager.getEntries()) {
    if (entry.type === "custom" && entry.customType === ENTRY_TYPE) {
      activo = Boolean((entry.data as Estado | undefined)?.active);
    }
  }
  return activo;
}

export default function (pi: ExtensionAPI) {
  let activo = false;

  const registrarComando = (nombre: string): void => {
    pi.registerCommand(nombre, {
      description: "Modo quick-wins: el usuario dicta, tú ejecutas (on/off o alterna)",
      getArgumentCompletions: (prefix) => {
        const opciones = ["on", "off"].filter((o) => o.startsWith(prefix));
        return opciones.length > 0 ? opciones.map((o) => ({ value: o, label: o })) : null;
      },
      handler: async (args, ctx) => {
        const pedido = args.trim().toLowerCase();
        const nuevo = pedido === "on" ? true : pedido === "off" ? false : !activo;
        activo = nuevo;
        pi.appendEntry(ENTRY_TYPE, { active: activo } satisfies Estado);
        indicador(ctx, activo);
        pi.sendMessage(
          {
            customType: "quick-wins-notice",
            content: nuevo
              ? "Modo quick-wins ACTIVADO: desde ahora ejecuta solo el cambio que dicte el usuario, nada más."
              : "Modo quick-wins DESACTIVADO.",
            display: true,
          },
          { deliverAs: "nextTurn" },
        );
        ctx.ui.notify(
          nuevo ? "⚡ Modo quick-wins ACTIVADO" : "Modo quick-wins desactivado",
          "info",
        );
      },
    });
  };

  registrarComando("quickwins");
  registrarComando("qw");

  pi.on("session_start", async (_event, ctx) => {
    activo = estadoDesdeEntradas(ctx);
    indicador(ctx, activo);
    if (activo && ctx.hasUI) {
      ctx.ui.notify("⚡ Modo quick-wins activo en esta sesión", "info");
    }
  });

  pi.on("before_agent_start", async (event, _ctx) => {
    if (!activo) return;
    return { systemPrompt: `${event.systemPrompt}\n\n${PROMPT_QUICK_WINS}` };
  });
}
