# Traspaso: ampliar y proteger el feature map de summonaikit

Fecha: 2026-09-06 UTC. Repo: `/Users/dn/dev/summonaikit-claude`.
HEAD al guardar: `99e8486c03c08b6fcd71d9645e9988e2de6cd39a`, rama `master`.

## Empezar aquí en la próxima sesión

El usuario quiere retomar desde esta revisión de los gaps propuestos por Kimi
entre nuestro feature map y el de pstack. Se contrastó la propuesta con los
archivos locales; **no se hizo una comparación directa con el código de
pstack**. No afirmar paridad ni atribuirle implementaciones no inspeccionadas.

La autorización inmediata fue **guardar este documento para reiniciar la
sesión**. La ampliación descrita abajo no se implementó ni se agregó a
`Plans.md`. El siguiente paso propuesto es formalizar alcance, contratos y
tareas; no arrancar siete implementaciones sin esa separación.

Antes de actuar: leer `AGENTS.md`, revisar git status, worktrees, PR abiertos
y estado actual de 18.27/18.10. No asumir que siguen como al guardar esta nota.

## Contexto y trabajo paralelo

- 18.25 y 18.26 se mergearon y desplegaron: PR #209, merge `a2ec238`, y
  PR #208, merge `d45b564`. Log, ledger y evidencia quedaron en master.
- Última verificación de cierre: CI
  [34015509720](https://github.com/gon0801/summonaikit-claude/actions/runs/34015509720)
  verde sobre `99e8486`, cuatro hosts al día y registrados, Drive 5/5,
  sello `al_dia`. Son observaciones históricas, no sustituyen un chequeo nuevo.
- El ledger tenía solo **18.27 y 18.10 abiertas**. Esto no significaba que
  no existieran límites, deuda o huecos de cobertura fuera del ledger.
- Se entregaron briefs: Codex para 18.27 (Grok headless puede cerrar sin
  recibo), GLM para 18.10 (guía/README/spec/retrospectiva). El usuario indicó
  que estaban implementando; no se auditó su progreso en esta revisión.
- 18.10 puede avanzar en paralelo, pero debe incorporar el resultado real
  de 18.27 antes de cerrarse. La ampliación del map es **trabajo separado**:
  no introducirla silenciosamente en 18.10.
- 16.7 quedó opcional y no ejecutada por decisión explícita; no es una tarea
  obligatoria olvidada.

## Artefactos que no se deben confundir

- Skill local: `.cursor/skills/verify-summonaikit/SKILL.md`.
- Controlador: `.cursor/skills/verify-summonaikit/scripts/control-summonaikit`.
- Índice y fichas: `.cursor/skills/verify-summonaikit/features/`.
- `verify/`: mapa en español, Drive pytest, Evidence y sello; **complementa**
  la skill. No borrarlo, sustituirlo ni confundir su cobertura con la de esta.
- La skill contiene cuatro fichas: `install-guardian`, `gate-turn`,
  `audit-ledger`, `check-deploy-log`; cuatro comandos `drive-*`.

## Hallazgos locales previos a los siete puntos

1. **La skill no está versionada.** `git ls-files
   .cursor/skills/verify-summonaikit` devolvió cero archivos. Un test de CI
   no puede proteger material que no llega al checkout del CI. Propuesta:
   versionar selectivamente instrucciones, controlador y fichas; excluir
   `.run/`, artefactos de ejecución y secretos. No agregar todo `.cursor/`.
2. **El drive del gate no afirma la semántica prometida.**
   `cmd_drive_gate_scenario` solo exige exit 0 y el encabezado
   `=== escenario ...`. No comprueba ausencia de estado en unarmed ni
   contrato y estado en armed. La ficha sí lo pide. `verify/test_drive.py`
   ya tiene aserciones más fuertes; esa cobertura no vuelve correcto al
   controlador por delegación. Reutilizar criterios sin sustituir drives
   de superficie por una suite unitaria.
3. Un artefacto JSON por sí solo no arregla lo anterior: primero deben
   existir observaciones y aserciones que distingan la regresión del verde.

## Los siete puntos de Kimi, con la revisión incorporada

### 1. Descubrimiento y dispatch genérico

Agregar `list-features` (ID estable ↔ ficha) y `drive <id>` al controlador.
Candado permanente: entrada del índice sin ejecutor o ejecutor de feature
huérfano ⇒ rojo. Distinguir ejecutores públicos de helpers internos.
Una feature bloqueada también tiene ejecutor: reporta la precondición
incumplida; no desaparece del inventario.

### 2. Evidencia machine-readable

Cada intento produce un directorio propio con `steps.jsonl` (acción y
resultado observado) y `summary.json`. Abarca los cuatro drives y los nuevos.
Exit 0 con pasos vacíos ⇒ drive inválido, nunca verde.

Ajustes necesarios: esquema validado, conteos derivados de pasos, aserciones
esperadas presentes, coherencia entre summary y exit. Un solo paso trivial
no acredita toda la feature. Distinguir PASS, FAIL observado y `unknown`
por falta de observación según AGENTS.md. Fijar cómo se representan BLOCKED
y MISSING sin convertirlos en PASS ni esconder fallos observados.

### 3. Contrato de las fichas y lint

Exigir en `features/README.md`: H1 y descripción, exactamente cuatro H2 en
orden (`Sub-features`, `How to get to it (user POV)`,
`Driving it with control-summonaikit`, `Gotchas`), `Preconditions:` al
comienzo de la sección de ejecución, y acción → comando exacto → observable.

Corrección a la premisa: **las cuatro fichas ya tienen las secciones
ordenadas y Preconditions**. Falta el lint permanente y formalizar los
pares de acción/comando/observable. Un lint de forma no demuestra conducta.

### 4. El fallo también es evidencia

Conservar artefactos rojos y reportarlos como fallos medidos; cada reintento
debe quedar identificado, sin ocultar corridas descartadas.

Cleanup ya conserva `artifacts/`, pero hoy repetir el mismo drive dentro
del mismo run sobrescribe su archivo. Hace falta ID de intento, no solo ID
de launch. Además, `set -e` puede cortar antes de `rc=$?` y evitar el reporte
explícito del fallo: corregir el ejecutor y probar ese camino, no solo poner
una prohibición en el README. No almacenar secretos en la evidencia.

### 5. Mantenimiento con ejecutor

Kimi propuso adelantar `maintain-verification-skill` de pstack o un candado
ligado al cierre de filas. Recomendación local: el candado automático, sin
importar otra skill por ahora.

Definir un inventario de superficies públicas instalables/ejecutables y
exclusiones con razón. Cruzarlo con el map en CI, no depender únicamente de
que el líder recuerde actualizarlo. No exigir una feature por cada helper
de `tools/`; permitir que una feature cubra varias herramientas.

### 6. Ampliar cobertura por grupos

Inventario propuesto por Kimi, a contrastar antes de llamarlo «total»:

- `saikit-merge` (18.4), con gh falso en sandbox, usando el patrón de
  `tests/test_saikit_merge.sh` sin presentar simulación como GitHub vivo.
- `saikit-postmerge` (18.5).
- `setup-autopilot` (18.7), incluidas las cinco preguntas.
- `ci-minimo` (18.8).
- Párrafo autopilot del contrato (18.6), vía golden-harness.
- Install multi-host grok/dsh/codex y check-hook-registration.
- Check-secrets y capture-payloads, siempre aislados.
- `merge-happy-path` vivo, como entrada bloqueada cuando corresponda.

Correcciones:

- El setup solo lee respuestas si `[ -t 0 ]`: un pipe con stdin scripteado
  NO ejercita las preguntas. Usar PTY para la interacción; los flags prueban
  otra superficie y los defaults sin TTY deben distinguirse.
- La skill actual dice que no usa mocks. Al introducir gh falso, documentar
  explícitamente simulación de dependencias vs medición real del host.
- 18.26 **ya está cerrada con límite**: el sello se registra en el hijo,
  pero la captura no acredita vínculo padre-hijo. No transferir sello,
  reviewer o logs a una sesión elegida por mtime/verified. El recorrido
  medido conserva merge manual; no afirmar que el sello sigue sin existir.
- La cuota de Claude es una precondición temporal: verificarla al ejecutar,
  no conservar indefinidamente «bloqueado por cuota» como hecho actual.
- Los escenarios simulados no habilitan la afirmación «merge vivo probado».

### 7. Doctor granular

Reportar requisitos por feature: herramientas, fixtures y acceso a gh/red
cuando corresponda. MISSING/BLOCKED debe afectar solo a sus dependientes;
`doctor.json` puede expresar el detalle y el estado agregado.

La seguridad de aislamiento sigue siendo global: una ruta al perfil vivo
debe impedir ejecutar, no ser solo un aviso. El doctor de sandbox no prueba
los registros o sellos del operador; separar ámbitos y no leer perfiles
vivos como parte de los drives por defecto.

## Secuencia recomendada, todavía no implementada

1. Versionado selectivo, inventario público, dispatch y lint.
2. Contrato común de evidencia, aserciones reales y conservación de intentos.
3. Doctor granular y drives adicionales en grupos independientes.

Cada protección requiere regresión y mutación discriminante. Elegir primero
el esquema común: lanzar muchos drives en paralelo antes de fijarlo provoca
reescrituras y choques. Una vez estable, repartir archivos por feature.

## Límites operativos para retomar

- Trabajar en worktrees separados. El reflog de la entrega anterior mostró
  cambios de rama en un checkout compartido; no repetirlo.
- No tocar las áreas de los implementadores activos sin coordinar.
- No modificar `Plans.md` ni abrir nuevas filas como efecto implícito de
  esta nota: formalizar la ampliación con el usuario/líder.
- No borrar ni reemplazar la skill existente ni `verify/`.
- No instalar, registrar hooks ni modificar perfiles vivos para medir.
- No importar pstack, instalar dependencias o ejecutar merges externos por
  el solo hecho de que aparezcan en una propuesta de cobertura.
- Estado al guardar: `.cursor/` y `.qwen/` eran preexistentes sin seguimiento;
  preservarlos. Este documento se guarda localmente, sin commit/push en
  este turno, para que la sesión siguiente lo encuentre.

Mensaje sugerido al reiniciar:

> Lee docs/traspaso-feature-map-2026-09-06.md y AGENTS.md. Retomemos la
> ampliación del feature map desde la propuesta revisada, comprobando primero
> el estado de 18.27 y 18.10 y sin interferir con sus implementadores.
