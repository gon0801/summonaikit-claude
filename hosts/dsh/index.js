// hosts/dsh/index.js — @summonaikit/dsh-gate. Solo traduce (D1) y falla abierto (D3).
import z from "@deepseek-ai/schemastery";
import { runHook } from "./spawn-hook.js";
import { toSessionStart, toUserPromptSubmit, toPostToolUse, toStop } from "./translate.js";

export const name = "summonaikit-gate";
export const Config = z.object({
  hook: z.string().required(),      // ruta del summonaikit-harness.sh instalado
  bash: z.string().required(),      // ruta ABSOLUTA del bash de Git for Windows — la escribe el instalador (bots #83: `bash` pelado puede resolver a WSL)
  timeoutMs: z.number().default(20000),
});

// Una clave por sesion para TODO: cola, texto del asistente, cwd. 15.1 midio que
// `agent.id` == `session.id` (la misma cadena), asi que una sola clave sirve.
export function sessionKey(agentOrSession) { return agentOrSession?.id ?? String(agentOrSession); }

export function apply(ctx, config) {
  const warn = (...a) => (ctx.logger?.warn ?? console.warn)("[summonaikit-gate]", ...a);
  const lastText = new Map();   // sessionKey -> ultimo texto del asistente (assistant/message, 15.1)
  const cwdOf = new Map();      // sessionKey -> cwd (agent/created meta.cwd, 15.1)
  const queues = new Map();     // sessionKey -> promesa encadenada (bots #83: el Stop espera a los PostToolUse)
  const ctxOf = (agent) => ({ sessionId: sessionKey(agent), cwd: cwdOf.get(sessionKey(agent)) ?? process.cwd() });
  const call = async (payload) => {
    if (!payload) return undefined;
    const r = await runHook({ hook: config.hook, payload, timeoutMs: config.timeoutMs, bash: config.bash });
    if (!r.ok || r.error) warn(r.error, r.stderr ?? "");
    return r.json;
  };
  // Cola por sesion: cada llamada al hook corre despues de la anterior de la
  // misma sesion, en el orden en que dsh emitio los eventos. Un error no corta
  // la cadena (fail-open).
  const enqueue = (key, payload) => {
    const prev = queues.get(key) ?? Promise.resolve();
    const nextP = prev.then(() => call(payload)).catch((e) => { warn(e); return undefined; });
    queues.set(key, nextP);
    return nextP;
  };

  ctx.on("agent/created", ({ agent }) => {
    // dsh no pone meta.cwd en agent/created (codex r1 PR #86): el cwd vive en
    // session.header.cwd. Fallback: process.cwd() (lo del proceso del adaptador).
    const cwd = agent?.session?.header?.cwd;
    if (typeof cwd === "string" && cwd !== "") cwdOf.set(sessionKey(agent), cwd);
  });
  ctx.on("agent/disposed", ({ agent }) => {
    // Limpieza de estado por sesion (codex r1 PR #86 / Greptile): un proceso dsh
    // de larga vida no debe acumular lastText/cwdOf/queues por sesion historica.
    const key = sessionKey(agent);
    lastText.delete(key); cwdOf.delete(key); queues.delete(key);
  });
  ctx.on("agent/session-start", ({ agent }) => { enqueue(sessionKey(agent), toSessionStart(ctxOf(agent))); });
  ctx.on("session/event", (session, event) => {
    if (event?.type === "assistant/message") lastText.set(sessionKey(session), textOf(event));
  });
  ctx.on("agent/pre-step", async (payload, next) => {
    const decision = await next();
    if (decision.kind !== "enter") return decision;
    const json = await enqueue(sessionKey(payload.agent), toUserPromptSubmit({ ...ctxOf(payload.agent), step: payload.step, messages: payload.messages }));
    const extra = json?.hookSpecificOutput?.additionalContext;
    if (!extra) return decision;
    const msg = { id: crypto.randomUUID(), role: "user", source: { kind: "plugin", plugin: "summonaikit-gate" }, content: [{ type: "text", text: extra }] };
    return { kind: "enter", messages: [...decision.messages, msg] };
  });
  ctx.on("tools/result", (exec) => {
    if (!exec.agent) return;
    enqueue(sessionKey(exec.agent), toPostToolUse({ ...ctxOf(exec.agent), name: exec.name, arguments: exec.arguments }));
  });
  ctx.on("agent/turn-stopping", async ({ agent }) => {
    const key = sessionKey(agent);
    // El Stop entra a la MISMA cola: corre solo cuando drenaron los PostToolUse.
    const json = await enqueue(key, toStop({ ...ctxOf(agent), lastAssistantText: lastText.get(key) ?? "" }));
    if (json?.decision === "block" && json.reason) agent.followup({ role: "user", source: { kind: "plugin", plugin: "summonaikit-gate" }, content: [{ type: "text", text: json.reason }] });
  });
}
function textOf(event) {
  // 15.1: el texto del asistente vive en event.data.message.content[].text (no en
  // event.message). Solo los bloques `type:"text"` cuentan (codex r1 PR #86): un
  // recibo presente solo en `reasoning` (oculto) no debe pasar el gate por
  // delante del texto visible. Se conserva el fallback del plan por robustez.
  const c = event?.data?.message?.content ?? event?.message?.content ?? event?.content ?? [];
  const blocks = Array.isArray(c) ? c : [c];
  return blocks.filter((x) => x?.type === "text" || typeof x === "string")
    .map((x) => (typeof x === "string" ? x : x?.text ?? "")).join("\n");
}
