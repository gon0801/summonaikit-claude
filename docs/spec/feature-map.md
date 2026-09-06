# Contrato del feature map — Phase 19

Fecha: 2026-09-06 UTC. **Diseño para implementar**, no cobertura ya medida.
Spec padre: [00-project-spec.md](00-project-spec.md). Tareas: `Plans.md`,
Phase 19. Plan y fuentes: [phase-19-feature-map-plan.md](../phase-19-feature-map-plan.md).

## Propósito y alcance

El operador debe poder descubrir qué superficies del kit se comprueban,
ejecutar su recorrido en aislamiento y distinguir evidencia de éxito,
fallo y falta de observación. El inventario completo no significa que todos
los comportamientos, flags y hosts estén probados.

Se conserva `.cursor/skills/verify-summonaikit/` como fuente de la skill local.
La excepción permite versionar sus instrucciones, controlador, fichas,
descriptores y esquemas; excluye estado, capturas y artefactos de ejecución.
No adopta Cursor como host ni autoriza tocar sus perfiles/configuración.
`verify/` sigue siendo el mapa español y Drive del producto, con su evidencia
y sello propios. Los dos recorridos se complementan; ninguno acredita al otro.

## Inventario, fichas y dispatch

- `features/catalog.json` declara raíces, clasificación de superficies y
  exclusiones con razón. El candado descubre los archivos de esas raíces y
  compara el descubrimiento con el catálogo; no valida solo una lista estática.
- Raíces: ejecutables de `tools/` (incluidos los sin extensión y `.ps1`),
  `hooks/`, `hosts/`, `skills/`, `agents/` y `recetas/`; `tools/lib/` se clasifica
  como biblioteca. Las familias de assets declaran patrón, consumidor y
  contrato, sin exigir una ficha por archivo de rol o receta.
- Cada `features/<id>.json` declara `schema_version`, `id`, `card`,
  `executor`, `execution_mode`, `surfaces`, `requirements`, `cases` y
  `required_assertions` por caso. IDs estables, únicos y sin rutas arbitrarias.
  Una superficie puede tener varios casos; cada una tiene cobertura asignada
  o exclusión explícita. Un caso aplazado queda nombrado, nunca implícitamente PASS.
- `list-features` enumera ID, ficha, modo y alcance declarado sin necesitar
  launch. `drive <id>` ejecuta todos los casos obligatorios de esa feature.
  Ejecutores públicos nuevos viven en `scripts/drivers/<id>.sh`; helpers en
  `scripts/lib/`. En 19.1–19.3 se admite `executor.kind: legacy` únicamente
  para las cuatro entradas actuales: el lint verifica su comando y función
  existentes en el controlador mediante una lista explícita. 19.4 las migra
  a archivos de driver y 19.17 rechaza entradas legacy restantes. No se acepta
  un nombre inventado como ejecutor. Ficha sin ejecutor y ejecutor público
  huérfano son FAIL.
- Se conservan `drive-install-dry-run`, `drive-gate-scenario [name]`,
  `drive-audit-ledger` y `drive-deploy-log` como aliases. Un alias de escenario
  acredita solo ese escenario, no toda `gate-turn`. Un escenario sin perfil
  de aserciones se puede diagnosticar, pero no recibe PASS de feature.
- Las fichas tienen H1 y descripción; exactamente cuatro H2, en orden:
  `Sub-features`, `How to get to it (user POV)`,
  `Driving it with control-summonaikit`, `Gotchas`. La sección de ejecución
  empieza con `Preconditions:` y relaciona ID de caso, acción, comando literal
  y observable. El lint cruza esos IDs con el descriptor.
- Una feature bloqueada mantiene ficha y ejecutor. La imposibilidad temporal
  de conducirla aparece en evidencia y doctor, sin sacarla del inventario.

## Aislamiento obligatorio

El controlador es un ejecutor de herramientas de confianza en un entorno
acotado, no una sandbox del sistema operativo contra código malicioso.
Su frontera sí debe impedir escapes por configuración, rutas o entorno.

1. `launch` crea un run privado (`umask 077`), HOME, temporales y repos Git
   desechables. Preparar la instalación se vuelve dependiente de cada feature:
   la ausencia del instalador no impide auditar un fixture de ledger.
   Los drives que necesitan hook lo preparan antes de observar su conducta.
2. El estado se guarda como datos validados en `.run/state.json`; jamás se
   ejecuta con `source` o `eval`. Un `.run/env` antiguo se rechaza con instrucción
   de relanzar; no se ejecuta ni se borra su supuesto HOME a ciegas.
3. Antes de `launch`, `doctor`, `drive`, `cli` y `cleanup`, verificar las rutas
   físicas, pertenencia al run y ausencia de enlaces que escapen. Validar
   HOME, destinos de todos los hosts, repo, git-common-dir, temporales, estado
   y artefactos. Un prefijo textual `/tmp` o un `HOME_REAL` heredado no prueba
   propiedad. Un estado inválido o escape observado es FAIL y no ejecuta tools.
4. Cada subproceso recibe un entorno construido explícitamente: HOME,
   USERPROFILE, XDG, temporales y destinos por host apuntan al run; se eliminan
   overrides de SAIKIT/hosts, configuración Git externa, credenciales y
   transportes heredados. Se reintroducen únicamente las opciones del caso.
   El fuente bajo prueba se fija explícitamente al checkout de esa tarea.
5. Las herramientas que escriben en cwd, refs o git-common-dir corren sobre
   repos desechables con origin bare local, sin hooks Git del operador. No se
   ejecutan setup/merge/postmerge en el checkout de trabajo aunque HOME sea falso.
6. `cli --` solo acepta las entradas públicas y argumentos/rutas validados
   del catálogo; no admite shells ni comandos arbitrarios. Es una restricción
   deliberada del CLI anterior y se documenta al migrarlo. Los cuatro aliases
   de drive conservan sus formas de invocación.
7. STATE/ARTIFACTS externos solo se aceptan en directorios privados asignados
   al run y validados. Los defaults de la skill permanecen posibles mediante
   directorios privados bajo `.run/` y `artifacts/`, nunca symlinks. En CI se
   ubican fuera del checkout para respetar la guardia de fuga del runner.
8. Cleanup elimina solo temporales reconocidos como propios del run; conserva
   sus evidencias y las de intentos anteriores. Repetir cleanup es inocuo.
   Directorios genéricos, estado manipulado y destinos ajenos se rechazan.

Las pruebas usan perfiles externos **sintéticos** con sentinelas y comprueban
que permanecen intactos. No leen ni modifican perfiles vivos. Permisos privados
y checks de identidad no prometen defensa contra otro proceso con el mismo
usuario que reescriba el ejecutor; las carreras residuales se declaran.

## Evidencia por intento

Formato: `artifacts/<run_id>/<feature_id>/<attempt_id>/`. Los IDs se asignan
de forma exclusiva; dos procesos o reintentos no comparten directorio.
Cada intento conserva `steps.jsonl`, `summary.json` y logs redactados.
Se registra inicio antes de ejecutar y resultado al terminar, también cuando
la herramienta devuelve error o llega una interrupción capturable.

`steps.jsonl` usa `schema_version: 1` y registros tipados `action`, `assertion`
o `diagnostic`: `run_id`, `attempt_id`, `feature_id`, `case_id`, `step_id`,
tiempo UTC, modo, comando como argv redactado, `tool_exit` (entero o null si
no se inició), observación estructurada y referencia al log. Una aserción
incluye `assertion_id`, esperado, observado y `result: PASS|FAIL|unknown`.
Una acción o diagnóstico por sí solo nunca acredita una feature.

`summary.json` incluye versión, identidad del intento, casos solicitados,
modo (`sandbox`, `simulated`, `live`), procedencia del checkout/hook (SHA Git,
dirty y hash de archivo), tiempos, `result`, `exit_code`, motivos y listas de
aserciones requeridas/observadas. Conteos de pasos y aserciones se **derivan**
de `steps.jsonl`; el validador verifica coincidencia de IDs, referencias,
esquema, conteos, casos, resultado y código final. Los descriptores fijan el
conjunto requerido antes del intento; no se reduce para fabricar verde.

| Resultado del drive | Exit | Regla |
|---|---|---|
| PASS | 0 | Todos los casos/aserciones obligatorios se observaron y pasaron; evidencia válida |
| FAIL | 1 | Fallo inesperado observado, aserción fallida, violación de aislamiento o evidencia inválida |
| unknown | 3 | No se pudo observar una parte obligatoria y no hubo fallo observado; razón explícita |

`MISSING` y `BLOCKED` son motivos de disponibilidad bajo `unknown`, nunca
resultados adicionales. FAIL domina unknown; unknown domina PASS al agregar
casos. Una dependencia presente pero corrupta, o un comando que debía funcionar
y sale 1, no se degrada a unknown. Falta de precondición documentada antes de
medir puede ser unknown; el diagnóstico no cuenta como aserción conductual.

`tool_exit` no es `exit_code`: golden usa 2 para falta de observación, setup
puede rechazar un lock con 3 y registration es advisory con exit 0. Cada
driver interpreta el contrato nativo. Un rechazo negativo esperado puede
producir PASS si se verifica también la razón y ausencia de efectos indebidos.

Exit 0 con pasos vacíos, aserciones obligatorias omitidas o solo `echo ok` es
FAIL del verificador. Una interrupción capturable o excepción deja el intento
fallido; un SIGKILL/corte de energía puede impedir summary: al leer ese intento
se declara evidencia incompleta, nunca PASS ni se borra. Si ni siquiera es
posible crear un destino de evidencia seguro, fallar por stderr sin ejecutar;
es la excepción explícita a la persistencia de cada intento.

No se vuelcan entorno completo, tokens, payloads vivos ni stdout arbitrario a
artefactos publicados. Se redacta antes de persistir; `capture-payloads` solo
recibe payloads sintéticos y su crudo queda en el temporal privado del caso.
Un secreto sintético inyectado no debe aparecer en ningún artefacto conservado,
incluidos stderr, comandos, JSON y logs de fallos. Un chequeo sobre archivos
Git no acredita la limpieza de estos artefactos ignorados.

## Doctor y modos de ejecución

`doctor [<id>]` escribe `doctor.json` y reporta requisitos por feature. La
seguridad de aislamiento es global; binarios, fixtures, PTY y acceso externo
se resuelven por dependencia. Una falta de gh real no bloquea gate ni un
driver con gh simulado. Un gh falso no satisface requisitos del modo `live`.
El agregado distingue features listas, bloqueadas y fallidas con sus razones.

Los drives por defecto usan herramientas reales del repo en sandbox; las
dependencias externas de merge/postmerge se simulan de forma explícita y
estricta. Los dobles rechazan llamadas no previstas y registran argv. Generar
un workflow no acredita una corrida real de Actions. Instalar un adaptador
no acredita que su host lo haya cargado o que su UI haya bloqueado un Stop.

`merge-happy-path` permanece visible. Su ejecución sin autorización vigente
para un repo descartable identificado produce `unknown/BLOCKED`, sin lanzar
hosts, consumir cuota o mutar GitHub. La cuota y demás requisitos se comprueban
al ejecutar, no se reutiliza un bloqueo histórico como hecho actual.
Una medición viva futura requiere autorización del operador para el destino
y acciones concretas; las autorizaciones de Phase 18 no se heredan a Phase 19.

Se conserva el límite de 18.26: sello en la sesión emisora; la evidencia
disponible no acredita vínculo padre-hijo. Nunca transferir sello, reviewer o
log por mtime o presencia de `verified`. La ficha viva consume las conclusiones
reales de 18.27/18.10 antes del cierre documental, sin arreglar esas tareas aquí.
Registrar una entrada bloqueada cierra su descubrimiento, **no su cobertura viva**.

## Calidad y mantenimiento

Todo nuevo driver tiene regresión y mutación que prueban cada protección.
Los wrappers `tests/test_feature_map_*.sh` entran en la partición rápida del
runner existente; no sustituyen la batería previa. Se verifica explícitamente
la sintaxis del controlador sin extensión. El lint barato de catálogo/fichas
corre también en pre-commit. No se agregan herramientas por mera conveniencia:
usar bash y Python estándar para validación y PTY cuando estén disponibles.

El cierre de una tarea exige su prueba acotada, mutaciones discriminantes,
revisión y PR con `gate` verde. La batería completa corre una vez en CI por
tarea; nuevas dependencias deben estar instaladas allí y los unknown obligatorios
no se aceptan como cobertura. Las limitaciones Windows se declaran por caso.
El mapa no vuelve obligatorio el Optional 16.7 ni importa pstack.
