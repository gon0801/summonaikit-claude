# Auditoría del sentinel y del gate — 2026-08-13

Auditoría multi-agente sobre el **working tree** (workflow
`saikit-sentinel-audit`: 5 lentes de búsqueda independientes + batería empírica
de ciclo de vida, merge/dedup, y verificación adversarial por hallazgo con
ejecución real del hook en sandbox). 21 agentes. Resultado: **14 hallazgos
CONFIRMADOS (todos reproducidos con ejecución), 1 refutado**.

Spec auditada (del operador): *el kit se activa SOLO con el sentinel `-saikit`,
y al turno siguiente sin sentinel ya no debe estar activo*.

## Cerrados por la Phase 8 (lotes priorizados por el operador)

| ID | Sev | Hallazgo | Task |
|----|-----|----------|------|
| C1 | alta | `json_string_field` corta el valor en la primera `\"`: comillas antes de `-saikit` → no arma; corrección CON sentinel y comillas → desarma a media ceremonia; `command` entrecomillado pierde crédito de verify | 8.1 |
| C2 | alta | Sentinel grepeado sobre JSON crudo: `\n`/`\t` literales antes de `-saikit` rompen la frontera izquierda (prompt multilínea no arma / corrección multilínea desarma) | 8.1 |
| C3 | media | `command`/`tool_name`/`file_path`/`transcript_path` con lector greedy (última ocurrencia): un `"command":"pytest -q"` dentro de `tool_response` acredita `verified=1` | 8.1 |
| C4 | alta | El tail de 160 líneas mete texto de turnos ANTERIORES en `$text`: recibo viejo invierte la escotilla DELEGATED (bloquea turno legítimo); PAUSED viejo deja pasar el gate entero | 8.2 |
| C7 | media | `has_receipt_label` rechaza `**Understand**:` (markdown bold): recibo honesto bloqueado con las 6 etiquetas "faltantes" | 8.3 |
| C5 | baja | El contrato promete "run the full cycle once they reply" tras PAUSED/DELEGATED, pero la respuesta sin `-saikit` desarma por diseño (A4-c2): promesa falsa | 8.4 |

## Deuda declarada (confirmados, sin task todavía)

| ID | Sev | Hallazgo |
|----|-----|----------|
| C6 | media | `dotnet test` y `gradle` FALLANDO se acreditan como verified: `Failed!  - Failed:     1` y `FAILURE: Build failed` no matchean `FAILURE_SIGNAL_RE_CI/_CS` |
| C8 | media | Tokens de runner sin anclar acreditan por mención: `echo … pytest`, `ls tsc/` dan `verified=1` sin proceso de test |
| C9 | baja | Fallback `prompt_text="$INPUT"` (L754): un payload sin campo `prompt` puede armar por `-saikit` en CUALQUIER campo |
| C10 | baja | Frontera izquierda del sentinel acepta `/` y `-`: `docs/-saikit.md` y `--saikit` arman falso |
| C11 | baja | La frontera `[^[:alpha:]]` acepta `'`: citar el feedback del gate satisface etiquetas sin recibo |
| C12 | baja | `assistant_text_transcript` no resetea `c4`/`en_text`/`en_assistant`: valores top-level (uuid, timestamps) se filtran a `$text` |
| C13 | baja | `state/` acumula un dir por sesión para siempre; sesión armada abandonada persiste indefinidamente |
| C14 | baja | El `elif` RN (L1286) borra el aviso pendiente de otra sesión incluso desde un Stop QUE BLOQUEÓ — más allá del borde declarado ("secuencia limpia") |

**Refutado**: "assistant_text_transcript no filtra isSidechain" — el walker exige
`role:assistant` + `content[].type:text` en la forma que los sidechain reales no
tienen; no reproducible.

Repros completos (payloads exactos por hallazgo): salida del workflow, archivo
`tasks/w5c2o0wgk.output` del scratchpad de la sesión `04e00816` (efímero; los
repros que importan quedaron convertidos en casos de `tests/lib/gate_cases.sh`
por las tasks 8.1–8.3).
