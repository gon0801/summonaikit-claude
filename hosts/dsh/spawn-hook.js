// hosts/dsh/spawn-hook.js — ejecuta el hook bash con el payload por stdin. Fail-open (D3).
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";

export function runHook({ hook, payload, env = {}, timeoutMs = 20000, bash = "bash", _bashArgs, cwd }) {
  return new Promise((resolve) => {
    if (!_bashArgs && !existsSync(hook)) return resolve({ ok: false, error: `hook no existe: ${hook}` });
    const args = _bashArgs ?? [hook];
    let child;
    try {
      // claude r3 PR #86 (D2: "no por variables heredadas"): no heredar las senales
      // de identidad de otros hosts. Un dsh lanzado desde una terminal de Claude Code
      // (CLAUDECODE=1) o Grok (GROK_HOOK_EVENT) haria que el hook clasificara
      // HOST=claude/grok y compartiera state/ con ese host.
      const childEnv = { ...process.env, SUMMONAIKIT_HOOK_TARGET: "dsh", ...env };
      for (const key of ["CLAUDECODE", "CLAUDE_SESSION_ID", "CLAUDE_PROJECT_DIR", "GROK_HOOK_EVENT", "GROK_SESSION_ID", "GROK_WORKSPACE_ROOT", "ZCODE_SESSION_ID", "ZCODE_PROJECT_DIR", "SUMMONAIKIT_INTERNAL_GENERATION", "SUMMONAIKIT_HOOK_PHASE"]) delete childEnv[key];
      child = spawn(bash, args, { env: childEnv, windowsHide: true, ...(cwd ? { cwd } : {}) });
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
    // Fail-open (kimi r3 PR #86): si el hook muere sin drenar stdin y el payload es
    // grande, child.stdin.emite 'error' (EPIPE/EOF); sin listener es un
    // uncaughtException que crashea el host de dsh (D3 prohíbe trabar dsh). Se traga;
    // el 'close'/'error' del child ya resuelve fail-open abajo.
    child.stdin.on("error", () => {});
    child.stdin.end(JSON.stringify(payload));
  });
}
