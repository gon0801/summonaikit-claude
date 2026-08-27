// hosts/dsh/spy/index.js — ESPÍA de medición (15.1). No es el adaptador.
import { appendFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import z from "@deepseek-ai/schemastery";

export const name = "summonaikit-spy";
export const Config = z.object({ out: z.string().required() });

// Redacción ANTES de escribir (bots PR #83): los mismos patrones que el hook y
// el perfil adversary — valores de token/password/secret/api_key (con o sin
// comillas), claves `sk-…`, y credenciales en URIs. La revisión manual del
// paso 5 es la SEGUNDA capa, no la única.
const SECRET_RES = [
  /((?:token|password|passwd|secret|api[_-]?key|authorization|bearer)\s*[=:]\s*["']?)[^\s"',;)]+/gi,
  /\bsk-[A-Za-z0-9_-]{8,}/g,
  /(:\/\/)[^\s\/@:]+:[^\s\/@]+@/g,
];
export function redact(text) {
  let t = text;
  t = t.replace(SECRET_RES[0], "$1[REDACTED]");
  t = t.replace(SECRET_RES[1], "sk-[REDACTED]");
  t = t.replace(SECRET_RES[2], "$1[REDACTED]@");
  return t;
}

// Claves sensibles: si el NOMBRE de la propiedad es sensible, se redacta el valor
// aunque el valor no matchee un patron (p. ej. {"token":"cleartext"} o
// {"authorization":"Bearer opaque-secret"}). Capa ADICIONAL a `redact`.
const SENSITIVE_KEY = /^(?:token|password|passwd|secret|authorization|bearer|api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|auth)$/i;

function dump(out, event, payload) {
  // Fail-open: la medicion nunca debe romper dsh. Cualquier error (serializacion,
  // BigInt, fs) se traga y se pierde solo esa linea.
  try {
    const seen = new WeakSet();
    const json = JSON.stringify({ ts: new Date().toISOString(), event, payload }, (k, v) => {
      if (typeof v === "bigint") return String(v);
      if (typeof v === "function") return "[fn]";
      if (v instanceof AbortSignal) return "[signal]";
      if (SENSITIVE_KEY.test(k)) return "[REDACTED]";
      if (typeof v === "string") return redact(v);
      if (v && typeof v === "object") {
        if (seen.has(v)) return "[cycle]";
        seen.add(v);
        if (typeof v.id === "string" && typeof v.session !== "undefined") return { agentId: v.id, sessionId: v.session?.id ?? "[unknown]", status: v.status };
      }
      return v;
    });
    mkdirSync(dirname(out), { recursive: true });
    appendFileSync(out, json + "\n");
  } catch {
    // fail-open: el plugin de medicion no debe abortar el turno de dsh.
  }
}

export function apply(ctx, config) {
  const out = config.out;
  ctx.on("agent/session-start", (payload) => dump(out, "agent/session-start", payload));
  ctx.on("agent/created", (payload) => dump(out, "agent/created", payload));
  ctx.on("agent/pre-step", async (payload, next) => {
    dump(out, "agent/pre-step", { step: payload.step, messages: payload.messages });
    const decision = await next();
    dump(out, "agent/pre-step:decision", decision);
    return decision;
  });
  ctx.on("tools/pre-execute", (exec, ...rest) => { dump(out, "tools/pre-execute", { name: exec.name, arguments: exec.arguments, agent: exec.agent?.id, parent: exec.parent }); return rest.at(-1)?.(); });
  ctx.on("tools/result", (exec, result) => dump(out, "tools/result", { name: exec.name, arguments: exec.arguments, agent: exec.agent?.id, parent: exec.parent, isError: result?.isError, result }));
  ctx.on("agent/turn-stopping", (payload) => dump(out, "agent/turn-stopping", { agent: payload.agent?.id, turn: payload.turn }));
  ctx.on("session/event", (session, event) => dump(out, "session/event", { session: session?.id ?? session, type: event?.type, event }));
}
