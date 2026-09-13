# 21.4 — Rastro y blast ligados a la raíz acreditada de la task

Fila `[Conditional]` `[lane:gate]` `[tdd:required]`. Activada por la SEÑAL
POSITIVA de 21.3 (ver `../21.3/README.md`): el `cwd` nativo del payload,
ligado a `session_id`/`turn_id`, deriva por git (`toplevel`, `git-dir`,
`HEAD`) la identidad del checkout del turno.

## Diseño implementado (decisión implementable de 21.3)

- El recibo cita la raíz como unidad en el span Close, estilo lista:
  `... ; raiz: /abs/path ; sha: <40hex> ; ...`.
- `trail_acreditar_raiz` (hooks/summonaikit-harness.sh): canoniza (`cd+pwd -P`),
  exige absoluta, exige `git -C raiz rev-parse --show-toplevel` == raíz
  canónica (mata prefijo parecido y subdirectorio), exige
  `git -C raiz rev-parse HEAD` == sha citado (mata checkout ajeno, otro
  worktree/HEAD/repo). Sin `raiz:` → modo legacy intacto. `raiz:` sin `sha:` →
  bloqueo fail-closed. Prosa (`la raiz: ...`) no acredita (la cita solo vale
  tras `;` o a inicio de línea).
- `path_present_under_acreditada`: resuelve los paths citados con
  `git -C <raíz>` — nunca con el cwd ambiental —, con contención física,
  rechazo de enlace final y `status --porcelain` vacío. Con HEAD == sha y
  estado limpio, el archivo ES el del árbol exacto revisado: untracked, dirty
  o escrito después del review se rechazan.
- Contrato de contenido vigente intacto fuera del vínculo SHA; otros hosts
  intactos (la rama nueva solo se ejerce con líneas `raiz:`/`sha:` citadas).

## TDD (rojo primero, literal)

Casos nuevos en tests/lib/trail_acreditada_cases.sh (familia G8: los corren
test_trail_gate.sh, test_gate_behavior.sh y test_gate_mutations.sh):

| Caso | Veredicto |
|---|---|
| raiz_acreditada_otro_cwd_cierra | CIERRA con cwd de otra sesión (el positivo literal) |
| raiz_untracked_bloquea / raiz_dirty_bloquea / raiz_post_review_bloquea | BLOQUEAN |
| raiz_ajena_bloquea / raiz_otro_head_bloquea / raiz_prefijo_bloquea | BLOQUEAN |
| raiz_puntos_cierra | CIERRA (`..` que canoniza a la acreditada) |
| raiz_symlink_bloquea (enlace versionado afuera) | BLOQUEA |
| raiz_sin_sha_bloquea | BLOQUEA |
| sha_sin_raiz_legacy_cierra | CIERRA (legacy intacto, sha ignorado) |

Rojo previo medido: con el hook sin el cambio (deployed anterior, que la
batería resolvía por defecto), los dos casos `cierra` bloqueaban con el
mensaje legacy — la brecha literal. Incidente de medición: el resolver
`tests/lib/hook_bajo_prueba.sh` prefiere el hook desplegado
(`~/.claude/hooks`) a la fuente del repo; las corridas de esta fila fijan
`SAIKIT_HOOK_VIVO=<repo>/hooks/summonaikit-harness.sh`. Segundo incidente:
dos repos sintéticos con contenido+autor+mensaje idénticos creados en el
mismo segundo comparten SHA — `_wt_nuevo` incrusta nombre+timestamp en el
contenido para que los SHAs siempre difieran.

## Mutantes

- Nuevo `G8|trail_raiz_vuelve_a_ambiental`: la rama acreditada vuelve a
  `path_present_under_root` → lo atrapa
  `caso_g8_full_raiz_acreditada_otro_cwd_cierra` (verificado en corrida
  dedicada: OK).
- Batería completa de mutaciones: OK (175/175).

## Resultados de batería (contra la fuente del repo)

- test_trail_gate.sh: OK (33 casos).
- test_gate_behavior.sh: OK (306 ok, 0 FAIL/ROJO).
- test_gate_mutations.sh: OK — 175/175 atrapadas, incluida la nueva
  `trail_raiz_vuelve_a_ambiental` (atrapada por
  `caso_g8_full_raiz_acreditada_otro_cwd_cierra`).
- Golden codex: sin deriva (golden-harness 57 escenarios + baseline OK);
  ninguna regrabación necesaria.

## Limitación declarada (no esconde nada)

Un clon ajeno en el MISMO sha con el MISMO árbol comiteado acredita igual:
el objeto acreditado es el árbol exacto revisado, y aceptarlo es inocuo
(contenido idéntico, reglas de contenido sin cambio). Lo que sí se rechaza:
cualquier diferencia de HEAD, de estado o de contención.
