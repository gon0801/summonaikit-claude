// hosts/dsh/spawn-hook.js — ejecuta el hook bash con el payload por stdin. Fail-open (D3).
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";

export function runHook({ hook, payload, env = {}, timeoutMs = 20000, bash = "bash", _bashArgs, cwd }) {
  return new Promise((resolve) => {
    if (!_bashArgs && !existsSync(hook)) return resolve({ ok: false, error: `hook no existe: ${hook}` });
    const args = _bashArgs ?? [hook];
    let child;
    try {
      child = spawn(bash, args, { env: { ...process.env, SUMMONAIKIT_HOOK_TARGET: "dsh", ...env }, windowsHide: true, ...(cwd ? { cwd } : {}) });
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
