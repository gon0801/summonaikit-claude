// hosts/dsh/test/plugin.test.js — apply() con un dsh falso (ctx + agent) y hook falso.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { apply } from "../index.js";


const hookPath = new URL("./fake-hook.sh", import.meta.url).pathname.replace(/^\/([A-Za-z]):/, "$1:");

async function install(ctx, log) {
  const handlers = {};
  await apply(ctx, { hook: hookPath, bash: "bash", timeoutMs: 10000 });
  return handlers;
}

test("pre-step con -saikit -> la decision agrega el contrato (SUMMONAIKIT HARNESS REQUIRED)", async () => {
  const handlers = {};
  const ctx = { on: (ev, fn) => { handlers[ev] = fn; }, logger: { warn() {} } };
  await apply(ctx, { hook: hookPath, bash: "bash", timeoutMs: 10000 });
  const agent = { id: "sess_dsh_1" };
  const decision = await handlers["agent/pre-step"](
    { agent, step: 1, messages: [{ role: "user", source: { kind: "user" }, content: [{ type: "text", text: "-saikit agrega el docstring" }] }] },
    async () => ({ kind: "enter", messages: [{ role: "user", content: [{ type: "text", text: "-saikit agrega el docstring" }] }] }),
  );
  assert.equal(decision.kind, "enter");
  const injected = decision.messages.filter((m) => JSON.stringify(m).includes("SUMMONAIKIT HARNESS REQUIRED"));
  assert.ok(injected.length === 1, "debe haber 1 mensaje de contrato");
  assert.deepEqual(injected[0].source, { kind: "plugin", plugin: "summonaikit-gate" });
});

test("pre-step sin -saikit -> decision intacta (sin contrato extra)", async () => {
  const handlers = {};
  const ctx = { on: (ev, fn) => { handlers[ev] = fn; }, logger: { warn() {} } };
  await apply(ctx, { hook: hookPath, bash: "bash", timeoutMs: 10000 });
  const agent = { id: "sess_dsh_1" };
  const decision = await handlers["agent/pre-step"](
    { agent, step: 1, messages: [{ role: "user", source: { kind: "user" }, content: [{ type: "text", text: "hola" }] }] },
    async () => ({ kind: "enter", messages: [{ role: "user", content: [{ type: "text", text: "hola" }] }] }),
  );
  assert.equal(decision.messages.length, 1);
  assert.ok(!JSON.stringify(decision).includes("SUMMONAIKIT HARNESS REQUIRED"));
});

test("turn-stopping sin recibo -> followup una vez con el reason", async () => {
  const handlers = {};
  const ctx = { on: (ev, fn) => { handlers[ev] = fn; }, logger: { warn() {} } };
  await apply(ctx, { hook: hookPath, bash: "bash", timeoutMs: 10000 });
  const queued = [];
  const agent = { id: "sess_dsh_1", followup: (m) => queued.push(m) };
  await handlers["agent/turn-stopping"]({ agent });
  assert.equal(queued.length, 1);
  assert.deepEqual(queued[0].source, { kind: "plugin", plugin: "summonaikit-gate" });
  assert.match(queued[0].content[0].text, /SUMMONAIKIT HARNESS GATE/);
});

test("turn-stopping con recibo -> followup NO se llama", async () => {
  const handlers = {};
  const ctx = { on: (ev, fn) => { handlers[ev] = fn; }, logger: { warn() {} } };
  await apply(ctx, { hook: hookPath, bash: "bash", timeoutMs: 10000 });
  const queued = [];
  const agent = { id: "sess_dsh_1", followup: (m) => queued.push(m) };
  await handlers["session/event"]("sess_dsh_1", { type: "assistant/message", data: { message: { role: "assistant", content: [{ type: "text", text: "SUMMONAIKIT HARNESS RECEIPT\n- Understand: x" }] } } });
  await handlers["agent/turn-stopping"]({ agent });
  assert.equal(queued.length, 0);
});

test("hook inexistente en config -> ningun throw, logger.warn, decision intacta", async () => {
  const handlers = {};
  let warned = 0;
  const ctx = { on: (ev, fn) => { handlers[ev] = fn; }, logger: { warn: () => { warned++; } } };
  await apply(ctx, { hook: "C:/no/existe.sh", bash: "bash", timeoutMs: 2000 });
  const agent = { id: "sess_dsh_1" };
  const decision = await handlers["agent/pre-step"](
    { agent, step: 1, messages: [{ role: "user", source: { kind: "user" }, content: [{ type: "text", text: "hola" }] }] },
    async () => ({ kind: "enter", messages: [{ role: "user", content: [{ type: "text", text: "hola" }] }] }),
  );
  assert.equal(decision.messages.length, 1);
  assert.ok(warned > 0);
});

test("orden: un tools/result con hook lento + turn-stopping -> el fake registra PostToolUse ANTES del Stop (cola por sesion)", async () => {
  const log = mkdtempSync(join(tmpdir(), "dsh-order-"));
  const logPath = join(log, "order.log");
  process.env.FAKE_HOOK_LOG = logPath;
  process.env.FAKE_HOOK_DELAY_MS = "300";
  try {
    const handlers = {};
    const ctx = { on: (ev, fn) => { handlers[ev] = fn; }, logger: { warn() {} } };
    await apply(ctx, { hook: hookPath, bash: "bash", timeoutMs: 10000 });
    const agent = { id: "sess_dsh_1", followup: () => {} };
    // tools/result con hook que tarda 300 ms (via env) + turn-stopping inmediato.
    const probe = { name: "subagent", arguments: { description: "Verify docstring in app.py" } };
    // Deliberadamente NO await del tools/result: dispara la cola; el Stop la espera.
    handlers["tools/result"]({ agent, name: probe.name, arguments: probe.arguments });
    await handlers["agent/turn-stopping"]({ agent });
    const lines = readFileSync(logPath, "utf8").trim().split("\n").filter(Boolean);
    assert.ok(lines.length >= 2, `esperaba al menos 2 llamadas, hay ${lines.length}`);
    const postIdx = lines.findIndex((l) => l === "PostToolUse");
    const stopIdx = lines.findIndex((l) => l === "Stop");
    assert.ok(postIdx !== -1, "falta PostToolUse");
    assert.ok(stopIdx !== -1, "falta Stop");
    assert.ok(postIdx < stopIdx, "el PostToolUse debe correr ANTES del Stop (cola por sesion)");
  } finally {
    delete process.env.FAKE_HOOK_LOG;
    delete process.env.FAKE_HOOK_DELAY_MS;
  }
});

test("Gap1: tools/result de un HIJO se re-acredita a la MADRE con la sesion y el rol del spawn", async () => {
  const log = mkdtempSync(join(tmpdir(), "dsh-gap1-"));
  const fullLog = join(log, "full.log");
  process.env.FAKE_HOOK_FULL_LOG = fullLog;
  try {
    const handlers = {};
    const ctx = { on: (ev, fn) => { handlers[ev] = fn; }, logger: { warn() {} } };
    await apply(ctx, { hook: hookPath, bash: "bash", timeoutMs: 10000 });
    const agent = { id: "sess_mother", followup: () => {} };
    handlers["agent/created"]({ agent: { id: "sess_mother" } });
    // 1) El padre lanza un subagente implementer -> result.value.subagentId = hijo.
    const spawn = { name: "subagent", arguments: { description: "Add docstring to app.py", prompt: "x" }, agent: "sess_mother" };
    await handlers["tools/result"](spawn, { isError: false, value: { kind: "continuable", subagentId: "sess_child" } });
    // 2) El hijo edita un archivo -> llega con agent = sess_child (su propia sesion).
    const childEdit = { name: "edit", arguments: { file_path: "app.py", old_string: "a", new_string: "b" }, agent: "sess_child" };
    await handlers["tools/result"](childEdit, { isError: false, value: { path: "app.py" } });
    // Drena la cola por sesion. Corremos hasta que full.log tenga 2 lineas (spawn + edit)
    // o el timeout; dsh/fork en Windows puede tardar mas que 50ms.
    const deadline = Date.now() + 4000;
    while (Date.now() < deadline) {
      try { if (readFileSync(fullLog, "utf8").trim().split("\n").filter(Boolean).length >= 2) break; } catch {}
      await new Promise((r) => setTimeout(r, 50));
    }
    const lines = readFileSync(fullLog, "utf8").trim().split("\n").filter(Boolean);
    const postLines = lines.filter((l) => JSON.parse(l).hook_event_name === "PostToolUse");
    // El edit del hijo debe traducirse a Edit con session_id de la MADRE y agent_type=implementer.
    const childPost = postLines.find((l) => JSON.parse(l).tool_name === "Edit");
    assert.ok(childPost, "falta el PostToolUse del edit del hijo");
    const cp = JSON.parse(childPost);
    assert.equal(cp.session_id, "sess_mother", "el edit del hijo debe acreditarse a la sesion de la madre");
    assert.equal(cp.agent_type, "implementer", "debe llevar el rol del spawn");
    assert.equal(cp.tool_input.file_path, "app.py");
  } finally {
    delete process.env.FAKE_HOOK_FULL_LOG;
  }
});

test("Gap2: turn-stopping del padre mientras hay hijos vivos NO envia Stop; al disponerse el hijo si", async () => {
  const log = mkdtempSync(join(tmpdir(), "dsh-gap2-"));
  const fullLog = join(log, "full.log");
  process.env.FAKE_HOOK_FULL_LOG = fullLog;
  try {
    const handlers = {};
    const ctx = { on: (ev, fn) => { handlers[ev] = fn; }, logger: { warn() {} } };
    await apply(ctx, { hook: hookPath, bash: "bash", timeoutMs: 10000 });
    const parent = { id: "sess_mother", followup: (m) => queued.push(m) };
    const queued = [];
    handlers["agent/created"]({ agent: { id: "sess_mother" } });
    // Padre lanza un subagente continuable.
    await handlers["tools/result"]({ name: "subagent", arguments: { description: "Verify docstring in app.py", prompt: "x" }, agent: "sess_mother" }, { isError: false, value: { kind: "continuable", subagentId: "sess_child_v" } });
    assert.equal(queued.length, 0);
    // Turn-stopping del padre MIENTRAS el hijo vive -> NO debe llegar Stop ni followup.
    await handlers["agent/turn-stopping"]({ agent: parent });
    assert.equal(queued.length, 0, "no debe followup con hijo vivo");
    // El hijo se dispone -> libera al padre.
    handlers["agent/disposed"]({ agent: { id: "sess_child_v" } });
    await handlers["agent/turn-stopping"]({ agent: parent });
    assert.ok(queued.length === 1, "el segundo turn-stopping (sin hijos) debe hacer followup");
    assert.match(queued[0].content[0].text, /SUMMONAIKIT HARNESS GATE/);
  } finally {
    delete process.env.FAKE_HOOK_FULL_LOG;
  }
});
