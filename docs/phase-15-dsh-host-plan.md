# Phase 15 — summonaikit en dsh (DeepSeek Harness): plan de implementación

> **Para workers:** ejecutar task por task con `superpowers:subagent-driven-development`
> (recomendado) o `superpowers:executing-plans`. Los pasos llevan `- [ ]`. Diseño
> aprobado: `docs/phase-15-dsh-host-design.md` (leerlo entero antes de la task).

**Objetivo:** que un turno en la UI web de dsh armado con `-saikit` reciba el
contrato, corra la ceremonia de roles por la tool `subagent`, y quede bloqueado
al cerrar si falta recibo o evidencia — con el MISMO hook bash que usan los
otros hosts, invocado por un plugin adaptador.

**Arquitectura:** plugin cordis `@summonaikit/dsh-gate` (`hosts/dsh/`, ESM sin
build) que traduce `agent/session-start` → `SessionStart`, `agent/pre-step` →
`UserPromptSubmit`, `tools/result` → `PostToolUse`, `agent/turn-stopping` →
`Stop`, y ejecuta `hooks/summonaikit-harness.sh` con `SUMMONAIKIT_HOOK_TARGET=dsh`.
El hook gana `HOST=dsh`; el instalador gana `--host dsh`.

**Stack:** bash (hook, instalador, tests del gate — `tests/lib/hook_lab.sh`),
Node ≥ 20 con `node:test` (adaptador y su banco), YAML (`cordis.patch.yml`),
dsh `@deepseek-ai/dsh` 0.1.1-rc.2 (peer, nunca dependencia).

## Restricciones globales (aplican a cada task)

- `not_observed != absent`: lo no medido se escribe `unknown`, nunca se rellena.
- Cada bug o rama nueva del hook: rojo medido pre-fix + caso que acredita +
  caso que bloquea + mutación acreditada + línea base golden con 0 divergencias
  (o regrabado con diff auditado, precedente 11.1).
- Local: SOLO el driver/archivo tocado (`SAIKIT_HOOK_VIVO="$PWD/hooks/summonaikit-harness.sh"`);
  la batería completa la corre CI en el PR. Rama desde `origin/master`;
  `git log origin/master..HEAD` lista solo commits de la task.
- Fail-open del adaptador (D3): ningún error del plugin o del hook traba dsh;
  se registra y se deja pasar. Fail-closed solo en el instalador.
- Tope: 2 rondas de bots/cross-review por PR; lo residual se declara en el spec.
- Sin dependencias npm nuevas en `hosts/dsh/` (solo `node:*` y el peer dsh).
- Nada de secretos en fixtures capturados: revisar y redactar antes de commitear.
- Versión de dsh contra la que se midió queda escrita (`hosts/dsh/package.json`
  → `summonaikit.measuredAgainst`), y el instalador la reporta si difiere.

---

### Task 15.1 — Captura: qué trae dsh de verdad

**Archivos:**
- Crear: `hosts/dsh/spy/index.js` (plugin espía, ~60 líneas)
- Crear: `hosts/dsh/spy/package.json`
- Crear: `tests/fixtures/dsh/README.md`, `tests/fixtures/dsh/*.jsonl`
- Crear: `docs/task-15.1-medicion-dsh.md`

**Interfaces:**
- Produce: los fixtures JSONL (una línea por evento: `{"event":"agent/pre-step","payload":{...}}`)
  y la tabla "campo observado / ausente / unknown" del doc de medición, que las
  tasks 15.2–15.4 leen como fuente de verdad.

- [ ] **Paso 1: el plugin espía.** Sin hook, solo vuelca eventos a JSONL.

```js
// hosts/dsh/spy/index.js — ESPÍA de medición (15.1). No es el adaptador.
import { appendFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import z from "@deepseek-ai/schemastery";

export const name = "summonaikit-spy";
export const Config = z.object({ out: z.string().required() });

// Redaccion ANTES de escribir (bots PR #83): los mismos patrones que el hook y
// el perfil adversary — valores de token/password/secret/api_key (con o sin
// comillas), claves `sk-…`, y credenciales en URIs. La revision manual del
// paso 5 es la SEGUNDA capa, no la unica.
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

function dump(out, event, payload) {
  // Solo lo serializable; Agent/AbortSignal/funciones se reducen a su forma.
  const seen = new WeakSet();
  const json = JSON.stringify({ ts: new Date().toISOString(), event, payload }, (k, v) => {
    if (typeof v === "function") return "[fn]";
    if (v instanceof AbortSignal) return "[signal]";
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
```

```json
{ "name": "@summonaikit/dsh-spy", "version": "0.0.1", "type": "module", "main": "index.js",
  "peerDependencies": { "@deepseek-ai/cordis": "*", "@deepseek-ai/schemastery": "*" } }
```

- [ ] **Paso 2: componerlo en un profile desechable**, no en `web`. Crear
  `~/.dsh/profiles/saikit-medicion/` copiando `~/.dsh/profiles/web/` y agregar en
  su `cordis.patch.yml`:

```yaml
- insert:
    - id: summonaikit-spy
      name: '@summonaikit/dsh-spy'
      config:
        out: C:/dev/saikit-captura/dsh/captura.jsonl
```

  Vincular el paquete: `cd ~/.dsh/profiles/saikit-medicion && dsh plugin --profile saikit-medicion add C:/dev/summonaikit-claude/hosts/dsh/spy`
  (si `add` exige un paquete publicado, usar `pnpm add file:...` en el dir del
  profile — anotar cuál funcionó). Verificar: `dsh --profile saikit-medicion --dump-config | grep summonaikit-spy`.

- [ ] **Paso 3: turno vivo de captura** en `C:/dev/saikit-captura/dsh-repo`
  (repo desechable con un `app.py`): en la UI web, con el profile de medición,
  pedir: *"-saikit agrega un docstring a app.py. Delegá la implementación a un
  subagente y la verificación a otro."* Dejar que termine. Después un segundo
  turno SIN `-saikit`.

- [ ] **Paso 4: leer la captura y escribir la tabla.** En
  `docs/task-15.1-medicion-dsh.md`, una fila por pregunta, cada una con
  `observado` (cita del JSONL) / `ausente` (buscado, no está) / `unknown` (no se
  pudo observar):
  1. `agent/pre-step`: ¿`messages[]` trae el texto del usuario? ¿en qué campo
     (`content[].text`)? ¿`step === 1` marca el primer paso del turno?
  2. `tools/result` de la delegación: ¿`exec.name` es `subagent`? ¿la persona
     viene en `exec.arguments` (campo) o solo en la config de la tool (entonces
     el rol se distingue por el NOMBRE de la tool)? ¿`exec.parent` distingue
     llamadas del hijo?
  3. tools de fs: nombres reales (`str_replace_editor`, `write`, …) y campo de
     ruta (`file_path`?).
  4. `agent/turn-stopping`: ¿llega una vez por turno? ¿qué evento de
     `session/event` (`assistant/message` / `assistant/chunk`) trae el texto
     final del asistente y con qué forma?
  5. ¿`agent.id` es el `SessionId`? ¿`session.id` en `session/event` es la
     MISMA cadena que `agent.id` del `agent/turn-stopping` del mismo turno?
     (el espía vuelca ambos; compararlos literal). ¿De dónde sale el cwd
     (`agent/created` `meta.cwd`?)?
  8. Redacción: buscar en la captura `token=`, `sk-`, `://…:…@` — tienen que
     salir `[REDACTED]` (el espía redacta antes de escribir); si algo se
     escapó, ampliar `SECRET_RES` y volver a capturar.
  6. JSONL de sesión en `~/.dsh/sessions/`: ¿tiene `role:"assistant"` +
     `content[].type:"text"` como exige el walker del hook?
  7. ¿`~/.dsh/AGENTS.md` se inyecta? (control: crear uno con una frase única y
     buscarla en el request).

- [ ] **Paso 5: fixtures.** Copiar el JSONL a `tests/fixtures/dsh/` partido por
  evento (`pre-step.jsonl`, `tools-result-subagent.jsonl`, `tools-result-fs.jsonl`,
  `turn-stopping.jsonl`, `session-events.jsonl`) tras **redactar** rutas del
  home y cualquier token. `README.md` del dir: qué turno los produjo, versión
  de dsh (`dsh --version`), fecha.

- [ ] **Paso 6: commit + PR (docs+fixtures).**
  `git add hosts/dsh/spy tests/fixtures/dsh docs/task-15.1-medicion-dsh.md`
  `git commit -m "feat(15.1): espía de medición de dsh + captura de un turno vivo + tabla observado/ausente/unknown"`.
  Retirar el profile de medición al final (`rm -r ~/.dsh/profiles/saikit-medicion`).

**DoD:** las 7 preguntas tienen respuesta citada o `unknown` explícito; los
fixtures no contienen secretos; el espía no queda en ningún profile real.

---

### Task 15.2 — El hook conoce `HOST=dsh`

**Archivos:**
- Modificar: `hooks/summonaikit-harness.sh:110-118` (detección de host), `:259`
  (`saikit_host_ciego`, NO tocar salvo que 15.1 mida ceguera), `:500` (session id
  fallback), `:2388` (salida por host en Stop)
- Modificar: `tests/lib/hook_lab.sh` (target `dsh` ya pasa por `SUMMONAIKIT_HOOK_TARGET`, línea 134 — verificar; agregar `LAB_DSH_*` solo si 15.1 midió señales propias)
- Modificar: `tests/lib/gate_cases.sh` (casos `caso_g1_dsh_*`, `caso_g2_dsh_*`), `tests/test_gate_mutations.sh` (mutación `host_dsh_no_reconocido`), `tests/golden/baseline.txt` (regrabado), `tools/golden-harness.sh` (escenarios dsh si el runner los enumera por host)

**Interfaces:**
- Consume: forma de payloads de 15.1 (los fixtures).
- Produce: `HOST=dsh` en el hook; estado en `$STATE_ROOT/dsh/$PROJECT_KEY`;
  salida de Stop para dsh en el mismo formato JSON que claude
  (`{"decision":"block","reason":...}`) — el adaptador lo parsea así.

- [ ] **Paso 1: caso rojo.** En `gate_cases.sh`, junto a los `caso_g1_*` de
  host, agregar y registrar en `CASOS_G1`:

```bash
# Phase 15 — dsh se identifica por SUMMONAIKIT_HOOK_TARGET=dsh (D2), como codex:
# nunca por variables heredadas. Un prompt con -saikit bajo target dsh ARMA y el
# estado queda bajo state/dsh/ (aislamiento por host, 5.3).
caso_g1_dsh_arma_y_aisla_estado() {
  lab_run prompt dsh "$(lab_payload_prompt '-saikit agrega el docstring')"
  _igual "exit code" "$LAB_RC" "0"
  _contiene "stdout" "$LAB_OUT" 'SUMMONAIKIT HARNESS REQUIRED'
  _existe "estado bajo dsh" "$LAB/home/.claude/hooks/state/dsh"
}
# Sin target dsh, el mismo payload NO cae en dsh (HOST=other/claude segun el lab).
caso_g1_dsh_no_se_hereda_sin_target() {
  lab_run prompt auto "$(lab_payload_prompt '-saikit agrega el docstring')"
  _no_existe "sin estado dsh" "$LAB/home/.claude/hooks/state/dsh"
}
```

  (Si `_existe`/`_no_existe` no existen en `hook_lab.sh`, agregarlas al lado
  de `_contiene`: `_existe() { [ -e "$3" ] || malo "$1: no existe $3"; }`.)

- [ ] **Paso 2: correr solo esos casos** con un driver (30 s), esperar ROJO:
  `caso_g1_dsh_arma_y_aisla_estado` falla porque `HOST=other` no crea `state/dsh`.

- [ ] **Paso 3: la rama en el hook** (`:110`):

```bash
elif [ "${SUMMONAIKIT_HOOK_TARGET:-}" = "codex" ]; then
  HOST=codex
# Phase 15 (D2): dsh no exporta senal propia medible desde el hook (el plugin
# corre en el proceso de dsh y lanza bash); el adaptador declara el target,
# igual que el wrapper de codex. Setness+valor exacto: un hijo lanzado DESDE
# dsh sin el adaptador no se cree dsh.
elif [ "${SUMMONAIKIT_HOOK_TARGET:-}" = "dsh" ]; then
  HOST=dsh
```

  Revisar cada `case`/`if` por host listado por
  `grep -nE '"\$HOST" = |case "\$HOST"' hooks/summonaikit-harness.sh` y decidir
  dsh explícitamente (default: como claude — salida JSON en Stop, sin `reason`
  extra de grok). `saikit_host_ciego()` NO cambia salvo medición (D7).

- [ ] **Paso 4: verde** con el driver; luego los casos G2 de ceremonia con
  target dsh (copiar `caso_g2_zcode_verif_subagente_acredita` como
  `caso_g2_dsh_ceremonia_cierra` usando `lab_run ... dsh` y `lab_payload_agent`
  para implementer/verifier/reviewer, y `caso_g2_dsh_sin_recibo_bloquea`).

- [ ] **Paso 5: mutación.** En `test_gate_mutations.sh`, fila
  `G1|host_dsh_no_reconocido|la rama HOST=dsh se apaga y un turno dsh cae en other (Phase 15)`
  y `mut_host_dsh_no_reconocido() { sed 's/= "dsh" \]; then/= "NUNCA_dsh" ]; then/'; }`.
  Verificar que la mutación cambia el hook (`diff`) y que la atrapa
  `caso_g1_dsh_arma_y_aisla_estado`.

- [ ] **Paso 6: golden.** Si `tools/golden-harness.sh` enumera targets, sumar
  `dsh` con un escenario de prompt y uno de Stop (payloads de 15.1). Regrabar
  UNA vez (`--record`), auditar el diff (solo header + escenarios nuevos; 0
  veredictos movidos) y correr `bash tests/test_golden_harness.sh`.

- [ ] **Paso 7: commit + PR.** `fix(15.2): HOST=dsh en el hook — rama por target, estado aislado, casos G1/G2 + mutacion + golden`.

**DoD:** rojo medido; 2 casos G1 + 2 G2 con nombre; mutación acreditada;
golden 0 divergencias; CI 5/5.

---

### Task 15.3 — El adaptador `@summonaikit/dsh-gate`

**Archivos:**
- Crear: `hosts/dsh/package.json`, `hosts/dsh/index.js`, `hosts/dsh/translate.js`,
  `hosts/dsh/spawn-hook.js`, `hosts/dsh/README.md`
- Crear: `hosts/dsh/test/translate.test.js`, `hosts/dsh/test/spawn-hook.test.js`,
  `hosts/dsh/test/plugin.test.js`, `hosts/dsh/test/fake-hook.sh`
- Modificar: `.github/workflows/*.yml` (job `quality` o nuevo `node-adapter`: `node --test hosts/dsh/test/`)

**Interfaces:**
- Consume: fixtures de 15.1; contrato de salida del hook (stdout JSON:
  `hookSpecificOutput.additionalContext` en prompt; `{"decision":"block","reason"}`
  o vacío en Stop; exit 0 siempre en fail-open).
- Produce: `translate.js` exporta `toSessionStart(ev)`, `toUserPromptSubmit(ev)`,
  `toPostToolUse(ev)`, `toStop(ev)` → objeto payload (o `undefined` si el evento
  no aplica); `spawn-hook.js` exporta `runHook({ hook, payload, env, timeoutMs })`
  → `{ ok, stdout, json, error }`; `index.js` exporta `{ name, Config, apply }`.

- [ ] **Paso 1: tests de `translate.js`** (puros, sobre los fixtures):

```js
// hosts/dsh/test/translate.test.js
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { toUserPromptSubmit, toPostToolUse, toStop, toSessionStart } from "../translate.js";

const fx = (f) => readFileSync(new URL(`../../../tests/fixtures/dsh/${f}`, import.meta.url), "utf8")
  .trim().split("\n").map((l) => JSON.parse(l));

test("pre-step con texto del usuario -> UserPromptSubmit con prompt y session_id", () => {
  const ev = fx("pre-step.jsonl").find((e) => e.event === "agent/pre-step");
  const p = toUserPromptSubmit({ sessionId: "sess_dsh_1", cwd: "C:/proyecto", ...ev.payload });
  assert.equal(p.hook_event_name, "UserPromptSubmit");
  assert.equal(p.session_id, "sess_dsh_1");
  assert.equal(p.cwd, "C:/proyecto");
  assert.match(p.prompt, /-saikit/);
});

test("pre-step sin mensaje de usuario (solo contexto inyectado) -> undefined", () => {
  const p = toUserPromptSubmit({ sessionId: "s", cwd: "c", step: 2, messages: [] });
  assert.equal(p, undefined);
});

test("tools/result de subagent -> PostToolUse Task con subagent_type", () => {
  const ev = fx("tools-result-subagent.jsonl")[0];
  const p = toPostToolUse({ sessionId: "s", cwd: "c", ...ev.payload });
  assert.equal(p.hook_event_name, "PostToolUse");
  assert.equal(p.tool_name, "Task");
  assert.match(p.tool_input.subagent_type, /^(implementer|verifier|reviewer|adversary)$/);
});

test("tools/result de una tool de fs -> PostToolUse Edit/Write con file_path", () => {
  const ev = fx("tools-result-fs.jsonl")[0];
  const p = toPostToolUse({ sessionId: "s", cwd: "c", ...ev.payload });
  assert.ok(["Edit", "Write"].includes(p.tool_name));
  assert.equal(typeof p.tool_input.file_path, "string");
});

test("tools/result de una tool ajena (bash) -> undefined", () => {
  const p = toPostToolUse({ sessionId: "s", cwd: "c", name: "bash", arguments: { command: "ls" } });
  assert.equal(p, undefined);
});

test("turn-stopping -> Stop con last_assistant_message", () => {
  const p = toStop({ sessionId: "s", cwd: "c", lastAssistantText: "SUMMONAIKIT HARNESS RECEIPT\n..." });
  assert.equal(p.hook_event_name, "Stop");
  assert.equal(p.stop_hook_active, false);
  assert.match(p.last_assistant_message, /RECEIPT/);
});
```

  La forma exacta de `ev.payload` (dónde está el texto, cómo se llama la persona)
  la fija 15.1: **si el doc de medición dice otro campo, el test usa el medido**.

- [ ] **Paso 2: correr y ver rojo:** `node --test hosts/dsh/test/translate.test.js`
  → falla por módulo inexistente.

- [ ] **Paso 3: `translate.js`** (puro; sin dsh, sin fs):

```js
// hosts/dsh/translate.js — evento dsh -> payload del hook. Puro. Phase 15 §3.
const ROLES = new Set(["implementer", "verifier", "reviewer", "adversary"]);
// Medido en 15.1 (ajustar aqui si la captura dice otra cosa):
const FS_TOOLS = { write: "Write", str_replace_editor: "Edit", edit: "Edit" };
const SUBAGENT_TOOL_RE = /^subagent(?:[_-](implementer|verifier|reviewer|adversary))?$/;

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
    const role = m[1] ?? ev.arguments?.persona ?? ev.arguments?.subagent_type;
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
```

- [ ] **Paso 4: verde** `node --test hosts/dsh/test/translate.test.js`.

- [ ] **Paso 5: tests de `spawn-hook.js`** con un hook falso:

```bash
#!/usr/bin/env bash
# hosts/dsh/test/fake-hook.sh — responde segun el evento; simula al hook real.
set -u
in="$(cat)"
ev="$(printf '%s' "$in" | sed -n 's/.*"hook_event_name":"\([A-Za-z]*\)".*/\1/p')"
case "$ev" in
  UserPromptSubmit) printf '%s' "$in" | grep -q -- '-saikit' && printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"SUMMONAIKIT HARNESS REQUIRED"}}' ;;
  Stop) printf '%s' "$in" | grep -q 'SUMMONAIKIT HARNESS RECEIPT' || printf '{"decision":"block","reason":"SUMMONAIKIT HARNESS GATE\\n\\nFailed gates:\\n- Missing SUMMONAIKIT HARNESS RECEIPT."}' ;;
  *) : ;;
esac
exit 0
```

```js
// hosts/dsh/test/spawn-hook.test.js
import { test } from "node:test";
import assert from "node:assert/strict";
import { runHook } from "../spawn-hook.js";
const hook = new URL("./fake-hook.sh", import.meta.url).pathname.replace(/^\/([A-Za-z]):/, "$1:");

test("prompt con -saikit devuelve additionalContext", async () => {
  const r = await runHook({ hook, payload: { hook_event_name: "UserPromptSubmit", prompt: "-saikit x" }, timeoutMs: 10000 });
  assert.equal(r.ok, true);
  assert.match(r.json.hookSpecificOutput.additionalContext, /REQUIRED/);
});
test("stop sin recibo devuelve block", async () => {
  const r = await runHook({ hook, payload: { hook_event_name: "Stop", last_assistant_message: "hola" }, timeoutMs: 10000 });
  assert.equal(r.json.decision, "block");
});
test("stop con recibo devuelve vacio (sin json)", async () => {
  const r = await runHook({ hook, payload: { hook_event_name: "Stop", last_assistant_message: "SUMMONAIKIT HARNESS RECEIPT" }, timeoutMs: 10000 });
  assert.equal(r.ok, true); assert.equal(r.json, undefined);
});
test("hook inexistente -> fail-open con error declarado", async () => {
  const r = await runHook({ hook: "C:/no/existe.sh", payload: { hook_event_name: "Stop" }, timeoutMs: 2000 });
  assert.equal(r.ok, false); assert.match(r.error, /ENOENT|no existe|not found/i);
});
test("salida no-JSON -> fail-open", async () => {
  const r = await runHook({ hook, payload: { hook_event_name: "Stop" }, timeoutMs: 2000, _bashArgs: ["-c", "echo 'esto no es json'"] });
  assert.equal(r.ok, true); assert.equal(r.json, undefined); assert.match(r.error ?? "", /JSON/);
});
```

- [ ] **Paso 6: `spawn-hook.js`:**

```js
// hosts/dsh/spawn-hook.js — ejecuta el hook bash con el payload por stdin. Fail-open.
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";

export function runHook({ hook, payload, env = {}, timeoutMs = 20000, bash = "bash", _bashArgs }) {
  return new Promise((resolve) => {
    if (!_bashArgs && !existsSync(hook)) return resolve({ ok: false, error: `hook no existe: ${hook}` });
    const args = _bashArgs ?? [hook];
    let child;
    try {
      child = spawn(bash, args, { env: { ...process.env, SUMMONAIKIT_HOOK_TARGET: "dsh", ...env }, windowsHide: true });
    } catch (e) { return resolve({ ok: false, error: String(e) }); }
    let out = "", err = "";
    const timer = setTimeout(() => { child.kill(); resolve({ ok: false, error: `timeout ${timeoutMs}ms` }); }, timeoutMs);
    child.stdout.on("data", (d) => (out += d));
    child.stderr.on("data", (d) => (err += d));
    child.on("error", (e) => { clearTimeout(timer); resolve({ ok: false, error: String(e), stderr: err }); });
    child.on("close", () => {
      clearTimeout(timer);
      const text = out.trim();
      if (!text) return resolve({ ok: true, stdout: out, json: undefined, stderr: err });
      try { resolve({ ok: true, stdout: out, json: JSON.parse(text), stderr: err }); }
      catch { resolve({ ok: true, stdout: out, json: undefined, stderr: err, error: "salida no-JSON del hook" }); }
    });
    child.stdin.end(JSON.stringify(payload));
  });
}
```

- [ ] **Paso 7: verde** `node --test hosts/dsh/test/spawn-hook.test.js`.

- [ ] **Paso 8: test del plugin con un dsh falso** (`plugin.test.js`): un `ctx`
  mínimo `{ on(event, fn) { handlers[event] = fn }, logger: { warn() {} } }` y
  un `agent` falso `{ id: "sess_dsh_1", followup: (m) => queued.push(m), inbox: {...} }`.
  Casos: (a) pre-step con `-saikit` y hook falso → la decisión devuelta trae un
  mensaje extra con `SUMMONAIKIT HARNESS REQUIRED`; (b) pre-step sin `-saikit`
  → decisión intacta; (c) turn-stopping sin recibo → `agent.followup` llamado
  una vez con el `reason`; (d) turn-stopping con recibo → no se llama; (e) hook
  inexistente en config → ningún throw, `logger.warn` llamado, decisión intacta;
  (f) **orden**: un `tools/result` cuyo hook falso tarda 300 ms seguido de
  `turn-stopping` inmediato → el hook falso registra el `PostToolUse` ANTES del
  `Stop` (el fake escribe una línea por llamada a un archivo; el test lee el
  orden). Sin la cola por sesión este caso es ROJO — medirlo así primero.

- [ ] **Paso 9: `index.js`:**

```js
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

// Una clave por sesion para TODO: cola, texto del asistente, cwd. Que `agent.id`
// y `session.id` de session/event sean la misma cadena lo decide 15.1 (pregunta
// 5); si no lo son, esta funcion es el UNICO lugar que se ajusta.
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

  ctx.on("agent/created", ({ agent, meta }) => { if (meta?.cwd) cwdOf.set(sessionKey(agent), meta.cwd); });
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
    const msg = { id: crypto.randomUUID(), role: "user", source: "summonaikit-gate", content: [{ type: "text", text: extra }] };
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
    if (json?.decision === "block" && json.reason) agent.followup({ role: "user", source: "summonaikit-gate", content: [{ type: "text", text: json.reason }] });
  });
}
function textOf(event) {
  const c = event?.message?.content ?? event?.content ?? [];
  return (Array.isArray(c) ? c : [c]).map((x) => (typeof x === "string" ? x : x?.text ?? "")).join("\n");
}
```

  La forma de `msg`/`followup` y de `assistant/message` es la de 15.1: si la
  captura dice que `messages` exige `createMessage` de `dsh-llm` o un `source`
  tipado, usar eso — y anotar la diferencia en el README.

- [ ] **Paso 10: verde** `node --test hosts/dsh/test/`. `package.json`:

```json
{ "name": "@summonaikit/dsh-gate", "version": "0.1.0", "type": "module", "main": "index.js",
  "peerDependencies": { "@deepseek-ai/cordis": "*", "@deepseek-ai/schemastery": "*" },
  "summonaikit": { "measuredAgainst": "@deepseek-ai/dsh@0.1.1-rc.2" } }
```

- [ ] **Paso 11: CI.** En el workflow existente, paso `node --test hosts/dsh/test/`
  (Node 20+ ya está en el runner). Commit + PR:
  `feat(15.3): adaptador @summonaikit/dsh-gate — traduce 4 eventos al hook, fail-open, banco con dsh y hook falsos`.

**DoD:** 3 archivos de test en verde local y en CI; ninguna regla del gate en JS;
fail-open probado (hook ausente, timeout, no-JSON).

---

### Task 15.4 — Instalador, verificador y ruteo

**Archivos:**
- Modificar: `tools/install-hook.sh` (DEST para dsh junto a `:153-165`; funciones
  `dsh_*` junto a `zcode_*`; dispatch junto a `:1352`), `tools/check-hook-registration.sh`
  (forma `--dsh-home`), `tools/model-routing.sh` (fila `dsh` vacía)
- Modificar: `tests/test_install_hook.sh`, `tests/test_check_hook_registration.sh`
  (o el que exista para el checker), `tests/test_model_routing.sh`

**Interfaces:**
- Consume: `hosts/dsh/` (paquete a copiar), personas (formato de 15.1).
- Produce: `~/.dsh/hooks/summonaikit-harness.sh`, `~/.dsh/plugins/summonaikit-dsh-gate/`,
  entrada entre marcas en `~/.dsh/cordis.patch.yml`, personas con `saikit_owned`.

- [ ] **Paso 1: casos rojos** en `test_install_hook.sh` (con `HOME` de
  laboratorio, `SAIKIT_DSH_HOME` como costura de test igual que `SAIKIT_GROK_HOOKS_DIR`):
  `dsh: instala hook + plugin + entrada entre marcas + 4 personas (limpio)`,
  `dsh: --dry-run no escribe nada (ni backups)`, `dsh: patch con contenido ajeno fuera de marcas se respeta`,
  `dsh: repara hook y plugin viejos con backup`, `dsh: --quitar-dsh deja el patch sin nuestra entrada y las personas ajenas intactas`,
  `dsh: sin bash.exe => exit 2 y nada escrito`, `dsh: version de dsh distinta de measuredAgainst => se REPORTA, no se aborta`.

- [ ] **Paso 2: rojo** `bash tests/test_install_hook.sh` (solo los casos nuevos
  fallan: `--host dsh` es rechazado hoy en `:125`).

- [ ] **Paso 3: implementación.** Aceptar `dsh` en `:125-126`; DEST:

```bash
# Phase 15 (D5): dsh declara su ruta; el plugin la lee de su config.
if [ "$HOST" = "dsh" ] && [ "$VIO_DEST" -eq 0 ]; then
  DEST="${SAIKIT_DSH_HOME:-${HOME:-}/.dsh}/hooks/summonaikit-harness.sh"
fi
```

  Funciones (mismo estilo que `zcode_*`; `decir`, backups `saikit-backups/…<fecha>.bak`,
  temporal en el mismo dir + `mv`): `dsh_home()`, `dsh_plugin_dir()`
  (`$dsh_home/plugins/summonaikit-dsh-gate`), `dsh_patch()` (`$dsh_home/cordis.patch.yml`),
  `dsh_publicar_plugin()` (copia `hosts/dsh/{index,translate,spawn-hook}.js` +
  `package.json`, compara sha por archivo, repara con backup), `dsh_patch_entrada()`
  (bloque entre `# >>> summonaikit-gate START` / `# <<< summonaikit-gate END`):

```yaml
# >>> summonaikit-gate START — managed by summonaikit-claude tools/install-hook.sh
- insert:
    - id: summonaikit-gate
      name: '<ruta absoluta de dsh_plugin_dir()>'
      config:
        hook: '<DEST>'
        bash: '<zcode_bash_win(), p. ej. C:/Program Files/Git/bin/bash.exe>'
# <<< summonaikit-gate END
```

  `dsh_publicar_personas()` en el formato medido en 15.1 (si 15.1 midió que la
  persona va por instancia de tool, la entrada del patch suma 4 instancias
  `subagent_<rol>` con `config.persona` apuntando al perfil traducido por
  `agente_traducido dsh <fuente>`); `dsh_instalar()` con preflights (bash.exe,
  `dsh --version` vs `measuredAgainst`, DEST NUESTRO_IDENTICO como exige zcode),
  `DRY_RUN` que solo reporta; `dsh_quitar()` inverso. Dispatch:

```bash
if [ "$HOST" = "dsh" ]; then
  if [ "$QUITAR" -eq 1 ]; then dsh_quitar; exit $?; fi
  dsh_instalar; exit $?
fi
```

- [ ] **Paso 4: verde** `bash tests/test_install_hook.sh`.

- [ ] **Paso 5: verificador.** `tools/check-hook-registration.sh --dsh-home <dir>`:
  silencio si existen el hook, el dir del plugin con sus 4 archivos, la entrada
  entre marcas en `cordis.patch.yml` con `hook:` apuntando al hook, y las 4
  personas con marca; habla (una línea por falta) si no. Casos en el test del
  checker: completo → silencio; sin entrada → habla; `hook:` apuntando a otra
  ruta → habla. Además `dsh --dump-config` con `summonaikit-gate` en la salida
  como verificación manual documentada (no en el test: depende del binario).

- [ ] **Paso 6: ruteo.** Fila `dsh` vacía en `tools/model-routing.sh` (hereda),
  caso en `test_model_routing.sh`: `--host dsh --role implementer --field model`
  imprime vacío y `--format frontmatter` no emite `model:`; el candado "IDs de
  modelo SOLO en el router" sigue verde.

- [ ] **Paso 7: commit + PR.** `feat(15.4): --host dsh en el instalador (hook + plugin + patch entre marcas + personas), --quitar-dsh, --dry-run, checker --dsh-home, fila dsh del router`.

**DoD:** 7 casos del instalador + 3 del checker + 1 del router en verde; el
patch ajeno intacto byte a byte en los casos que lo prueban; CI 5/5.

---

### Task 15.5 — Turno vivo, deploy y documentación

**Archivos:**
- Modificar: `docs/spec/00-project-spec.md` (§ nuevo "Host dsh (Phase 15)"),
  `agents/adversary.md` (fila dsh en la tabla de enforcement por host),
  `README.md` (dsh entre los hosts), `docs/deploy-log.md`
- Crear: `docs/smoke-dsh-2026-XX-XX.md` (evidencia del turno vivo)

- [ ] **Paso 1: deploy** desde master con el instalador: `bash tools/install-hook.sh --host dsh`;
  `bash tools/check-hook-registration.sh --dsh-home ~/.dsh` (silencio);
  `dsh --dump-config | grep summonaikit-gate`.

- [ ] **Paso 2: turno vivo** en la UI web sobre un repo desechable, tres
  escenarios, cada uno con transcript guardado:
  1. `-saikit agrega un docstring a app.py` → aparece el contrato; el lead
     delega por `subagent` (implementer, verifier, reviewer); el recibo cierra.
  2. Mismo pedido, y al final se le pide al modelo que cierre SIN recibo → el
     turno vuelve con `SUMMONAIKIT HARNESS GATE` y sigue hasta el recibo.
  3. Pedido sin `-saikit` → nada del harness aparece (byte-idéntico a un dsh sin plugin).
  Anotar en `docs/smoke-dsh-…md` qué pasó en cada uno, literal.

- [ ] **Paso 3: spec.** § "Host dsh (Phase 15)": adaptador y sus 4 traducciones,
  fail-open, personas, composición home, límites (versión rc, canal interno
  según lo medido en 15.1 — `unknown` si no se midió, ceguera NO declarada),
  `headless`/`tui` fuera de alcance.

- [ ] **Paso 4: perfil y README.** `agents/adversary.md`: fila dsh en la tabla
  por host con el enforcement REAL medido (candado aplicable o `unknown`).
  `README.md`: dsh en la lista de hosts con "cómo se instala".

- [ ] **Paso 5: deploy-log** con backups, sha del hook, salida del checker
  citada (silencio), versión de dsh. Commit + PR:
  `docs(15.5): turno vivo de dsh, spec § host dsh, perfil por host, deploy anotado`.

**DoD:** los 3 escenarios con evidencia literal; spec/perfil/README coherentes
entre sí y con lo que el instalador hace; deploy anotado.

---

### Task 15.6 — Cierre del ledger

- [ ] `Plans.md`: filas 15.1–15.5 en `cc:完了` con sha/PR; la 15.6 misma.
- [ ] `docs/plans-archivo.md` si `Plans.md` supera las 200 líneas (candado
  `context-docs-budget`): mover Phase 13 al archivo.
- [ ] Commit + PR `docs(15.6): cierre de la Phase 15`.

---

## Auto-revisión del plan (hecha)

- **Cobertura del diseño:** D1 (15.3), D2 (15.2), D3 (15.3 pasos 5–9), D4 (15.4
  personas + 15.1 pregunta 2), D5 (15.4 patch home), D6 (15.4 paso 6), D7 (15.2
  paso 3 + 15.5 spec). Escalera §5 del diseño = tasks 15.1→15.5 en orden.
- **Sin placeholders:** los puntos que dependen de la medición nombran la
  pregunta de 15.1 que los resuelve y el default que se usa si la captura
  coincide con lo documentado.
- **Nombres consistentes:** `toSessionStart/toUserPromptSubmit/toPostToolUse/toStop`,
  `runHook`, `summonaikit-gate`, `SAIKIT_DSH_HOME`, `--quitar-dsh`, `--dsh-home`
  usados igual en 15.3, 15.4 y 15.5.
