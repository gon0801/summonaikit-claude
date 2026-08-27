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
const SUBAGENT_TOOL_RE = /^subagent(?:[_-](implementer|verifier|reviewer|adversary))?$/;
// Heuristica de rol por texto (15.1: el rol solo esta ahi). Orden por especificidad.
const ROLE_INFER = [
  ["adversary", /\badversar|\battack|\bred[\s_-]?team|\bhack/i],
  ["verifier", /\bverif|\bverify|\bconfirm|\bcheck\b|\btest|acredita|revisa/i],
  ["reviewer", /\breview|\brevision|\baudit|\bcode.?review/i],
  ["implementer", /\bimplement|\badd\b|\bcreate|\bbuild|\bagrega|\bcrea|\bescribe|\bchange|\bupdate/i],
];
function inferRole(text) {
  for (const [role, re] of ROLE_INFER) if (re.test(text)) return role;
  return undefined;
}

const base = (ev, name) => ({
  session_id: ev.sessionId, transcript_path: ev.transcriptPath ?? "", cwd: ev.cwd,
  permission_mode: "auto", hook_event_name: name,
});

export function toSessionStart(ev) { return { ...base(ev, "SessionStart"), source: "startup" }; }

export function toUserPromptSubmit(ev) {
  const text = (ev.messages ?? [])
    .filter((m) => m.role === "user" && !m.source?.startsWith?.("summonaikit"))
    .flatMap((m) => (Array.isArray(m.content) ? m.content : [m.content]))
    .map((c) => (typeof c === "string" ? c : c?.text ?? ""))
    .join("\n").trim();
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
  return undefined;
}

export function toStop(ev) {
  return { ...base(ev, "Stop"), stop_hook_active: false, last_assistant_message: ev.lastAssistantText ?? "" };
}
