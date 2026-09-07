# Contrato de residuales — Phase 20

2026-09-06. **Planificado, todavía no implementado.** Subordinado a
[00-project-spec.md](00-project-spec.md); tareas en `Plans.md`, Phase20;
[plan y fuentes](../phase-20-residual-plan.md). La petición es convertir
pendientes en tareas, no ejecutar mediciones externas ni habilitar producción.

## Invariantes que se conservan

El autopilot prepara y para; cada merge necesita autorización del acto,
las precondiciones de su modo y CI del SHA exacto. El modo normal exige
config de origin y veredicto acreditado; revert conserva la vía sin estado
del hook descrita en el spec principal. El postmerge avisa
sin revertir solo. `--admin`, force y atajos manuales no acreditan el camino.
La protección por sesión de18.26 y la evidencia histórica18.27 permanecen.
Los dos ciclos son una decisión vigente. El gate sigue siendo un ayudante,
no una frontera de seguridad frente a quien controla código y configuración.

## Correcciones y nuevas garantías acotadas

1. Los comandos sugeridos por herramientas del kit deben ejecutarse en un
   checkout limpio sin requerir cambios de modo: invocación con bash cuando
   corresponde. El banco debe rechazar pruebas que ya fallan antes de mutar.
2. Postmerge neutraliza el color antes de leer JSON de gh; error de transporte
   o dato no observable mantiene su clasificación nativa, nunca se vuelve verde.
3. DELEGATED en Grok solo toma trabajo de un array válido de primer nivel.
   Claves en prosa, objetos anidados, vacío, null y tipos inválidos no habilitan
   la salida. La implementación debe respetar las dependencias del hook;
   cualquier dependencia obligatoria nueva necesita contrato de distribución.
4. La integración normal y la de revert quedan serializadas por git-common-dir.
   El lock cubre la última validación y el intento de publicación; propietario
   y recuperación son explícitos, un proceso no libera el lock de otro.
   Cada intento revalida las precondiciones de su modo: sello solo en merge
   normal; el revert conserva su camino sin estado del hook, con comprobación
   de punta, trailer, árbol inverso y CI. No ofrece exclusión distribuida
   entre clones o máquinas; allí continúa la integración serial del líder.
5. Consumir un sello de un hijo en otra sesión solo será admisible si20.12
   demuestra un vínculo emitido por el host y20.13 lo valida junto con
   repo/HEAD/ejecución/rol/artefacto. mtime, task_hash o ruta coincidente no
   autorizan ese cruce. Sin vínculo, mantiene el límite y la tarea pendiente.
6. Una eventual superficie de supervisión headless conoce las ejecuciones
   que inició. Solo puede afirmar cierre exitoso tras observar un recibo
   completo de esa ejecución; RC0 del host no basta. Falta de recibo observada
   es FAIL, captura imposible es unknown. Sin fabricar evidencia, reiniciar
   trabajo silenciosamente ni transferir estado. No cambia las invocaciones
   directas que quedan fuera de esa superficie, ni promete que el host emita Stop.
7. La zona de pruebas adversariales será privada por ejecución, con propiedad
   y limpieza acotadas. No equivale a permiso para modificar producción ni
   reemplaza los controles de atribución y artefactos existentes.
8. Las retiradas zcode/grok con dry-run no escriben, borran, crean backups
   ni cambian configuración; informan lo que harían. La retirada real conserva
   sus verificaciones de propiedad y el comportamiento de otros hosts.
9. Actualizar pins de CI mantiene SHAs inmutables, diff revisable y workflows
   ajenos intactos. Corepack/pnpm se afirma solo para versiones ejercitadas.

## Medición y aceptación

- Registrar versiones, SHA del hook/tools, sesión/ejecución, payload/resultado,
  estado previo/posterior, PR/run y autorización cuando corresponda. Redactar
  secretos antes de versionar. El test doble y el driver de Phase19 acreditan
  simulación; no prueban un turno del host.
- Claude: autorización antes de publicación; LISTO no publica; el tool es quien
  termina el merge autorizado. cuidar-pr deja el PR listo y no mergea.
- PreToolUse: distinguir registro, invocación y deny ejecutado. En el perfil
  del operador ya se observó registro; eso no prueba el tercer nivel.
- dsh: escenario de bloqueo en UI web; no sustituirlo por headless ni por
  un test de traducción. Los escenarios1/3 ya medidos se usan como controles.
- Una investigación puede terminar con impedimento demostrado; eso no cierra
  su implementación ni una medición funcional dependiente. Las filas Required
  de medición siguen abiertas ante cuota, auth o captura insuficiente.
- Conditional solo se activa tras su decisión positiva; si se descarta, el
  líder registra cancelación explícita y residual, no marca PASS. Optional no
  se activa por omisión. Recommended forma parte del trabajo incluido; para
  retirarlo hace falta decisión explícita, no ignorarlo al cerrar la fase.
- No instalar ni activar autopilot en ningún proyecto solo por crear el plan.
  La autorización remota D23 de Phase18 expiró al cerrar18.10; una corrida
  nueva requiere destino, operaciones y presupuesto de uso aprobados.

## Relación con Phase19

Phase19 construye inventario, aislamiento, evidencia y drivers. Phase20
corrige producto y exige mediciones reales del alcance elegido. Reutiliza
los drivers disponibles sin imponer que termine toda Phase19. Si cambia una
superficie ya catalogada, su ficha/casos se actualizan en el mismo PR; cuando
su driver esté en desarrollo, ambos responsables integran serialmente.
No se edita el contrato19.16: su prueba viva sigue Optional en esa fase;
20.10/20.14 son las nuevas tareas de medición con su propio alcance.

El umbral histórico de más de cinco funciones para activar mantenimiento ya se
cumple con el catálogo de Phase19. Phase20 define el runbook en20.23 y ejecuta
una primera pasada en20.25 sobre su HEAD final. Esa pasada reutiliza el
dispatcher y el contrato de evidencia existentes, conduce cada feature en su
modo declarado y produce `clean`, `changed` o `blocked` sin crear un cuarto
resultado de feature ni ampliar la autorización de20.8. Sus hallazgos se
separan entre deriva documental, gap del harness y regresión de producto; solo
los dos primeros pueden corregirse dentro del alcance del verificador.
