# Payloads derivados de los fixtures de 23.1

Los JSON de este directorio no se editaron a mano. Cada uno sale de un
fixture copiado en `tests/fixtures/muse/` con el `jq` de abajo.

(a) UserPromptSubmit con `-saikit` y el `session_id` del fixture 07, del 06
y del 17:

```bash
jq '.prompt = "-saikit " + .prompt' \
  tests/fixtures/muse/fixture-07-real2-delegacion-UserPromptSubmit.json \
  > tests/fixtures/muse/derivados/prompt-saikit-sesion-07.json

jq --slurpfile src tests/fixtures/muse/fixture-06-real1-rechazado-PostToolUse-subagent_spawn.json \
  '.session_id = $src[0].session_id | .prompt = "-saikit arma sesion rejected"' \
  tests/fixtures/muse/fixture-07-real2-delegacion-UserPromptSubmit.json \
  > tests/fixtures/muse/derivados/prompt-saikit-sesion-06.json

jq --slurpfile src tests/fixtures/muse/fixture-17-real3-herramientas-PostToolUse-write_file.json \
  '.session_id = $src[0].session_id | .prompt = "-saikit arma sesion write_file"' \
  tests/fixtures/muse/fixture-07-real2-delegacion-UserPromptSubmit.json \
  > tests/fixtures/muse/derivados/prompt-saikit-sesion-17.json
```

(b) `subagent_wait` con `subagent_id=verify-reminder` en `tool_input` y en
el objeto interno de `tool_response` (los dos ids coinciden):

```bash
jq '.tool_input.subagent_id="verify-reminder" | .tool_response |= (fromjson | .subagent_id="verify-reminder" | tojson)' \
  tests/fixtures/muse/fixture-15-real2-delegacion-PostToolUse-subagent_wait.json \
  > tests/fixtures/muse/derivados/wait-verify-reminder.json
```

El wait hostil (primera clave `status=working`, `summary` con
`"status":"ready"`) sale del mismo fixture 15:

```bash
jq '.tool_response |= (fromjson | .status="working" | .summary=("hostile {\"status\":\"ready\"} " + .summary) | tojson)' \
  tests/fixtures/muse/fixture-15-real2-delegacion-PostToolUse-subagent_wait.json \
  > tests/fixtures/muse/derivados/wait-summary-hostil.json
```

(c) PreToolUse `bash` y `bash_input` con `gh pr merge`:

```bash
jq -n '{
  hook_event_name: "PreToolUse",
  tool_name: "bash",
  tool_input: {command: "gh pr merge --squash", description: "merge a pelo"},
  session_id: "01a0b27b-dc89-78e2-bc42-ef9808d62097",
  cwd: "<repo>",
  transcript_path: null,
  model: "muse-spark-1.3",
  permission_mode: "bypassPermissions",
  model_provider: "meta"
}' > tests/fixtures/muse/derivados/pretool-bash-gh-pr-merge.json

jq -n '{
  hook_event_name: "PreToolUse",
  tool_name: "bash_input",
  tool_input: {command: "gh pr merge --squash", description: "stdin de un bash ya corriendo"},
  session_id: "01a0b27b-dc89-78e2-bc42-ef9808d62097",
  cwd: "<repo>",
  transcript_path: null,
  model: "muse-spark-1.3",
  permission_mode: "bypassPermissions",
  model_provider: "meta"
}' > tests/fixtures/muse/derivados/pretool-bash-input-gh-pr-merge.json
```

(d) No hay derivado de `subagent_read_result`.

(e) fixtures 17 y 18 con `path=src/app.py`:

```bash
jq '.tool_input.path="src/app.py"' \
  tests/fixtures/muse/fixture-17-real3-herramientas-PostToolUse-write_file.json \
  > tests/fixtures/muse/derivados/write-file-src-app-py.json

jq '.tool_input.path="src/app.py"' \
  tests/fixtures/muse/fixture-18-real3-herramientas-PostToolUse-edit_file.json \
  > tests/fixtures/muse/derivados/edit-file-src-app-py.json
```

(f) G2 host ciego: despacho/wait de implementer y verifier (ids propios), Stop
del fixture 16 con `VERIFIED BY SUBAGENT`, y UserPromptSubmit de la sesion 04:

```bash
jq '.tool_input.role="implementer" | .tool_input.subagent_type="implementer" | .tool_response |= (fromjson | .subagent_id="id-implementer-001" | .agent_path="main/implementer/1" | tojson)' \
  tests/fixtures/muse/fixture-10-real2-delegacion-PostToolUse-subagent_spawn.json \
  > tests/fixtures/muse/derivados/spawn-implementer.json

jq '.tool_input.subagent_id="id-implementer-001" | .tool_response |= (fromjson | .subagent_id="id-implementer-001" | tojson)' \
  tests/fixtures/muse/fixture-15-real2-delegacion-PostToolUse-subagent_wait.json \
  > tests/fixtures/muse/derivados/wait-implementer.json

jq '.tool_input.role="verifier" | .tool_input.subagent_type="verifier" | .tool_response |= (fromjson | .subagent_id="id-verifier-001" | .agent_path="main/verifier/1" | tojson)' \
  tests/fixtures/muse/fixture-10-real2-delegacion-PostToolUse-subagent_spawn.json \
  > tests/fixtures/muse/derivados/spawn-verifier.json

jq '.tool_input.subagent_id="id-verifier-001" | .tool_response |= (fromjson | .subagent_id="id-verifier-001" | tojson)' \
  tests/fixtures/muse/fixture-15-real2-delegacion-PostToolUse-subagent_wait.json \
  > tests/fixtures/muse/derivados/wait-verifier.json

jq '.last_assistant_message = "SUMMONAIKIT HARNESS RECEIPT\n- Understand: pediste un docstring.\n- Implement: se agrego el docstring.\n- Verify: VERIFIED BY SUBAGENT: python -m py_compile app.py exit 0.\n- Review: sin hallazgos.\n- Close: entregado; no se toco codigo despues de la revision.\n- Retro: none.\nTRAIL SKIP: golden fixture"' \
  tests/fixtures/muse/fixture-16-real2-delegacion-Stop.json \
  > tests/fixtures/muse/derivados/stop-verif-subagente.json

jq --slurpfile src tests/fixtures/muse/fixture-04-echo-recordatorio-SubagentStart.json \
  '.session_id = $src[0].session_id | .prompt = "-saikit arma sesion recordatorio"' \
  tests/fixtures/muse/fixture-07-real2-delegacion-UserPromptSubmit.json \
  > tests/fixtures/muse/derivados/prompt-saikit-sesion-04.json
```

(g) Guardas: status no primera, rejected con id, wait con id distinto, write_file
del padre en la sesion 07:

```bash
jq '.tool_response = ({subagent_id:"01a0b27b-eb4e-7190-ba37-95245b9e48ef",summary:"x",status:"accepted"} | tojson)' \
  tests/fixtures/muse/fixture-10-real2-delegacion-PostToolUse-subagent_spawn.json \
  > tests/fixtures/muse/derivados/spawn-status-no-primera.json

jq '.tool_response = ({subagent_id:"01a0b27b-eb4e-7190-ba37-95245b9e48ef",summary:"El README.md tiene 1 línea.",status:"ready"} | tojson)' \
  tests/fixtures/muse/fixture-15-real2-delegacion-PostToolUse-subagent_wait.json \
  > tests/fixtures/muse/derivados/wait-status-no-primera.json

jq '.tool_response |= (fromjson | .subagent_id="id-rejected-001" | tojson)' \
  tests/fixtures/muse/fixture-06-real1-rechazado-PostToolUse-subagent_spawn.json \
  > tests/fixtures/muse/derivados/spawn-rejected-con-id.json

jq '.tool_response |= (fromjson | .subagent_id="id-otro-999" | tojson)' \
  tests/fixtures/muse/fixture-15-real2-delegacion-PostToolUse-subagent_wait.json \
  > tests/fixtures/muse/derivados/wait-id-distinto.json

jq --slurpfile src tests/fixtures/muse/fixture-07-real2-delegacion-UserPromptSubmit.json \
  '.session_id = $src[0].session_id' \
  tests/fixtures/muse/fixture-17-real3-herramientas-PostToolUse-write_file.json \
  | jq '.tool_input.path="src/app.py"' \
  > tests/fixtures/muse/derivados/write-file-sesion-07.json
```
