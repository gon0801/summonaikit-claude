// hosts/dsh/test/translate.test.js — puro, sobre los fixtures de 15.1.
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

test("tools/result de subagent -> PostToolUse Task con subagent_type (rol inferido del texto, 15.1)", () => {
  const ev = fx("tools-result-subagent.jsonl")[0];
  const p = toPostToolUse({ sessionId: "s", cwd: "c", ...ev.payload });
  assert.equal(p.hook_event_name, "PostToolUse");
  assert.equal(p.tool_name, "Task");
  assert.match(p.tool_input.subagent_type, /^(implementer|verifier|reviewer|adversary)$/);
  assert.equal(p.tool_input.subagent_type, "implementer"); // "Add docstring..." -> implementer
  assert.equal(p.tool_input.description, ev.payload.arguments.description);
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

test("tools/result de subagent 'Verify' -> verifier (rol por texto)", () => {
  const ev = fx("tools-result-subagent.jsonl")[1];
  const p = toPostToolUse({ sessionId: "s", cwd: "c", ...ev.payload });
  assert.equal(p.tool_name, "Task");
  assert.equal(p.tool_input.subagent_type, "verifier"); // "Verify docstring..." -> verifier
});

test("subagent con descripcion ambigua (add + verify) -> undefined (fail-safe, codex r1)", () => {
  const p = toPostToolUse({ sessionId: "s", cwd: "c", name: "subagent", arguments: { description: "Add and verify the change", prompt: "x" } });
  assert.equal(p, undefined);
});
test("subagent sin keyword de rol -> undefined (fail-safe)", () => {
  const p = toPostToolUse({ sessionId: "s", cwd: "c", name: "subagent", arguments: { description: "Do the thing", prompt: "x" } });
  assert.equal(p, undefined);
});
test("pre-step con reporte de subagente (source.kind != user) -> undefined", () => {
  const p = toUserPromptSubmit({ sessionId: "s", cwd: "c", step: 3, messages: [{ role: "user", source: { kind: "subagent-settled", senderSessionId: "x" }, content: [{ type: "text", text: "Background subagent … finished" }] }] });
  assert.equal(p, undefined);
});
