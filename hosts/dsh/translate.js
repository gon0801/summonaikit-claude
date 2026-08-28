// hosts/dsh/translate.js — evento dsh -> payload del hook. Puro (sin dsh, sin fs). Phase 15 §3.
//
// Adaptado a la medicion de la Task 15.1 (docs/task-15.1-medicion-dsh.md):
// - la tool model-facing de delegacion se llama `subagent` y sus `arguments` son
//   `{ description, prompt }` — SIN `subagent_type` ni `persona`. El rol
//   (implementer/verifier/reviewer/adversary) solo esta en el TEXTO, asi que se
//   infiere (heuristica documentada en el README). El design D4 preveia un campo;
//   15.1 midio que no lo hay.
// - el texto del usuario en `pre-step` vive en `messages[].content[].text`.
// - el texto final del asistente vive en `session/event type:"assistant/message"`
//   en `event.data.message.content[].text` (ver `textOf` en index.js).
const ROLES = new Set(["implementer", "verifier", "reviewer", "adversary"]);
// Tools de fs observadas en 15.1: `edit` (file_path), `read` (file_path). `write`
// y `str_replace_editor` NO aparecieron en el turno capturado; se conservan por
// robustez/futuro. `read` no se mapea (es una lectura; el gate rastrea escrituras).
const FS_TOOLS = { write: "Write", str_replace_editor: "Edit", edit: "Edit", str_replace: "Edit" };
// Shell de dsh (claude r3 PR #86): 15.1 midio `pwsh` con `arguments.command`. El
// raíl de verificacion del hook acredita `verified` sobre un evento con
// tool_name:"Bash" + comando de runner; sin esto, en dsh `verified` jamas se
// acredita por evento y el Stop depende solo del fallback de prosa. Extension por
// medicion (la tabla §3 del diseño solo lista fs + subagent).
const SHELL_TOOLS = { pwsh: "Bash", powershell: "Bash" };
const SUBAGENT_TOOL_RE = /^subagent(?:[_-](implementer|verifier|reviewer|adversary))?$/;
// Heuristica de rol por texto (15.1: el rol solo esta ahi). Fail-safe (codex r1):
// SOLO se devuelve un rol si matchea EXACTAMENTE una regla; cero o multiples
// (ambiguo) -> undefined. Vocabulario alineado con el `canonical_agent_role` del
// hook (claude r3: verifier/implementer/reviewer mas amplios) para no perder un
// rol real por falta de stem.
const ROLE_INFER = [
  ["adversary", /\badversar|attack|\bred[\s_-]?team|\bhack/i],
  ["verifier", /\bverif|verify|acredita|validat|\bqa\b|qualit|\btest/i],
  ["reviewer", /\breview|revis|revision|\baudit|criti|\bcode[.\s]?review/i],
  ["implementer", /\bimplement|create|build|agrega|crea|escribe|add(?:s|ing)?\b|engineer|developer|coder|debug|refactor|\bfix\b/i],
];
function inferRole(text) {
  const hits = [];
  for (const [role, re] of ROLE_INFER) if (re.test(text)) hits.push(role);
  const uniq = [...new Set(hits)];
  return uniq.length === 1 ? uniq[0] : undefined;
}

const base = (ev, name) => ({
  session_id: ev.sessionId, transcript_path: ev.transcriptPath ?? "", cwd: ev.cwd,
  permission_mode: "auto", hook_event_name: name,
});

export function toSessionStart(ev) { return { ...base(ev, "SessionStart"), source: "startup" }; }

export function toUserPromptSubmit(ev) {
  // Solo un mensaje de usuario HUMANO (source.kind === "user") cuenta como prompt;
  // los reportes de subagente (source.kind "subagent-settled"/"subagent-report")
  // y los mensajes inyectados por este plugin ("plugin") NO. Y solo el MAS NUEVO,
  // para no re-transcribir el prompt de un paso anterior.
  const human = (ev.messages ?? []).filter((m) => m.role === "user" && m.source?.kind === "user");
  const newest = human.at(-1);
  if (!newest) return undefined;
  const text = (() => {
    const c = newest.content ?? [];
    return (Array.isArray(c) ? c : [c]).map((x) => (typeof x === "string" ? x : x?.text ?? "")).join("\n").trim();
  })();
  if (!text) return undefined;
  return { ...base(ev, "UserPromptSubmit"), prompt: text };
}

// Anade a un payload de PostToolUse el desenlace del comando, en la FORMA que el
// hook ya sabe leer (glm HIGH r4 PR #86). dsh da un resultado de tool "exitoso"
// (isError:false) aunque el comando salga con exit != 0, asi que el adaptador
// tiene que llevar el desenlace MANUALMENTE o el raíl `verified` queda ciego a
// una corrida roja (falso verde). Dos campos:
// - `toolResult.exit_code` en SNAKE (el veto de :2150 grepea exit_code en esa
//   forma; dsh trae camelCase `exitCode`, hay que traducir). Se agrega solo si
//   es numero; el grep exige [1-9] directo tras el ':', asi que 0 no dispara.
// - `tool_response.output` (forma Claude) para que FAILURE_SIGNAL_RE_CI/CS
//   (que grepea $combined, que incluye $INPUT) vea el texto de salida.
function withShellResult(ev, payload) {
  const value = ev.result?.value;
  if (!value || typeof value !== "object") return payload;
  const out = { ...payload };
  if (typeof value.exitCode === "number") out.toolResult = { exit_code: value.exitCode };
  const stdout = value.stdout?.text ?? "";
  const stderr = value.stderr?.text ?? "";
  const output = [stdout, stderr].filter(Boolean).join("\n");
  if (output) out.tool_response = { output };
  return out;
}

export function toPostToolUse(ev) {
  const m = SUBAGENT_TOOL_RE.exec(ev.name ?? "");
  if (m) {
    // El rol solo esta en el TEXTO (15.1: sin subagent_type/persona). La
    // DESCRIPCION es la senal confiable (corta y tipica del rol); el prompt es
    // mas ruidoso (p. ej. un "confirm" del texto del implementer), asi que se
    // prueba primero la descripcion y el prompt queda de fallback.
    const role = m[1] ?? ev.arguments?.persona ?? ev.arguments?.subagent_type
      ?? inferRole(ev.arguments?.description ?? "")
      ?? inferRole(ev.arguments?.prompt ?? "");
    if (!ROLES.has(role)) return undefined;
    const payload = { ...base(ev, "PostToolUse"), tool_name: "Task", tool_input: { subagent_type: role, description: ev.arguments?.description ?? "" } };
    // dsh manda el subagente a su PROPIA sesion (Gap1 claude, r3 PR #86): el
    // evento de spawn trae result.value.subagentId (id de la sesion del hijo) y
    // kind:"continuable". El adaptador lo copia al payload para que index.js
    // pueda mapear sesion-hijo -> sesion-madre + rol (la ceremonia y el candado
    // adversary corren sobre la sesion de la MADRE).
    if (typeof ev.result?.value?.subagentId === "string") payload.subagentId = ev.result.value.subagentId;
    return payload;
  }
  const fs = FS_TOOLS[ev.name];
  if (fs && typeof ev.arguments?.file_path === "string") {
    return { ...base(ev, "PostToolUse"), tool_name: fs, tool_input: { file_path: ev.arguments.file_path } };
  }
  const shell = SHELL_TOOLS[ev.name];
  if (shell && typeof ev.arguments?.command === "string") {
    return withShellResult(ev, { ...base(ev, "PostToolUse"), tool_name: shell, tool_input: { command: ev.arguments.command } });
  }
  return undefined;
}

export function toStop(ev) {
  return { ...base(ev, "Stop"), stop_hook_active: false, last_assistant_message: ev.lastAssistantText ?? "" };
}
