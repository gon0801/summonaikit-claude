// hosts/dsh/test/spawn-hook.test.js — runHook con un hook falso. Fail-open (D3).
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
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
test("bash inexistente -> fail-open (sin throw/rejection)", async () => {
  const r = await runHook({ hook, payload: { hook_event_name: "Stop" }, bash: "C:/no/existe/bash.exe", timeoutMs: 2000 });
  assert.equal(r.ok, false); assert.match(r.error, /ENOENT|no existe|not found/i);
});
test("runHook corre en el cwd de la sesion (qwen r2 PR #86: el hook resuelve el proyecto por pwd)", async () => {
  const dir = mkdtempSync(join(tmpdir(), "dsh-cwd-"));
  const r = await runHook({ hook, payload: { hook_event_name: "Stop" }, _bashArgs: ["-c", "pwd"], cwd: dir, timeoutMs: 10000 });
  assert.equal(r.ok, true);
  assert.ok(r.stdout.includes("dsh-cwd-"), `pwd de la sesion esperado, dio: ${r.stdout.trim()}`);
});
test("hook que muere sin leer stdin + payload grande -> fail-open (sin throw/rejection, kimi r3)", async () => {
  const big = "x".repeat(2 * 1024 * 1024);
  const r = await runHook({ hook: "ignored", payload: { hook_event_name: "Stop", last_assistant_message: big }, _bashArgs: ["-c", "exit 0"], timeoutMs: 5000 });
  assert.equal(r.ok, true);
});
test("no hereda senales de identidad de otros hosts (claude r3 PR #86, D2)", async () => {
  const r = await runHook({ hook: "ignored", payload: { hook_event_name: "Stop" }, env: { CLAUDECODE: "1", GROK_HOOK_EVENT: "user_prompt_submit" }, _bashArgs: ["-c", "test -z \"$CLAUDECODE\" && test -z \"$GROK_HOOK_EVENT\" && echo STRIPPED"], timeoutMs: 10000 });
  assert.equal(r.ok, true);
  assert.match(r.stdout, /STRIPPED/);
});
test("timeout -> fail-open con error declarado", async () => {
  const r = await runHook({ hook, payload: { hook_event_name: "Stop" }, timeoutMs: 1, _bashArgs: ["-c", "sleep 1"] });
  assert.equal(r.ok, false); assert.match(r.error, /timeout/i);
});
