# summonaikit-claude — Especificación de producto

Fecha: 2026-08-08

## Purpose

Hacerse cargo del hook que gatea cada turno de Claude Code: ponerlo bajo control
propio, con pruebas de comportamiento, y cerrar los agujeros que hoy lo vuelven
un control decorativo.

**NO es una migración para escapar del vendor.** Esa premisa se verificó y es
falsa (ver § Premisas verificadas). Es hacerse cargo de un archivo que en la
práctica ya es del usuario.

## Premisas verificadas (2026-08-08, no supuestas)

Estas mediciones son la base del alcance. Si alguna cambia, el plan se revisa.

1. **La versión actual del vendor no aporta nada.** Se descargó el kit v5 en un
   directorio desechable y se comparó contra el archivo vivo:
   - sigue siendo bash (520 líneas), no el launcher Python;
   - `is_engineering_task()` mantiene el MISMO regex sin fronteras de palabra:
     medido, se arma con "cual**qui**er" y "se**gui**r" por el fragmento `ui`.
     Ese es exactamente el bug que el parche del sentinel existe para tapar;
   - `json_string_field()` es idéntico byte a byte (mismo `sed` greedy);
   - el contrato son las MISMAS 71 líneas.
   ⇒ Actualizar no arregla nada y pierde los parches. **Rechazado.**
2. **El launcher Python de los snapshots era el runtime propio del usuario**
   (`summonaikit_core`, repo `gon0801/summonaikit-core`), desactivado 2026-08-03
   y borrado 2026-08-07 — no una evolución del vendor. El archivo bash vivo es
   aquello a lo que el usuario **volvió**, no un olvido.
3. **El vendor no reescribe el archivo hoy** (kit en estado `pre-uninstall`), así
   que la fragilidad de los parches por anclas dejó de ser el riesgo principal.
4. **El hook tiene CERO pruebas de comportamiento.** Las 416 verificaciones de
   `quality-kit` prueban el *parcheador*, no el hook.

## Users And Workflows

Un operador, en Windows. El hook corre en CADA `UserPromptSubmit`, `PostToolUse`
y `Stop` de Claude Code, con el payload del turno por stdin. El usuario arma el
harness escribiendo `-saikit` en el prompt; sin ese sentinel el hook no debe
crear estado ni bloquear nada.

## Core Rules

1. **Fail-open ante lo desconocido.** El hook corre en cada turno: si no puede
   medir algo, reporta y deja pasar. Un gate que bloquea sin evidencia es peor
   que ninguno. Única excepción declarada: el instalador (§ Instalación).
2. **`not_observed != absent`.** No poder mirar no es lo mismo que haber visto
   ausencia. Se reporta `unknown`, no fallo.
3. **El sentinel `-saikit` es la ÚNICA condición de armado.** El regex del vendor
   busca sus palabras clave como SUBCADENA y en español se arma solo. Esta regla
   no se re-litiga; se vuelve código propio en vez de parche por anclas.
4. **Nunca se prueba contra el estado real.** Todo test corre contra un `HOME`
   y un directorio de hooks aislados.
5. **La identidad del archivo se declara en el archivo.** Un marcador propio
   permite distinguir "esto es nuestro" de "esto es del vendor" sin depender del
   hash del archivo entero, que cambia con cada edición legítima.

## Data And Contracts

### Qué se hereda y qué se corrige

El archivo vivo (746 líneas) es la fuente inicial: el bash del vendor más dos
parches locales (`SAIKIT-SENTINEL-GATE v1`, `SAIKIT-REVIEW-NOTICE v1`). Al
adoptarlo, sus defectos pasan a ser responsabilidad propia. Los conocidos:

| # | Defecto | Efecto | Fase |
|---|---|---|---|
| A1 | `json_string_field` es greedy (`.*` inicial) y lee el payload CRUDO, que incluye `tool_response` | Un archivo del repo que contenga `"subagent_type": "reviewer"` satisface el gate de revisión sin que corra ningún reviewer | 3 |
| A2 | El recibo y la pausa se buscan en el tail del transcript entero | Un archivo con `SUMMONAIKIT HARNESS PAUSED`, o con las 6 etiquetas, deja pasar cualquier turno | 3 |
| A3 | `TEST_RUNNER_RE` sin fronteras de palabra | `cat pytest.log` cuenta como verificación (mismo hallazgo 6 ya corregido en el port de Kimi) | 3 |
| A4 | Estado llaveado por proyecto y sin revalidar el sentinel | Un turno `-saikit` abandonado sigue cobrando recibo a turnos que no lo pidieron (reproducido en vivo el 2026-08-08) | 3 |
| A5 | `command_text` crudo persiste en `harness-evidence.log` | Un comando con credenciales en la línea queda en claro en disco hasta el cierre limpio | 3 |
| A6 | `transcript_path` sale del payload y se hace `tail` sin acotar | Primitiva de lectura de archivo arbitrario controlada por payload | 3 |
| A7 | ACL: `CodexSandboxUsers` tiene `Modify` sobre el hook y su directorio de estado | Una identidad *aislada* puede reescribir el script que corre SIN sandbox en cada turno, o plantar `agents_seen` y anular el gate | 0 |

A7 es anterior e independiente del plan: se corrige primero porque es el único
que no depende de ninguna decisión de diseño.

### El contrato inyectado

Las 71 líneas de `HARNESS_CONTEXT` son el producto del vendor. **Consecuencia de
la premisa 1:** como su versión actual trae el mismo texto, seguirlo "en vivo" no
sigue ninguna mejora. El contrato pasa a ser propio, en el repo, con una
herramienta explícita para importar el del vendor si algún día cambia.

**Acoplamiento a declarar:** el hook de Kimi extrae su contrato de
`$HOME/.claude/hooks/summonaikit-harness.sh` — o sea de este archivo. Al
adoptarlo, este repo pasa a ser la fuente de verdad del contrato **para los dos
hosts**. Es coherente y deliberado, pero deja de ser cierto que Kimi "sigue al
vendor": sigue a este repo.

### Instalación

Por REEMPLAZO, no por anclas. Requisitos, cada uno por un modo de falla real:

- **Tres estados, no dos.** *Nuestro* (marcador presente) ⇒ verificar/reparar.
  *Vendor conocido* (hash en un manifiesto) ⇒ archivar y reemplazar. *Desconocido*
  ⇒ NO tocar, reportar fuerte. "No es nuestro ⇒ sobrescribir" es cómo se
  destruye en silencio un cambio legítimo.
- **Escritura atómica**: validar `bash -n` sobre un temporal y recién ahí `mv`.
  `cp` no es atómico; un archivo truncado rompe TODOS los turnos siguientes.
- **Backup fechado** antes de reemplazar.
- **Verificar el REGISTRO, no solo el contenido.** Si `settings.json` deja de
  apuntar al hook, el archivo puede estar perfecto y el gate no existir. Ese es
  el modo de falla más silencioso del sistema y hoy nada lo detecta.

### Convivencia con quality-kit

`saikit-gate-heal.ps1` aplica los dos parches a 4 perfiles (`.claude`, `.codex`,
`.cursor`, `.agents`). Dos escritores en `SessionStart` sobre la misma ruta con
modelos distintos (parche-por-ancla vs reemplazo) pueden producir un archivo
doblemente parcheado o truncado.

La costura es **por host**: quality-kit saltea cualquier archivo que lleve el
marcador de propiedad. Un condicional. `.codex`/`.cursor`/`.agents` no cambian.
Ese cambio se mergea ANTES de instalar lo nuestro.

## Non-Goals

- **No se actualiza al kit v5.** Verificado: mismos bugs, mismo contrato.
- **No se adoptan los otros 3 perfiles** en este alcance. `.codex` es una
  variante distinta con parches de otro origen. La divergencia queda declarada.
- **No se persigue que el gate sea un control de seguridad.** Es advisory: aun
  corregidos A1 y A2, quien controla el texto del turno puede influirlo. Se
  documenta; no se promete lo contrario.
- **No se borra el código de los parches de quality-kit**, solo su target
  `.claude`: el resto de perfiles depende de ellos y de su cobertura de tests.
