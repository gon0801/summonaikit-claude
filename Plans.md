# summonaikit-claude — Plans.md

Creado: 2026-08-08
Alcance: hacerse cargo del hook que gatea cada turno de Claude Code — pruebas
propias, instalación por reemplazo, y cierre de los agujeros que hoy lo vuelven
un control decorativo. Contrato de producto y premisas medidas:
`docs/spec/00-project-spec.md`.

**Contrato de datos:** `not_observed != absent`. Lo que no se pudo observar se
marca `unknown`, nunca se afirma como ausente.

---

## Phase 0: Higiene urgente (independiente del resto)

Purpose: cerrar lo que ya es un problema hoy y no depende de ninguna decisión de
diseño. Si el plan se cancelara entero, esta fase igual debe correr.

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 0.1 | `[Guardrail]` `[lane:gate]` `[tdd:skip:system-acl-not-unit-testable]` Quitar `Modify` de `CodexSandboxUsers` y del SID huérfano `S-1-5-21-…-2159037359` sobre `~/.claude/hooks/` y `~/.claude/hooks/state/`. Hoy una identidad **aislada** puede reescribir el script que corre SIN sandbox en cada turno, o plantar `agents_seen=implementer,verifier,reviewer` y anular el gate | `icacls` sobre ambas rutas ya no lista `Modify` para esas identidades; `Gon\ehven`, `SYSTEM` y `Administrators` conservan su acceso; Claude Code arranca y un turno normal corre sin error tras el cambio | - | cc:完了 [d9057b0] |
| 0.2 | `[Guardrail]` `[lane:gate]` `[tdd:skip:system-acl-not-unit-testable]` Quitar `Modify` de `CodexSandboxUsers` y del SID huérfano sobre **`~/.claude` la raíz**: ahí está el otorgamiento explícito `(OI)(CI)` que midió la 0.1 — en `hooks/` solo se heredaba. Mientras siga, esas identidades escriben `settings.json` y **desregistran** el hook: el gate desaparece sin tocar el archivo, el mismo efecto que la 0.1 cerró por la otra vía | `tools/hook-acl.ps1 -Path "$HOME/.claude"` sale 0 **al terminar la corrección**; `settings.json` y `settings.local.json` dejan de ser escribibles por esas identidades; ningún SID no resoluble conserva ACE en `~/.claude`, `AppData`, `AppData\Local` ni `%TEMP%`; un archivo creado en `%TEMP%` y movido a `~/.claude/state/` NO arrastra cuentas borradas (prueba directa del vector A7-bis); un turno normal corre sin error y una tarea delegada al sandbox (`codex-companion.sh`) sigue funcionando. **No se exige que la auditoría se MANTENGA en 0**: A7-bis lo vuelve imposible de garantizar — ese vector se detecta, no se previene | 0.1 | cc:完了 [e19a739] |
| 0.3 | `[Guardrail]` `[lane:fast]` `[tdd:required]` El heal verifica el **REGISTRO**, no solo el contenido: si `settings.json` deja de apuntar al hook, el archivo puede estar perfecto y el gate no existir. Es el modo de falla más silencioso del sistema y hoy nada lo detecta | Fixture con `settings.json` sin la ruta del harness ⇒ el heal lo reporta fuerte y sale 0 (fail-open); fixture con el registro presente ⇒ silencio | - | cc:TODO |

## Phase 1: Red de seguridad antes de tocar nada

Purpose: hoy el hook tiene CERO pruebas de comportamiento. Construirlas contra el
archivo VIVO, en solo-lectura, es lo que vuelve segura cualquier sustitución
posterior — y tiene valor aunque el resto del plan se cancele.

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 1.1 | `[Setup]` `[lane:fast]` `[tdd:skip:tooling-setup]` Esqueleto del repo: runner de tests, `bash -n` sobre el hook, `HOME` y directorio de hooks aislados por test (Core Rule 4). Se copia el molde ya probado de `C:\dev\summonaikit-kimi\tests\` | `bash tests/run.sh` sale 0 con el repo vacío de lógica; el runner falla si `bash -n` falla; ningún test escribe fuera de su tmpdir | - | cc:TODO |
| 1.2 | `[Test]` `[lane:gate]` `[tdd:required]` **Arnés de salida dorada**: capturar los payloads JSON reales de las 3 fases y registrar stdout + exit code del archivo VIVO para N escenarios (armado/sin armar, evidencia completa/incompleta, ciclos de revisión, presupuesto agotado). Es el paso de mayor valor del plan: sin esto, cualquier reemplazo es a ciegas | Existe una línea base reproducible; re-correrla contra el archivo vivo sin cambios da resultado idéntico; el arnés jamás escribe en `~/.claude/` | 1.1 | cc:TODO |
| 1.3 | `[Test]` `[lane:gate]` `[tdd:required]` Suite de comportamiento sobre la semántica ACTUAL del gate: armado por sentinel, evidencia de tools, secuencia de roles, recibo, presupuesto de 2 ciclos, y las salidas por target (`claude` vs `cursor`) | Cada gate tiene al menos un caso que pasa y uno que bloquea; mutar la condición de cada gate hace fallar su test (mutation-test declarado en el reporte) | 1.2 | cc:TODO |

## Phase 2: Adopción

Purpose: mover el archivo a control propio sin ventana en la que el harness quede
roto o sin gate.

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 2.1 | `[Feature]` `[lane:gate]` `[tdd:required]` La fuente del repo es el archivo vivo, byte a byte, más un **marcador de identidad** en línea fija (`# SAIKIT-CLAUDE-OWNED <repo> <version>`). Sin el marcador no hay forma de distinguir "nuestro" de "del vendor" salvo por hash del archivo entero, que cambia con cada edición legítima | El arnés de 1.2 da salida idéntica entre la fuente del repo y el archivo vivo en TODOS los escenarios; el marcador está presente y es detectable por `grep` de una línea | 1.3 | cc:TODO |
| 2.2 | `[Setup]` `[lane:gate]` `[tdd:required]` Instalador por reemplazo con **tres estados**: *nuestro* ⇒ verificar/reparar; *vendor conocido* (hash en manifiesto) ⇒ archivar y reemplazar; *desconocido* ⇒ NO tocar y reportar fuerte. Escritura atómica: `bash -n` sobre temporal y recién ahí `mv`. Backup fechado | Destino desconocido ⇒ exit ≠ 0 sin escribir; destino vendor ⇒ backup + reemplazo; destino nuestro e idéntico ⇒ no reescribe (mtime intacto); un temporal inválido nunca llega al destino; 2 corridas dejan el archivo byte-idéntico | 2.1 | cc:TODO |
| 2.3 | `[Guardrail]` `[lane:gate]` `[tdd:required]` `quality-kit`: saltear cualquier archivo que lleve el marcador de propiedad, **mergeado ANTES** de instalar lo nuestro. Dos escritores en `SessionStart` sobre la misma ruta con modelos distintos (ancla vs reemplazo) pueden dejar un archivo doblemente parcheado o truncado | Fixture con marcador ⇒ `saikit-gate-heal.ps1` lo saltea y lo dice; fixture sin marcador (`.codex`/`.cursor`/`.agents`) ⇒ se parchea igual que hoy; la batería existente sigue verde | 2.2 | cc:TODO |
| 2.4 | `[Setup]` `[lane:gate]` `[tdd:required]` Puesta en producción en dos pasos: primero staging por **override de proyecto** (`<repo>/.claude/hooks/`, que la registración ya prefiere sobre el global) en un repo descartable; después install global con `--restore-vendor` de un comando | El staging gatea turnos reales sin tocar el archivo global; `--restore-vendor` devuelve el estado previo y se prueba ANTES de instalar; tras el install global, un turno `-saikit` real bloquea y uno pelado no | 2.3, 0.3 | cc:TODO |

## Phase 3: Cerrar los agujeros

Purpose: hoy el gate es evadible con texto plano. Cada task cierra un defecto
medido, con el test que lo habría atrapado.

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 3.1 | `[Guardrail]` `[lane:gate]` `[tdd:required]` **A1** — `json_string_field` es greedy y lee el payload crudo (que incluye `tool_response`): un archivo del repo con `"subagent_type": "reviewer"` satisface el gate sin que corra ningún reviewer. Parsear con parser JSON real (el port de Kimi ya usa `python` con fallback declarado) o regex anclada al primer nivel | Payload cuyo `tool_response` contiene `"subagent_type": "reviewer"` NO registra el rol; el fixture legítimo sí; revertir el arreglo hace fallar el test | 2.4 | cc:TODO |
| 3.2 | `[Guardrail]` `[lane:gate]` `[tdd:required]` **A2** — el recibo y la pausa se buscan en el tail del transcript entero, que incluye resultados de herramientas: un archivo con `SUMMONAIKIT HARNESS PAUSED` deja pasar cualquier turno. Anclar la detección a la salida del asistente | Transcript donde esas cadenas aparecen SOLO dentro de un resultado de herramienta ⇒ el gate sigue exigiendo; escritas por el asistente ⇒ satisfacen | 3.1 | cc:TODO |
| 3.3 | `[Guardrail]` `[lane:gate]` `[tdd:required]` **A3** — `TEST_RUNNER_RE` sin fronteras de palabra: `cat pytest.log` cuenta como verificación. Mismo arreglo ya validado en el port de Kimi (Task 2.15) | `cat pytest.log` y `cat tsconfig.json` ⇒ no marcan verificado; `pytest -q` y `./node_modules/.bin/vitest run` ⇒ sí | 3.1 | cc:TODO |
| 3.4 | `[Guardrail]` `[lane:gate]` `[tdd:required]` **A4** — estado por proyecto y sin revalidar el sentinel: un turno `-saikit` abandonado sigue cobrando recibo a turnos que no lo pidieron (reproducido en vivo 2026-08-08, obligó a un borrado manual). Llavear por sesión y desarmar ante prompt sin sentinel, salvo corrección al vuelo | Dos sesiones del mismo repo no comparten estado; prompt sin sentinel desarma y el Stop siguiente no bloquea; una corrección al vuelo NO desarma; el presupuesto agotado limpia el estado | 3.1 | cc:TODO |
| 3.5 | `[Guardrail]` `[lane:fast]` `[tdd:required]` **A5** — `command_text` crudo persiste en `harness-evidence.log`: un comando con credenciales en la línea queda en claro hasta el cierre limpio, y si el turno no cierra bien, indefinidamente | Un comando con `token=`/`password=`/`://user:pass@` se registra redactado; el log conserva utilidad diagnóstica (nombre del runner detectado) | 3.1 | cc:TODO |
| 3.6 | `[Guardrail]` `[lane:fast]` `[tdd:required]` **A6** — `transcript_path` sale del payload y se hace `tail` sin acotar: primitiva de lectura de archivo arbitrario controlada por payload | `transcript_path` fuera del directorio de transcripts del host ⇒ se ignora y se reporta `unknown` (fail-open, no bloquea) | 3.1 | cc:TODO |

## Phase 4: Consolidación

Purpose: retirar lo que quedó duplicado y dejar declarado lo que cambió de dueño.

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 4.1 | `[Config]` `[lane:gate]` `[tdd:required]` Retirar de `quality-kit` **solo el target `.claude`** de los dos parches, tras días en verde. NO se borra el código del parche: `.codex` tiene rama propia (`-harness-lite`) y el sentinel aplica a `.cursor`/`.agents`; borrar las anclas de `.claude` borraría además su cobertura de tests | Los 3 perfiles restantes se siguen parcheando; la batería de `quality-kit` sigue verde con la cobertura de `.codex` verificada por separado; `.claude` ya no aparece como target | 3.6 | cc:TODO |
| 4.2 | `[Docs]` `[lane:fast]` `[tdd:skip:docs-only]` Declarar el cambio de dueño del contrato: el hook de Kimi extrae su contrato de `$HOME/.claude/hooks/summonaikit-harness.sh`, o sea de este repo. Deja de ser cierto que "Kimi sigue al vendor" — sigue a este repo. Actualizar el spec del port de Kimi y su detector de drift | El spec de `summonaikit-kimi` declara la nueva fuente; su detector de drift apunta a lo correcto; ningún documento sigue afirmando que el contrato se sigue del vendor | 2.4 | cc:TODO |
| 4.3 | `[Docs]` `[lane:fast]` `[tdd:skip:docs-only]` README: instalación, staging por override, `--restore-vendor`, y la declaración explícita de que el gate es **advisory** y no un control de seguridad (aun corregidos A1 y A2, quien controla el texto del turno puede influirlo) | Las 4 secciones existen, ningún archivo citado falta, y la limitación del gate está escrita sin eufemismos | 4.1, 4.2 | cc:TODO |

---

## Clasificación del alcance

**Required** — Phases 0 a 3. El 0 es urgente e independiente; el 1 tiene valor
aunque todo lo demás se cancele; el 2 y el 3 son el objetivo.

**Recommended (fuera de este plan, independientes):**
- Prueba real de Kimi con un turno `-saikit` en vivo: 24 tareas hechas y **cero
  turnos reales**. Responde además dos hallazgos que quedaron como preguntas.
- CI + pre-commit con detección de secretos en este repo: el archivo corre en
  cada turno; hoy nada impide instalar desde una rama sucia.

**Optional:**
- Portar el aviso post-revisión a Kimi (canal distinto: Kimi no tiene el mensaje
  de sistema de Claude).
- Adoptar los otros 3 perfiles.

**Reject:**
- **Actualizar al kit v5.** Medido 2026-08-08: mismo regex de armado sin
  fronteras (se arma con "cualquier"), mismo `json_string_field` greedy byte a
  byte, mismas 71 líneas de contrato. No arregla nada y pierde los parches.
- **Seguir el contrato del vendor "en vivo".** Su versión actual trae el mismo
  texto: seguirlo no sigue ninguna mejora. Se reemplaza por importación
  explícita bajo demanda.

## Validación del plan

- `team_validation_mode`: `subagent` — se corrieron dos perspectivas
  independientes (Arquitectura, Seguridad). **Sus hallazgos no se tomaron al pie
  de la letra:** la conclusión central de la perspectiva de Arquitectura ("el
  vendor abandonó el bash y se mudó a Python") se verificó y resultó **mal
  atribuida** — ese launcher era el runtime propio del usuario. La verificación
  independiente cambió el encuadre del plan.
- Perspectiva Skeptic: cubierta por esa misma verificación, que descartó la
  premisa original del proyecto.
- Sin lint/formatter configurado para bash en este repo ⇒ Task 1.1 incluye
  `bash -n` como piso mínimo; `shellcheck` queda como Recommended.

## 事前確認

- 事項: escritura de ACLs sobre `~/.claude/hooks/` y `~/.claude/hooks/state/`
  理由: quitar `Modify` a identidades de sandbox sobre el script que corre sin sandbox
  scope: Phase 0 / Task 0.1
- 事項: lectura de `~/.claude/settings.json` y `~/.claude/settings.local.json`
  理由: verificar que el hook sigue registrado (modo de falla silencioso) y el cableado del heal
  scope: Phase 0 / Task 0.3, Phase 2 / Task 2.4
- 事項: remoción de ACE de cuentas BORRADAS (SID no resoluble) en `~/AppData`,
  `~/AppData/Local` y `%TEMP%` — aprobado en sesión 2026-08-08
  理由: A7-bis — `%TEMP%` re-contamina `~/.claude` por `move`, y los 5 SID
  huérfanos estaban explícitos repartidos en esos tres niveles. NO se toca
  `CodexSandboxUsers`, que ahí sí escribe legítimamente
  scope: Phase 0 / Task 0.2
- 事項: escritura de ACLs sobre `~/.claude` (la RAÍZ del perfil, no solo `hooks/`)
  理由: ahí vive el otorgamiento explícito medido en la 0.1; mientras siga, el hook
  se puede desregistrar desde `settings.json` sin tocar el archivo
  scope: Phase 0 / Task 0.2
- 事項: escritura sobre `~/.claude/hooks/summonaikit-harness.sh` (el archivo que gatea cada turno)
  理由: la adopción por reemplazo es el objetivo de la Phase 2
  scope: Phase 2 / Task 2.4
- 事項: escritura sobre `C:\Users\ehven\quality-kit\saikit-gate-heal.ps1` y su batería
  理由: el skip por marcador debe mergearse antes de instalar, para no tener dos escritores
  scope: Phase 2 / Task 2.3, Phase 4 / Task 4.1
- 事項: creación de repo remoto y `git push` a `gon0801/summonaikit-claude`
  理由: regla de dejar en git + remoto todo lo tocado
  scope: Phase 1 / Task 1.1 en adelante
- 事項: descarga del kit del vendor en directorio desechable (ya ejecutada 2026-08-08)
  理由: verificar la premisa de si conviene actualizar; se hizo fuera del home y se borró
  scope: pre-plan, completado
