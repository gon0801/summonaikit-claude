# Cierre delegado de Codex entre worktrees

2026-09-08. **Backlog, todavía no implementado.** Subordinado a
[00-project-spec.md](00-project-spec.md); tareas en `Plans.md`, Phase21. Esta
fase registra incompatibilidades observadas durante el cierre de un trabajo
delegado en Codex y no cambia la aceptación de Phase20.

## Problema observado y límite de la evidencia

Un cierre con agentes delegados terminó rechazado porque el gate no acreditó al
verifier y buscó el rastro y el blast bajo el checkout activo, mientras los
artefactos estaban en el worktree aislado de la task. El rechazo demuestra una
incompatibilidad. Todavía no demuestra qué evento nativo de delegación recibió
el hook ni qué campo puede ligar con autoridad el turno al worktree revisado.

`VERIFIED BY SUBAGENT` conserva el alcance zcode del spec principal. No se
extiende a Codex para suplir observación faltante. Un nombre de task, prompt,
texto de resultado o recibo tampoco acredita que un agente se ejecutó, terminó
ni cumplió un rol.

## Contrato de investigación y adaptación

Primero se capturan y redactan los eventos reales de solicitud, inicio,
finalización y fallo en el canal que consume el hook, correlacionados por la
identidad nativa del agente. La salida que ve el orquestador no demuestra por sí
sola que el hook recibió ese evento. Una adaptación de roles exige una identidad
correlacionable con la ejecución actual y un rol explícito o una vía equivalente
definida y discriminable. No se infiere `verifier` de cualquier agente genérico
ni se acredita un despacho que quedó running o falló.

La raíz para rastro y blast requiere una señal autoritativa que ligue ejecución,
repo, HEAD y worktree. Compartir `git-common-dir` solo prueba que dos checkouts
pertenecen al mismo repositorio; no elige cuál produjo la evidencia de esta
task. La implementación debe conservar contención canónica y rechazar otro
worktree no acreditado, otro repo o HEAD, prefijos parecidos, recorridos `..` y
enlaces que escapen. Los artefactos acreditados deben pertenecer al commit y
árbol exactos que recibió el review; una copia untracked, dirty o escrita después
no sirve. Fuera de ese vínculo nuevo con el SHA, este trabajo no amplía
implícitamente la validación actual del contenido de los artefactos.

Si el host no expone una señal suficiente, la investigación termina con la
limitación documentada y las implementaciones condicionales no se activan.

## Implementación del canal nativo (21.2, 2026-09-13)

La re-corrida de 21.1 midió señal suficiente y 21.2 se activó con alcance
recortado. En Codex, el CIERRE nativo acredita rol: un `SubagentStop` con
`agent_id` registrado por el `SubagentStart` previo y `agent_transcript_path`
presente acredita el rol que el propio evento trae. En una sesión con canal
nativo activo, los eventos internos y el despacho NO acreditan: sin
`SubagentStop` el agente está running y no está acreditado. El cierre nunca
emite veredicto de éxito ni de fallo (el Stop de fallo blando tiene la misma
forma; del fallo duro R3 se desconoce si emite Stop — sin Stop = running =
no acreditado). Ni `task_name`, ni prompt, ni prosa, ni
ruta acreditan. En una sesión sin señal nativa queda el crédito histórico por
`agent_type` de eventos internos (medido en 6.1). **R4 (revisión externa
21.2 r2):** el legado rige hasta el PRIMER evento nativo de la sesión — el
hook no distingue «host sin canal» de «canal aún mudo», así que la marca
`codex_native_seen` apaga el legado desde el primer `SubagentStart`/`SubagentStop`
aunque no acredite nada (huérfano, replay, rol cambiado). `VERIFIED BY SUBAGENT`
conserva su contrato zcode: este canal no lo extiende a Codex.

## Preflight

Una ayuda previa al cierre usa el mismo parser y juez estático que Stop. Puede
mostrar requisitos dinámicos todavía no observables, pero no los acredita. Es
solo lectura: no consume ciclos ni cambia estado, crea rastro o fabrica
evidencia. El veredicto final sigue perteneciendo a Stop porque el estado puede
cambiar después del preflight.
