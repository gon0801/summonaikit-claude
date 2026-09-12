# Contrato: cierre headless observable (20.15–20.17)

Launcher opt-in: `tools/headless-close.sh`. Solo cubre ejecuciones que él inicia.
La invocación directa de `claude -p` / `grok -p` queda **fuera de garantia**.

## STATE_PATH (igual que el hook)

`HOOK_DIR/state/$HOST/$PROJECT_KEY/$SESSION_KEY/harness-state.env`

- `HOOK_DIR`: `$SAIKIT_HOOK_DIR` o `$HOME/.claude/hooks`
- `PROJECT_KEY=$(printf '%s' "$PROJECT_ROOT" | cksum | cut -d ' ' -f 1)`
- `SESSION_KEY`: `sed 's/[^A-Za-z0-9_-]/_/g' | cut -c1-64`
- `session_id` vacío parseado ⇒ clave `UNKNOWN`, **nunca** `sin-session`, **nunca** glob.

`session_id` sale del JSON del host (`claude -p --output-format json`;
`grok --single "PROMPT" --output-format json`: en grok 1.0.25 `-p`/`--single`
toman el prompt como valor — medido 20.17, `grok -p --output-format json "P"`
muere en clap con rc=2). 20.10 `turn1.json` prueba `session_id` top-level en
Claude.

## Recibo (seis etiquetas)

No es `agents_seen`. Es el bloque:

- `SUMMONAIKIT HARNESS RECEIPT`
- `Understand:` `Implement:` `Verify:` `Review:` `Close:` `Retro:`

en `harness-evidence.log` **o** en el campo `result` del JSON del host.

## close_type (solo observación)

El caller **no** puede pasar `close_type`. Valores:

| observación | close_type | exit |
| leftover + recibo completo | forced | 0 (limpia solo su STATE_PATH) |
| sin leftover | clean | 0 (no-op) |
| leftover sin recibo completo | incomplete | 1 (aunque host rc=0) |
| timeout | timeout | 1 |
| sin session_id / captura no observable | unknown | 3 |
| uso / binario ausente | — | 2 (nunca 0) |

Sin relanzamiento silencioso. Aislamiento: dos sesiones concurrentes, solo la
propia ruta. `--timeout` soportado. Async real no es un prompt Bash.

## Rollback

Si el launcher no corre, el comportamiento del hook no cambia. Quitar el
wrapper no deja estado a medias más allá del leftover que el host ya hubiera
escrito.
