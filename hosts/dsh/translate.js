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
    return { ...base(ev, "PostToolUse"), tool_name: "Task", tool_input: { subagent_type: role, description: ev.arguments?.description ?? "" } };
  }
  const fs = FS_TOOLS[ev.name];
  if (fs && typeof ev.arguments?.file_path === "string") {
    return { ...base(ev, "PostToolUse"), tool_name: fs, tool_input: { file_path: ev.arguments.file_path } };
  }
  const shell = SHELL_TOOLS[ev.name];
  if (shell && typeof ev.arguments?.command === "string") {
    return { ...base(ev, "PostToolUse"), tool_name: shell, tool_input: { command: ev.arguments.command } };
  }
  return undefined;
}

export function toStop(ev) {
  return { ...base(ev, "Stop"), stop_hook_active: false, last_assistant_message: ev.lastAssistantText ?? "" };
}
