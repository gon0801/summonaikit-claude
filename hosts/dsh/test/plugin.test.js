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
  assert.ok(decision.messages.some((m) => JSON.stringify(m).includes("SUMMONAIKIT HARNESS REQUIRED")));
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
