# Phase 20 — cerrar residuales abordables fuera del feature map

Fecha: 2026-09-06. Base observada: `origin/master@949ca54` tras fetch.
Petición: «convertirlos en tareas explícitas, todo lo que se pueda cerrar».
**Estado: plan; 25 tareas nuevas, ninguna implementada por este cambio.**

Contrato: [spec de residuales](spec/autopilot-residuals.md), subordinada a
[spec del producto](spec/00-project-spec.md). La fila de `Plans.md` define
alcance, DoD, dependencias y estado; este documento organiza la ejecución.

## Resultado esperado

Corregir defectos acotados, acreditar recorridos que siguen sin medición y
resolver las incertidumbres que impiden nuevas garantías. No confundir cerrar
una investigación con hacer funcionar su implementación dependiente. Las
filas18.26/18.27 conservaron límites autorizados; estas son ampliaciones,
no un cambio retrospectivo de su evidencia ni de sus estados.

Clasificación: Required y Recommended están incluidos. Required define el
mínimo de aceptación; Recommended se implementa después o se retira mediante
una decisión explícita. Conditional solo se activa con el resultado positivo
nombrado; Optional exige adopción explícita. Nada se da por cerrado por pasar
el tiempo, por tener CI verde sin prueba funcional o por quedar documentado.

## Inventario completo y trazabilidad

| Origen / pendiente | Clasificación | Entrega |
|---|---|---|
| Banco de mutantes de merge puede acreditar caso siempre-rojo (18.4) | Required | 20.1 control sano antes de mutar |
| Comandos sin bash en postmerge, LISTO y liberar-lock | Required | 20.2 tres emisores, sin chmod |
| Color heredado de gh no neutralizado en postmerge (18.25) | Required | 20.3 reproducción y fix |
| backgroundTasks textual: multiline, tipos, citas y anidación (18.27) | Required | 20.4 lectura estructural |
| Lock solo de setup, merges/reverts sin exclusión local | Required | 20.5 contrato y dos procesos reales |
| Adversary carece de zona para fixtures (plan18, deuda explícita) | Recommended | 20.6 ubicación acotada y guardas |
| Pins en literales del generador sin proceso de refresh (18.24) | Recommended | 20.7 actualización revisable |
| Autorización D23 expirada, versiones/cuota/precondiciones cambiantes | Required | 20.8 preparación, no ejecución implícita |
| Registro PreToolUse presente, deny vivo no acreditado (18.11) | Required | 20.9 prueba del evento y no-ejecución |
| Happy path completo en Claude no observado (18.9/18.10) | Required | 20.10 recorrido autorizado real |
| cuidar-pr sin turno vivo; tres modos públicos | Required | 20.11 revisar, solo-hilos, cuidar |
| Sello Grok no acredita relación padre-hijo (18.26) | Required + Conditional | 20.12 investiga; 20.13 implementa si hay canal; 20.14 mide flujo |
| Teardown Grok puede omitir Stop (18.27) | Required + Conditional | 20.15 diseña; 20.16 implementa superficie; 20.17 mide |
| Escenario2 de bloqueo dsh UI desconocido (15.5) | Required + Conditional | 20.18 mide; 20.19 corrige solo defecto reproducido |
| pnpm sin packageManager / prompt corepack viejo no observado (18.24) | Recommended | 20.20 medición y política determinista |
| Costo120–230k tokens/8–18min por PR sin comparación equivalente | Recommended | 20.21 reutiliza mediciones; decisión sobre16.7 |
| Config autopilot ausente en este repo, adopción por proyecto | Optional | 20.22 exige destino y cinco opciones |
| Texto adversary y estados históricos desactualizados | Required | 20.23 reconciliación sin falsificar capturas |
| dry-run de quitar-zcode/quitar-grok ignora flag | Required | 20.24 sin escrituras, backups ni borrado |
| Cierre verificable y trazabilidad | Required | 20.25 matriz y registro post-merge |

### Lo que se conserva, aplaza o rechaza con razón

| Tema | Decisión / disparador |
|---|---|
| 16.7 receta→tier | Optional existente; no crear implementación duplicada. 20.21 debe justificar costo/latencia/calidad o demanda antes de reactivarla |
| Más runners de app | Optional por necesidad de un proyecto concreto; conservar rechazo honesto de runner no reconocido |
| Evals de recetas | Optional tras medir fidelidad actual; el disparador histórico >6 recetas ya se cumple con cuidar-pr. 20.11/20.21 entregan datos para decidir una batería, no se asume que exista |
| Auditor de worktrees / borrado del descartable | Optional por necesidad operativa; aquí se preservan worktrees y entrega al operador, sin limpieza destructiva |
| Adversary en kimi / paridad de hosts | Fuera de este repo; requiere alcance en summonaikit-kimi. El hook local no puede acreditar otro port |
| ACL Windows y carreras TOCTOU del perfil | No prometer solución shell ni prueba desde macOS/Linux; alcance separado con entorno Windows y modelo de amenaza explícito |
| Auto-merge sin sí / autorevert | Reject: decisión vigente del operador, no bugs |
| Publicar repo/cambiar plan para branch protection, Graphite/stacks, modo pegajoso | Reject: decisiones explícitas y sin necesidad nueva en este pedido |
| Sellos por mtime/ruta/task_hash, sembrar verified o relajar CI | Reject: invalidan atribución y el gate |
| Rastro/blast ausentes en smoke17 | No reabrir fix18.12: medir su uso posterior dentro de20.10 |
| Registro Codex, zcode11.6/11.8, instalación POSIX, pytest/yarn/timeout del CI | Resueltos por filas posteriores. No crear tareas por texto histórico aislado |
| Presupuesto de dos ciclos y gate advisory | Decisiones vigentes. El supervisor puede reportar incompleto, no inventar garantía universal ni reintentar trabajo silenciosamente |

Los opcionales no adoptados quedan visibles con disparador, no cuentan como
implementaciones pendientes obligatorias. No se excluye silenciosamente un
bug observado para mantener pequeño el plan.

## Orden y reparto

Primera ola de código: **20.1**, 20.3, 20.4 y20.24 son independientes en
archivos principales. 20.2 va tras20.1; 20.5 tras ambas porque cambia el mismo
tool y su banco.20.6 toca hook/perfil y se integra en serie con20.4.
20.7 y20.20 comparten generador CI: se hacen en ese orden.

20.8 prepara el laboratorio en paralelo, con presupuesto acotado y sin
lanzar llamadas externas hasta tener su alcance autorizado. Después pueden
medirse20.9,20.11,20.12,20.15 y20.18 en laboratorios separados.20.10 espera
los fixes que ejercita.20.13/20.16 no arrancan hasta una decisión técnica
positiva;20.14/20.17 necesitan sus implementaciones.20.19 solo se activa por
un fallo observado en20.18: su dependencia exige el artefacto de reproducción
FAIL, no que20.18 esté cerrada.20.18 sigue abierta hasta repetir la medición
UI con éxito; así el arreglo puede ejecutarse sin falsear un PASS previo.20.21 reutiliza las capturas, sin otra ronda cara
para conseguir números de presentación.

20.23 tiene una primera parte inmediata (frases desactualizadas) y se mantiene
abierta hasta incorporar los resultados de las tareas activas.20.25 juzga el
conjunto: si falta una medición Required, la fase queda pendiente; si una
Conditional resulta inviable, registra cancelación explícita y el límite que
permanece. No transforma `unknown` en PASS ni marca la implementación hecha.
El rango de Depends del cierre se evalúa por activación: Required exige cierre
observado; Recommended exige ejecución o decisión explícita de retirar alcance;
Conditional exige ejecución cuando fue habilitada o decisión que la cancele;
Optional exige adoptar y ejecutar, o aplazar explícitamente. Cancelar/aplazar
no usa `cc:完了` de implementación: conserva `cc:NO EJECUTADA` con su razón,
fuente de decisión y límite. Una Required bloqueada nunca se omite del rango.

### Archivos y pruebas por familia

| Tareas | Archivos previsibles / comprobación focal |
|---|---|
| 20.1–20.3/20.5 | tools/saikit-merge.sh, saikit-postmerge.sh, saikit-setup-autopilot.sh; tests/test_saikit_merge.sh, test_saikit_postmerge.sh, test_autopilot_config.sh y meta-test del banco si hace falta |
| 20.4/20.13 | hooks/summonaikit-harness.sh, tests/lib/gate_cases.sh, hook_lab.sh, test_gate_mutations.sh; consumidor merge para20.13; conservar negativos18.26 |
| 20.6 | agents/adversary.md, contrato de artefactos y gate de escrituras; tests adversary existentes y casos nuevos de propiedad |
| 20.7/20.20 | tools/saikit-ci-minimo.sh, su banco test_ci_minimo.sh y script/procedimiento de refresh; literales del generador además de workflows del repo |
| 20.8–20.12/20.14–20.15/20.17–20.18/20.21 | docs/evidence/phase-20/<tarea>/ con índice redactado; fixtures mínimos derivados de capturas, sin credenciales ni cambios del perfil del operador |
| 20.16 | Nueva superficie tools/ de supervisión si se elige; test propio y fuente/tipo de salida definidos por20.15 antes de implementar |
| 20.19 | hosts/dsh/ y banco node; hook solo si la reproducción demuestra que allí está el defecto |
| 20.22 | Config del proyecto elegido y su documentación; no activar este repo por default |
| 20.23/20.25 | spec, guía, README, perfil adversary, Plans.md y deploy-log (estos dos últimos, líder) |
| 20.24 | tools/install-hook.sh, tests de instalación/retirada zcode/grok y controles dsh; snapshot del árbol completo con temporales/backups |

Un archivo listado es ownership previsto, no permiso para cambiar toda su
superficie. Si otro PR lo modifica, integrar desde origin/master y resolver
el conflicto por contrato, sin checkout compartido ni revertir trabajo ajeno.

## Pruebas que permiten cerrar

- Bugfix: rojo medido antes del verde con el driver de un archivo y HOME,
  USERPROFILE, TMPDIR aislados; SAIKIT_HOOK_VIVO apunta al fuente del task.
  Cada protección nueva tiene mutante que falla por su causa, no por carga.
- Para20.1: caso sano que falla invalida la atribución de mutación; un mutante
  que no cambia código o un error de carga no cuenta como protección probada.
- Para20.2: ejecutar variante inocua --help en fixture100644 y validar argv
  de salidas; no ejecutar revert/merge/liberar-lock reales por probar texto.
- Para20.5: concurrencia real de procesos contra gh estricto falso; lock
  abandonado, proceso ajeno, normal/revert y reintento con base avanzada. Sello solo para merge normal;
  revert mantiene su contrato sin estado (punta/trailer/árbol inverso/CI).
  No presentar el ensayo como exclusión entre clones independientes.
- Para20.10: ni marca/sello sembrado ni merge manual acreditan autopilot.
  Capturar permiso del acto antes de publicación y el trailer después.
  Observar receta, pasos o skips, rastro/blast y adjudicación sin instruir
  cada paso al modelo artificialmente; separar éxito del gate de obediencia.
- Para20.11: revisar no escribe; solo-hilos no toca código; cuidar sí resuelve
  el caso pertinente y deja listo. Registrar lo ejercitado sin pedir al azar
  que un modelo produzca todas las ramas ni superar el tope de revisiones.
- Para20.18: si el modelo siempre entrega recibo, no ejercitó el bloqueo.
  Preparar caso reproducible; un block observado que no continúa es FAIL,
  no unknown. Controles1/3 protegen lo que sí se había medido.
- Todas las implementaciones: pre-commit local, CI completo en PR abierto y
  gate verde sobre el head entregado; suites rápida/lenta siguen completas.
  No duplicar batería completa local. Tests POSIX no acreditan rutas Windows.
- Cierre y deploy son del líder después del merge, con cuatro copias,
  comprobación de registro y auditoría de ledger; nunca SHA/resultado inventado.

## Relación con Phase19 y trabajo activo

Phase19 conserva todas sus filas y decisiones.19.6/19.7 prueban drivers
simulados;20.1–20.5 arreglan tools y banco preexistentes.19.11 prueba registro,
no evento vivo.19.16 prepara precondiciones, no ejecuta el happy path.
19.4/19.11 cubren instalación/retirada;20.24 corrige el producto que conducen.
Ninguna tarea depende artificialmente de terminar toda Phase19.

Cuando una superficie tenga ficha/driver, el PR de producto incorpora su
ajuste correspondiente para que el mapa no derive; si está en construcción,
los propietarios coordinan integración serial. El plan no edita la skill ni
sus tests ni cambia el WIP de19.2. Versiones nuevas del host se miden al
empezar cada tarea; los resultados de septiembre no se universalizan.

## Investigación, memoria y validación de equipo

Se consultaron spec, Plans/archivo, diseño16–18 y decisión2026-08-30,
retro18, smokes de recetas/verificación/autopilot/adversary/dsh, evidencia
18.26/18.27 y código/test de los tools. `.saikit/decisiones/18.11.tsv`,
18.25.tsv y18.27.tsv conservan decisiones históricas; el README corregido
18.27 y las capturas prevalecen sobre sus conteos antiguos. No se reescribe
el pasado para hacer coincidir resultados.

En este worktree no existe `.claude/`; memoria remota harness-mem no se
consultó. La comprobación de decisiones previas usa memoria versionada del
repo; no se leyó una DB ni secretos. No se introducen hechos nuevos sobre
APIs externas: el plan exige registrar versión/canal real al medir.

`Spec delta`: nueva spec/autopilot-residuals.md y enlace acotado en el spec
principal. No existe spec.md raíz; se conserva el SSOT existente. La spec
expresa garantías futuras y no cambia retrospectivamente límites medidos.
`team_validation_mode: subagent`: investigadores independientes cubrieron
Architecture/Security, Product/QA y Product/Skeptic; el líder integró sus
hallazgos. Coincidieron en separar investigaciones de implementación,
no duplicar Phase19 y mantener cierres históricos. Se incorporaron los
adicionales de banco de mutaciones, emisores de comandos, dry-run de retirada,
zona adversary, pins y corepack. Revisión final del plan: una ronda con veredicto inicial REQUEST_CHANGES.
El líder integró los dos hallazgos de contrato (dependencia de dsh que admite
repro FAIL sin cerrar la medición, y sello solo en modo normal, no en revert)
y los menores (reglas del rango final, dependencia20.6→20.4, nombre del test).
No se atribuye un APPROVE posterior que el revisor no emitió. Verificación
local posterior: filas previas intactas, dependencias válidas, ledger y
pre-commit completos en verde.

Juicio de planificación (1–5, no benchmark):

| Grupo | Encaje | Evidencia | Valor | Viabilidad | Regresión | Mantenimiento | Seguridad | Verificable | Decisión |
|---|---|---|---|---|---|---|---|---|---|
| Fixes locales con contrato existente | 5 | 4 | 5 | 4 | 4 | 4 | 4 | 5 | Required |
| Mediciones vivas faltantes | 5 | 4 | 5 | 3 | 4 | 4 | 4 | 4 | Required con precondiciones |
| Canal Grok y superficie headless | 5 | 4 | 5 | 2 | 2 | 3 | 3 | 3 | Required investigación; implementación Conditional |
| Adversary/CI/costo | 4 | 4 | 4 | 3 | 3 | 4 | 4 | 4 | Recommended |
| Ruteo16.7 y adopción por proyecto | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | Optional, sin activar por omisión |
| Auto-merge permanente/paridad/importar stack | 1 | 1 | 1 | 2 | 1 | 1 | 1 | 2 | Reject |

`formatter_baseline: configured`; `.pre-commit-config.yaml` (higiene y
secretos), `tests/lib/check_syntax.sh` (bash y controlador), job node-adapter
para JS y CI quality/suite/suite-lentos/secrets. `formatter_baseline_action:
none`: no nueva herramienta ni reformat masivo. Extensión nueva sin linter
entra en el chequeo de sintaxis antes de su implementación.

## Operaciones y autorizaciones al ejecutar

Este pedido autoriza crear tareas y publicar el plan revisable en el repo.
No autoriza por sí mismo nuevas sesiones pagas, lectura/exportación de auth,
configurar proyectos ni merge/revert de repos descartables/productivos.
La autorización D23 anterior expiró al cerrar18.10.20.8 debe concretar un
solo paquete de ejecución con destino, operaciones, presupuesto y expiración;
no se inventa una aprobación ni se pide permiso por cada comando ya cubierto.

### 事前確認 — paquete previsto, todavía no aprobado para ejecución viva

- 事項: sesiones Claude/Grok/dsh con credenciales mediante mecanismo del host
  理由: observar los recorridos reales sin copiar secretos a evidencia
  scope: Phase20 /20.8–20.18,20.20–20.22; versión, costo y límites por fijar
- 事項: GitHub en un repo descartable exacto, topic+marcador; push/PR/merge por tool y consultas CI
  理由: acreditar autorización, CI y publicación real sin usar un PR productivo
  scope: Phase20 /20.8–20.11,20.14; destino concreto y acciones antes de correr
- 事項: adopción autopilot del proyecto elegido, cinco opciones y publicación de config
  理由: la ausencia de config no autoriza habilitar permisos o despliegue
  scope: Phase20 /20.22 Optional, opt-in específico del operador

No hay borrado remoto por defecto. La limpieza del lab solo toca rutas de
propiedad demostrada; si se decide borrar un repo, requiere alcance exacto
independiente y comprobación de topic+marcador. No tocar perfiles vivos desde
un worker; deploy final sigue el protocolo autorizado del líder.

## Primer paso

Abrir `claude` en un worktree creado desde origin/master tras integrar este
plan; primera entrada `/harness-work 20.1`. Empieza por la fiabilidad del
banco de mutaciones y deja las llamadas vivas para su preflight. Para ejecutar
varias filas, nombrar el rango20 explícitamente: `all` también tomaría19.
