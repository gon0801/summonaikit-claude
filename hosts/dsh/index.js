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
  const cwdOf = new Map();      // sessionKey -> cwd (agent/session header, 15.1)
  const cwdWarned = new Set();  // sessionKey -> ya se aviso del fallback a process.cwd()
  const queues = new Map();     // sessionKey -> promesa encadenada (bots #83: el Stop espera a los PostToolUse)
  // Gap1 claude (r3 PR #86): los subagentes corren en su PROPIA sesion, asi que
  // sus tools/result llegan con agent = id de la sesion del HIJO y el gate (que
  // corre sobre la sesion de la madre) no los ve. Mapeamos sesion-hijo ->
  // {parent, role} para re-acreditar los eventos del hijo a la madre. caretaker:
  // { parent: sessionKey de la madre, role: rol inferido del spawn }.
  const childOf = new Map();    // sessionKey de la sesion del hijo -> { parent, role }
  // Gap2 claude (r3 PR #86): mientras un hijo sigue vivo (kind:"continuable"),
  // un agent/turn-stopping INTERMEDIO del padre NO debe traducirse a Stop (quema
  // el gate con la ceremonia a medias y el turno final pasa sin gate). liveKids
  // mapea sessionKey del padre -> contador de hijos vivos que aun no cerraron.
  const liveKids = new Map();   // sessionKey del padre -> numero de hijos vivos
  const ctxOf = (agent) => {
    const key = sessionKey(agent);
    const cwd = cwdOf.get(key);
    if (!cwd && !cwdWarned.has(key)) { cwdWarned.add(key); warn(`sin agent.session.header.cwd para ${key}; cae a process.cwd() (a confirmar en 15.5)`); }
    return { sessionId: key, cwd: cwd ?? process.cwd() };
  };
  const call = async (payload) => {
    if (!payload) return undefined;
    // runHook arranca el hook con `cwd` = cwd de la sesion (payload.cwd), porque el
    // hook resuelve el proyecto por `pwd`+`git rev-parse` (qwen r2 PR #86: sin esto
    // correria en el cwd del SERVIDOR de dsh, gateando el repo equivocado).
    const r = await runHook({ hook: config.hook, payload, timeoutMs: config.timeoutMs, bash: config.bash, cwd: typeof payload.cwd === "string" && payload.cwd ? payload.cwd : undefined });
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
    lastText.delete(key); cwdOf.delete(key); queues.delete(key); cwdWarned.delete(key);
    // Gap1: si es un hijo, lo des-registramos de la madre; si es madre, cae todo
    // su arbol de hijos. Gap2: cerrar al ultimo hijo libera el Stop del padre.
    const link = childOf.get(key);
    if (link) {
      childOf.delete(key);
      const n = (liveKids.get(link.parent) ?? 1) - 1;
      if (n <= 0) liveKids.delete(link.parent); else liveKids.set(link.parent, n);
    }
    childOf.delete(key);
    liveKids.delete(key);
  });
  ctx.on("agent/session-start", ({ agent }) => { enqueue(sessionKey(agent), toSessionStart(ctxOf(agent))); });
  ctx.on("session/event", (session, event) => {
    if (event?.type === "assistant/message") lastText.set(sessionKey(session), textOf(event));
  });
  ctx.on("agent/pre-step", async (payload, next) => {
    const decision = await next();
    if (decision?.kind !== "enter") return decision;
    const json = await enqueue(sessionKey(payload.agent), toUserPromptSubmit({ ...ctxOf(payload.agent), step: payload.step, messages: payload.messages }));
    const extra = json?.hookSpecificOutput?.additionalContext;
    if (!extra) return decision;
    const msg = { id: crypto.randomUUID(), role: "user", source: { kind: "plugin", plugin: "summonaikit-gate" }, content: [{ type: "text", text: extra }] };
    return { kind: "enter", messages: [...(decision.messages ?? []), msg] };
  });
  ctx.on("tools/result", (exec, result) => {
    if (!exec.agent) return;
    if (result?.isError) return; // claude r3 PR #86: un subagente/herramienta que falla no debe sumarse a agents_seen
    let agentKey = sessionKey(exec.agent);
    let role = undefined;
    // Gap1: si el tool/result viene de un HIJO (sesion que no es la madre), lo
    // traducimos con la sesion de la MADRE y el rol del spawn para que el gate vea
    // el edit/run del implementer/verifier/adversary. Si es el EVENTO DE SPAWN
    // (name subagent + subagentId), registramos al hijo ANTES de procesarlo.
    const link = childOf.get(agentKey);
    if (link) { agentKey = link.parent; role = link.role; }
    const translated = toPostToolUse({ ...ctxOf({ id: agentKey }), name: exec.name, arguments: exec.arguments, result });
    if (!translated) return;
    if (translated.subagentId) {
      // Evento de spawn: el hijo corre en su propia sesion (subagentId). Lo
      // registramos bajo la sesion del PADRE (exec.agent) con el rol del spawn.
      const parentKey = sessionKey(exec.agent);
      childOf.set(translated.subagentId, { parent: parentKey, role: translated.tool_input?.subagent_type });
      liveKids.set(parentKey, (liveKids.get(parentKey) ?? 0) + 1);
    } else if (role) {
      // Evento de un hijo re-acreditado a la madre: el hook lee el rol por
      // top-level `agent_type` (fallback A9), asi que lo inyectamos para que el
      // gate atribuya el edit/run al rol correcto sobre la sesion de la madre.
      translated.agent_type = role;
    }
    enqueue(agentKey, translated);
  });
  ctx.on("agent/turn-stopping", async ({ agent }) => {
    const key = sessionKey(agent);
    // Gap2 (claude r3 PR #86): mientras haya hijos vivos (background continuable)
    // este turn-stopping es INTERMEDIO (el turno se corta para que corra el hijo),
    // no el cierre real. Traducirlo a Stop quemaria el gate con la ceremonia a
    // medias y dejaría pasar el turno final sin gate. Se difiere el Stop hasta que
    // el ultimo hijo se dispone (agent/disposed) y el padre vuelve a cerrar.
    if ((liveKids.get(key) ?? 0) > 0) return;
    // El Stop entra a la MISMA cola: corre solo cuando drenaron los PostToolUse.
    const json = await enqueue(key, toStop({ ...ctxOf(agent), lastAssistantText: lastText.get(key) ?? "" }));
    if (json?.decision === "block" && json.reason) {
      try { agent.followup({ id: crypto.randomUUID(), role: "user", source: { kind: "plugin", plugin: "summonaikit-gate" }, content: [{ type: "text", text: json.reason }] }); }
      catch (e) { warn(e); }  // fail-open: un followup que rechaza no debe tumbar el turno
    }
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
