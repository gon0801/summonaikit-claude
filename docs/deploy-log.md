# Deploy log — summonaikit-claude

Registro de cada deploy (post-merge) del gate hook al perfil vivo. Ver
`AGENTS.md` § "Deploy tras merge".

El deploy verifica las cuatro copias del hook en `~/.claude/hooks/`
(tambien usada por zcode), `~/.grok/hooks/`, `~/.dsh/hooks/` y
`~/.codex/hooks/`: bytes de `master` y registro de cada host.

## 2026-09-06 — PR #210 (18.10: cierre documental Phase 18) — hooks NO-OP

- **Merge:** `171a3345f17d97c45fc045921eb33ae601057b85`, head
  `81a7fb33e9561ccb3ffa99072f64515948a8da89`; gate SUCCESS en el
  [run 34047038390](https://github.com/gon0801/summonaikit-claude/actions/runs/34047038390).
- **Deploy (10:04 PDT):** master sincronizado; `sucio=no`,
  `coincide_origin_master=si`. Instaladores claude/grok/dsh/codex exit 0;
  cuatro hooks `YA AL DIA` (NO-OP), sha256 sin cambios:
  `8d13c9a0f34b3998a28104d89396523c50bca475c75d04c8aa4805243a751f39`.
- **Verificación:** `install-hook.sh --check` exit 0, cuatro copias al día y
  registro ok; `check-hook-registration.sh` y `audita-ledger.sh` exit 0.
- **Cierre:** fila 18.10 cerrada por el líder después del merge; documentos
  integran 18.27 y mantienen los límites medidos. Descartable entregado al
  operador, sin borrado. Gon autorizó terminar la entrega en esta sesión.

## 2026-09-06 — PR #212 (18.27: cierre Grok headless) — deploy REAL de las 4 copias

- **Merge:** `1fe7afcb652bbc2f141a1dc9af13967a1d72efdb`, head
  `80e1da918062fecd6cf2e23545897497d6dd4338`; gate SUCCESS en el
  [run 34022371166](https://github.com/gon0801/summonaikit-claude/actions/runs/34022371166).
- **Deploy (09:54 PDT):** master sincronizado; `sucio=no`,
  `coincide_origin_master=si`. Instaladores claude/grok/dsh/codex exit 0,
  cuatro copias `REPARADO`; sha256 del hook
  `8d13c9a0f34b3998a28104d89396523c50bca475c75d04c8aa4805243a751f39`.
  Backups del instalador: sufijo `20260906-095424.bak` en claude y
  `20260906-095425.bak` en grok/dsh/codex.
- **Verificación:** `install-hook.sh --check` exit 0, cuatro filas al día y
  registro ok; `check-hook-registration.sh` y `audita-ledger.sh` exit 0.
- **Cierre:** el líder integra la conclusión y cierra 18.27 en el PR de 18.10.
  El teardown headless y el presupuesto mantienen los límites declarados.
  Gon autorizó terminar la entrega en esta sesión.

## 2026-09-06 — PR #213 (19.1: feature-map inventory y lint) — hooks NO-OP

- **Merge:** `230bd96059d3384db5349d68b4a6c69c2115e66c`, head
  `7c5a9bd61c7a3af710e0682f6d3db4390db197f8`; CI del PR con `gate` verde
  en el [run 34021716592](https://github.com/gon0801/summonaikit-claude/actions/runs/34021716592).
  Post-merge en master: run [34022223146](https://github.com/gon0801/summonaikit-claude/actions/runs/34022223146).
- **Deploy (01:35 PDT):** desde `master` sincronizado, `sucio=no`,
  `coincide_origin_master=si`. Instaladores claude/grok/dsh/codex exit 0;
  las cuatro copias dijeron `YA AL DIA` (hook sin cambios).
- **Verificacion:** `install-hook.sh --check` exit 0, cuatro filas
  `resultado=al-dia registro=ok`; `check-hook-registration.sh` exit 0.
- **Operador:** Gon; merge y cierre de ledger autorizados en sesion Cursor.
  Fila 19.1 cerrada por el lead tras el merge.

## 2026-09-05 — PR #208 (18.26: sello local del reviewer Grok) — deploy REAL de las 4 copias

- **Merge:** `d45b564ebcab6ad50343a76f900faa45a419ef4c`. Antes del merge se
  integro el nuevo `master` (incluida 18.25) en el head `93aa689282c31569952357cb649afed703935979`;
  CI 8/8, incluido `gate`, en el
  [run 34015171295](https://github.com/gon0801/summonaikit-claude/actions/runs/34015171295).
- **Deploy (23:01 PDT):** `master` sincronizado, `sucio=no`,
  `coincide_origin_master=si`. Los cuatro instaladores exit 0,
  `REPARADO`; hook instalado sha256
  `f760fbbd33bb24dafb38697528ab22f0481590a036b6ede7e11e91b80465cc38`.
  Backups bajo `hooks/saikit-backups/` de cada host: sufijo
  `20260905-230153.bak` en claude y `20260905-230154.bak` en grok/dsh/codex.
- **Verificacion:** `install-hook.sh --check` exit 0, cuatro filas
  `resultado=al-dia registro=ok`; `check-hook-registration.sh` exit 0.
- **Limite:** el sello queda exclusivamente en la sesion que lo emite.
  No hay vinculacion padre-hijo acreditada por la captura disponible;
  el recorrido medido de autopilot Grok conserva merge manual del operador.
  No se transfiere reviewer/evidencia entre sesiones ni se relaja D18.
- **Operador:** Gon; merge y deploy autorizados a Codex. Fila 18.26
  cerrada por el lead con el limite explicito.

## 2026-09-05 — PR #209 (18.25: salida gh sin color forzado) — hooks NO-OP

- **Merge:** `a2ec23868f48cee0bf0aabdc677d14e355790ebe`, head
  `69f7223f7b43a947fd87792d950258ca661830ab`; CI 8/8, incluido `gate`,
  en el [run 34013581161](https://github.com/gon0801/summonaikit-claude/actions/runs/34013581161).
- **Deploy (22:54 PDT):** desde `master` sincronizado, `sucio=no`,
  `coincide_origin_master=si`. Instaladores claude/grok/dsh/codex exit 0;
  las cuatro copias dijeron `YA AL DIA` (hook sin cambios).
- **Verificacion:** `install-hook.sh --check` exit 0, cuatro filas
  `resultado=al-dia registro=ok`; `check-hook-registration.sh` exit 0.
  El script `saikit-merge.sh` y su pin del hatch quedan actualizados en
  el checkout. El cambio no habilita el merge automatico de Grok por si solo.
- **Operador:** Gon; merges y deploys autorizados a Codex. Fila 18.25
  cerrada por el lead despues del merge.

## 2026-09-05 — PR #207 (ayuda completa de blast) — tools actualizados, hooks NO-OP

- **Merge:** `58f1b54b54f322ac1f34c65fdf4b9e4306882f87`, head
  `b7df9b079898b933c2ea6a11b71fefeb21f78352`. CI 8/8 success, incluido
  `gate`, en el [run 34010058081](https://github.com/gon0801/summonaikit-claude/actions/runs/34010058081).
- **Deploy (21:06 PDT):** desde `master` sincronizado, `sucio=no`,
  `coincide_origin_master=si`. `install-hook.sh` y `--host grok`, `dsh`,
  `codex`: exit 0. Las cuatro copias del hook dijeron `YA AL DIA` (NO-OP).
  El paquete compartido `~/.claude/saikit-tools` actualizo `saikit-blast.sh`;
  backup `saikit-backups/saikit-blast.sh.nuestro.20260905-210620.bak`.
  El wrapper POSIX de Codex se replanto por el flujo normal del instalador.
- **Verificacion:** `install-hook.sh --check` exit 0, cuatro filas
  `resultado=al-dia registro=ok`; `check-hook-registration.sh` exit 0.
  El blast instalado coincide byte a byte con master; `--help` muestra
  la postura de falla completa sin SAIKIT_MARCA. Drive: 5 passed in 0.68s;
  sello `al_dia`; `audita-ledger.sh` OK. No se modifico `Plans.md`.
- **Operador:** Gon, merge y deploy autorizados expresamente a Codex.

## 2026-09-05 — PR #204 (18.12: hecho único exigido + tools del rastro plantados) — deploy REAL de las 4 copias

- **Merge:** `70f3a94e8e003ff0dff079f15eaddd93e3f2bb29`, head
  `1881f87`. Todos los jobs, incluido `gate`, verdes en el
  [run 34008635230](https://github.com/gon0801/summonaikit-claude/actions/runs/34008635230)
  (CodeRabbit rate-limited, no bloquea).
- **Deploy (20:26 PDT):** desde `master` limpio en `70f3a94`
  (`sucio=no`, `coincide_origin_master=si`); los cuatro instaladores
  exit 0, las cuatro copias `REPARADO` con backup nombrado — el hook SÍ
  cambió en este PR (gate de rastro/blast en carril full). Claude recibió
  además los 3 tools del trail en `~/.claude/saikit-tools`
  (`saikit-decision.sh`, `saikit-blast.sh`, `lib/redactar.sh`, plantados
  con swap atómico) y el recetario `00-lider.md` + `MANIFEST.sha256`
  actualizados. Grok: `agents/verifier.md` reparado. Codex: wrapper POSIX
  replantado; `hooks.json` sigue sin escribirse por diseño (declarado en
  la salida del instalador).
- **Registro:** `check-hook-registration.sh` exit 0.
- **Operador:** Gon (sesión kimi), merge autorizado tras 2 rondas de
  revisión del lead sobre el trabajo de Cursor.

## 2026-09-05 — PR #205 (cierre 18.9: smoke autopilot + filas 18.25-27) — deploy NO-OP

- **Merge:** `b3e27bca3a3b4b701db771bb1d71822b75d90c7a`, head
  `a710e25`. CI verde con `gate` en el
  [run 34007676096](https://github.com/gon0801/summonaikit-claude/actions/runs/34007676096).
- **Alcance:** solo docs — `docs/smoke-autopilot-2026-09-05.md`, cierre
  de la fila 18.9 en `Plans.md` y apertura de las filas 18.25, 18.26 y
  18.27 (huecos medidos en la medición viva). El hook no cambió.
- **Deploy:** `install-hook.sh` corrido tras el merge por costumbre del
  ritual: `YA AL DIA` en las 4 copias (no-op, sin backups). Entrada
  registrada a destiempo junto con la del PR #204.

## 2026-09-05 — PR #203 (sello persistente y cierre del registro Codex) — skill actualizada, hooks NO-OP

- **Merge:** `ae877a5f229dec5e50af338f60a41afabb25cc49`, head
  `10b25f15c08e1b4073d5f6d6fe2f1dde426374b2`. Todos los jobs, incluido
  `gate`, verdes en el
  [run 34006294938](https://github.com/gon0801/summonaikit-claude/actions/runs/34006294938).
- **Deploy (19:27 PDT):** desde `master` limpio, sincronizado con
  `origin/master`; los cuatro instaladores terminaron exit 0, hooks
  `YA AL DIA`. Claude actualizo la skill `saikit-verificar-app/verificar.sh`;
  `cmp` contra la fuente termino exit 0. Codex replanto su wrapper POSIX.
- **Registro:** `install-hook.sh --check` exit 0, cuatro
  `resultado=al-dia registro=ok`, `veredicto=ok`. El checker de registro con
  `--codex-wrapper` POSIX termino exit 0 sin avisos. Despues del deploy,
  `hooks/list` de Codex conserva las cuatro fases `enabled=true` y
  `trustStatus=trusted`, sin errores ni advertencias. El disparo real de las
  cuatro fases y el backup de configuracion constan en el cierre de PR #201.
- **Verificacion:** Drive post-merge `5 passed in 0.71s`; sello `al_dia`;
  `audita-ledger.sh` OK. El sello permanece valido al guardar este registro
  y la evidencia, sin cambiar el contenido medido del mapa, codigo o tests.
- **Operador:** Gon (sesion Codex), merge/deploy y registro autorizados.
  Sin cambios en `Plans.md` ni en el checkout de trabajo paralelo.

## 2026-09-05 — PR #201 (Drive del gate con HOME desechable) — deploy NO-OP de las 4 copias

- **Merge:** `0e711c564a616530ea2b3a0c1598950ef48ef07a`, head
  `4d3b8adc4c30b5f556315926307e55022717d7a0`, autorizado por el operador.
  CI del PR: todos los jobs, incluido `gate`, verdes en el
  [run 34003762052](https://github.com/gon0801/summonaikit-claude/actions/runs/34003762052).
- **Fuente desplegada:** `master` sincronizado a `b422a51`, que ya incluye
  tambien los merges de macOS y su cierre documental. Procedencia observada:
  `rama=master`, `sucio=no`, `coincide_origin_master=si`; hook SHA-256
  `153e8c21ec46221418d29803a9f6899506e2fc3eea1151a0640d28dbd1f130e7`.
- **Deploy:** `install-hook.sh` y sus modos `--host grok`, `--host dsh`,
  `--host codex` terminaron exit 0, los cuatro con `YA AL DIA`. El PR solo
  cambia `verify/`; el hook no cambio en esta entrega. El instalador de
  Codex tambien replanto `summonaikit-harness-codex-wrap.sh`.
- **Chequeo final:** `install-hook.sh --check` exit 1:
  claude/grok/dsh `resultado=al-dia registro=ok`; codex
  `resultado=al-dia registro=falta-registro`. Las cuatro copias coinciden con
  la fuente, pero no se afirma que Codex tenga el gate activo: falta
  `~/.codex/hooks.json`. Su checker reporta `unknown` de registro y ausencia
  del wrapper PowerShell por defecto; el wrapper POSIX si fue plantado.
  No se habilito un registro nuevo en esta entrega.
- **Validacion:** Drive sobre el master sincronizado: `5 passed in 0.73s`;
  `check-hook-registration.sh` de claude/grok/dsh exit 0 sin avisos;
  `audita-ledger.sh` OK, ninguna fila pendiente con trabajo ya mergeado.
  Revision independiente previa: una ronda, dos ajustes documentales
  corregidos y medidos; sin cambios posteriores en el test.
- **Operador:** Gon (sesion Codex); deploy y comprobacion repetidos a las
  19:06 PDT, despues del deploy compartido que registra la entrada siguiente.
- **Cierre del pendiente de Codex (19:13–19:18 PDT):** por instruccion
  expresa del operador se creo `~/.codex/hooks.json` para SessionStart,
  UserPromptSubmit, PostToolUse y Stop, apuntando al wrapper POSIX instalado.
  Se agrego en `config.toml` la confianza individual de las cuatro entradas,
  con las huellas `currentHash` devueltas por Codex 0.153.4. Backup previo:
  `~/.codex/hooks/saikit-backups/config.toml.before-hook-registration.20260905-1920.bak`.
  El nombre del backup es un identificador, no la hora de la medicion.
  `hooks/list`: cuatro `enabled=true`, `trustStatus=trusted`, sin errores ni
  advertencias. `install-hook.sh --check`: exit 0, cuatro
  `resultado=al-dia registro=ok`; checker Codex con `--codex-wrapper`
  apuntando al wrapper POSIX: exit 0, sin avisos.
- **Disparo real observado:** sesion efimera Codex
  `01a07481-c8c8-7ba3-9cb6-25625a019e56`, cwd temporal, comando inocuo `true`.
  La API del app-server emitio `hook/completed` para las cuatro fases, todas
  `status=completed` (54, 44, 38 y 38 ms); turno `completed`, respuesta `OK`.
  Se uso la confianza persistida, sin bypass. Esta prueba de registro fue
  sin sentinel; los casos armed/unarmed del gate siguen en el Drive aislado.

## 2026-09-05 — PR #200 / Task 18.22 (rojos de macOS: canon fisico + epoca portable) — deploy REAL a las 4 copias

- **SHA:** merge `229887a`, head `f2d1f89`, CI 8/8 con `gate` verde (run 34003475153).
- **El hook cambio** (H1 `adv_canon_path` ancla fisico el ancestro existente;
  H2 `adv_epoca_a_epoch` GNU→BSD con round-trip). En GNU comportamiento
  identico: golden regrabada SOLO identidad (diff = 3 lineas).
- **Deploy:** claude REPARADO (backup `…nuestro.20260905-184932.bak`), grok y
  dsh REPARADO (backups `…-184933.bak`), codex `YA AL DIA` + wrap POSIX
  plantado. `check-hook-registration.sh` exit 0.
- **Review del lead (sesion kimi):** diff auditado; DoD re-medida en la Mac
  del operador sin gnubin — `SAIKIT_PARTICION=rapidos` ⇒ `tests/run.sh: OK
  (37 tests)`, 13 skips contados aparte. Las mutaciones de H1/H2 quedaron al
  rojo MEDIDAS ahi mismo (una corrida sin `SAIKIT_HOOK_VIVO` midio el hook
  viejo y fallo exactamente donde la fila decia — la trampa de la regla 1 de
  AGENTS.md, declarada en la fila).
- **Mismo deploy cubre el PR #201** (`verify/` del kit, merge `0e711c5`): no
  toca el hook — sus cambios son del sandbox de verificacion. Mergeado por el
  operador sin review del lead; declarado.
- `audita-ledger` OK; `check-deploy-log` OK.
- **Operador:** Gon (sesión kimi).

## 2026-09-05 — PR #198 / Task 18.11 (PreToolUse niega el merge a pelo) — deploy REAL a las 4 copias

- **SHA:** merge `7009b74`, head `cf7f4a0`, CI 8/8 con `gate` verde (run 34001332338).
- **Deploy:** claude `YA AL DIA` (Cursor habia sincronizado el vivo al regrabar
  la golden); grok, dsh y codex REPARADO con backups `…nuestro.20260905-174819.bak`.
  `--check` rojo por diseño (codex sin registro); `check-hook-registration.sh`
  exit 0.
- **La guardia queda INERTE hasta registrarla** (operator-owned, fuera del PR):
  el checker avisa «MERGE A PELO: PreToolUse no esta registrado» — hay que
  agregar el hook en `PreToolUse` de `~/.claude/settings.json` con matcher
  `Bash` y SIN fijar `SUMMONAIKIT_HOOK_PHASE` (el comment del hook trae el
  snippet). Hasta entonces el veto a `gh pr merge` / `git push` a master|main
  no dispara en claude; el resto del gate corre igual. El deny vivo queda
  `unknown` declarado (residual del lead, en la TSV de la fila).
- **Review en 2 rondas:** r1 hallo 1 HIGH (bypass del hatch por sufijo
  `saikit-merge.sh.bak` — medido, pasaba con el pin legitimo); Cursor lo cerro
  con basename exacto + guarda anti-spoof, mutacion `pretool_hatch_spoof_apagado`
  atrapando solo su caso, driver 21/21. Noted: la TSV cita una mutacion con
  nombre viejo (deriva documental).
- `audita-ledger` OK; `check-deploy-log` OK.
- **Operador:** Gon (sesión kimi).

## 2026-09-05 — PR #196 (verificar-app: fecha_epoch valida calendario por round-trip) — deploy: skill replantada, hook sin cambios

- **SHA:** merge `f546b3e`, head `ce791dc`, CI 8/8 con `gate` verde (run 33997623419).
- **Deploy:** hook `YA AL DIA`; la skill viva `verificar.sh` quedo byte a byte
  con master (diff verificado tras `install-hook.sh`).
- **Que se mergeo:** follow-up del adversary de grok sobre el PR #194 (1 Act on
  MEDIUM, 2 Dismissed medidos): BSD desbordaba dias inexistentes
  (`2026-09-31` → `al_dia`); ahora guarda de formato + round-trip ⇒ `unknown`.
  Un CI rojo en el camino: el shim BSD del test no emulaba `-r` (en GNU es
  mtime de archivo, no epoch) — corregido en `ce791dc`.
- `audita-ledger` OK; `check-deploy-log` OK.
- **Operador:** Gon (sesión kimi).

## 2026-09-05 — PR #194 (verificar-app: fecha del sello portable + verify/ del kit) — deploy: skill replantada, hook sin cambios

- **SHA:** merge `7b19796`, head `0cc5aa9`, CI 8/8 con `gate` verde (run 33995017989).
- **Deploy:** hook `YA AL DIA` (el PR no lo toco); la skill viva
  `~/.claude/skills/saikit-verificar-app/verificar.sh` quedo byte a byte con
  master tras `install-hook.sh` (diff verificado). `--check` no se re-corrio:
  su rojo por diseño (codex sin registro) no cambio.
- **Que se mergeo:** `fecha_epoch` portable (GNU `-d` / BSD `-j -f`) — el
  `estado` del mapa ya no da `unknown` en macOS (rojo medido, discriminado
  viejo/nuevo contra el mapa real: unknown → al_dia); `sed -i` → `sed_i` en el
  test (era uno de los rojos de macOS de la 18.22, que sigue abierta con el
  resto); el `verify/` del propio kit (mapa 5 funciones + Drive 4/4 PASS).
- **Nota:** `.gitignore` quedo modificado en el working tree (entrada
  `.cursor/skills/verify-summonaikit/.run/`) — trabajo en curso de Cursor, no
  de esta sesión; no se tocó.
- **Operador:** Gon (sesión kimi).

## 2026-09-05 — PR #192 / Task 18.24 (el CI minimo nace rojo o verde-sin-correr) — deploy a las 4 copias; hook sin cambios

- **SHA:** merge `69f5893`, head `aaec0b6`, CI 8/8 con `gate` verde (run 33992318298).
- **Deploy:** el PR no toco `hooks/summonaikit-harness.sh`; el deploy corrio
  junto con el del PR #191 (misma corrida, ver esa entrada): claude `YA AL
  DIA`, grok/dsh/codex REPARADO con backup `…nuestro.20260905-142403.bak`.
  `--check` sigue rojo por diseño (codex sin registro, límite declarado de la
  18.15/18.21).
- **Que se mergeo:** `saikit-ci-minimo.sh` fail-closed (exit 2 sin runner,
  nada de `bash tests/run.sh` inventado), setup-python pinneado a sha +
  `pip install` (y requirements Y pytest), verify/ solo-markdown omite el
  paso y lo dice, job amarrado (ubuntu-24.04, timeout, concurrency),
  yarn/pnpm detectados; veto de merge: casos `skipped`=rojo y solo-push
  fijados, con decisión declarada. Cross-review adversary de grok: 6
  hallazgos (1 ALTO: pnpm sin toolchain), 5 Act on cerrados en `aaec0b6`,
  1 Dismissed; artefacto en `.saikit/findings/adversary-20260905T210102Z.json`.
- `audita-ledger` OK; `check-deploy-log` OK.
- **Operador:** Gon (sesión kimi).

## 2026-09-05 — PR #191 / Task 18.23 (el recibo se entrega un párrafo por etiqueta) — deploy REAL a las 4 copias

- **SHA:** merge `3843b7a`, head `4863983`, CI 8/8 con `gate` verde (run 33990766492).
- **Deploy:** claude `YA AL DIA` (glm habia sincronizado el vivo al regrabar
  la golden, verificado por sha); grok, dsh y codex REPARADO — corrian el
  hook pre-18.23 — backups `~/.grok/…nuestro.20260905-142403.bak`,
  `~/.dsh/…142403.bak`, `~/.codex/…142403.bak`. `--check` rojo por diseño
  (codex sin registro); `check-hook-registration.sh` exit 0, silencio.
- **Que se mergeo:** `has_receipt_label` con ancla de linea (vineta -,*,+,
  negrita o etiqueta pelada; `\n` literal de codex cuenta como frontera),
  los 7 mensajes de falta nombran la regla, contrato en sus dos bloques,
  golden regrabada con 227 pasos auditados sin flips. Ceremonia completa del
  implementador (verifier + adversary + reviewer 2 rondas, veredicto
  `clean`); review del lead con rojo reproducido y mutacion load-bearing
  medida; un hallazgo BAJO (comentario stale) corregido en `4863983`.
- `audita-ledger` OK; `check-deploy-log` OK.
- **Operador:** Gon (sesión kimi).

## 2026-09-05 — PR #185 / Task 18.8 (CI minimo cuando no hay) — deploy: skill actualizada, hook sin cambios

- **SHA:** merge `4051e69`, head `32e3682`, CI 9/9 (run 33984924089).
- **Deploy:** `install-hook.sh` replanta la skill `saikit-setup-autopilot` (su
  `SKILL.md` cambio: ahora ofrece el CI minimo). Hook `YA AL DIA`. `--check`
  sigue rojo por diseno (codex sin registro).
- **Que se mergeo:** generador de workflow pinneado a sha, con minimo
  privilegio y sin secretos; cableado al setup; veto en el camino de merge.
- **Cuatro hallazgos de CodeRabbit verificados y cerrados** (alcance del awk,
  instalacion de deps, minimo privilegio, carrera de publicacion).
- `audita-ledger` OK; `check-deploy-log` OK.
- **Operador:** Gon (sesion claude).

## 2026-09-05 — PR #186 / Task 18.19 (portabilidad macOS de la bateria + canal de skip) — deploy NO-OP

- **SHA:** merge `02fa21b`, head `b9b6a41`, CI 9/9 (run 33952631797). Hook sin cambios:
  `install-hook.sh` YA AL DIA; `--check` sigue rojo por diseño (codex sin
  registro).
- **Medido en la Mac del operador, partición rápida SIN GNU coreutils:**
  `test_gate_behavior` pasa de FAIL (master) a PASS (rama); golden_harness,
  restore_vendor, recetas, runner_guards, install_hook, install_provenance
  PASS; 12 casos contados como skip en categoría aparte. **Cero regresiones**:
  los diez tests que siguen rojos fallan idénticos en master.
- **Declaración incompleta, corregida:** qwen nombró 2 de esos 10; los otros 8
  van a la fila 18.22 con su primera aserción medida. El runner todavía cierra
  FAIL en macOS — por causas fuera de esta fila, ahora nombradas.
- `audita-ledger` OK; `check-deploy-log` OK.
- **Operador:** Gon (sesión claude).

## 2026-09-05 — PR #182 / Task 18.21 (registro, edad del ref y rollback) — deploy a las 4 copias; `--check` ROJO por diseño

- **SHA:** merge `f9cf872`, head `94d2f7f`, CI 9/9 (run 33948364332). Hook sin cambios.
- **Deploy por copia:** claude `YA AL DIA`; grok, dsh y codex verificados al día
  por `--check` (bytes iguales a la fuente).
- **`--check` post-merge: `veredicto=fallo`, rc=1 — y es lo correcto.** Con el
  registro ahora inspeccionado por host: claude/grok/dsh `registro=ok`, **codex
  `registro=falta-registro`** (`~/.codex/hooks.json` no existe). El gate de codex
  está apagado desde que se cableó su copia; hasta hoy `--check` decía `ok`.
  Queda rojo hasta que codex se registre — límite declarado de la 18.15.
- **Edad del ref:** `edad_s=0` (origin/master recién actualizado), juicio contra
  el ref local, umbral 1 día.
- **Hallazgo del lead en review, verificado:** el rollback nuevo dejaba el hook
  restaurado en modo 0600 (no ejecutable) — un rollback correcto en bytes que
  apagaba el gate. Arreglado en `94d2f7f`; R1 afirma el modo.
- **Nota de entorno:** `test_golden_harness` falla en macOS bajo el runner por
  `TMPDIR` (`/var` vs `/private/var`); entorno, no regresión — va en la 18.19.
- `check-hook-registration.sh` claude exit 0; `audita-ledger` OK;
  `check-deploy-log` OK.
- **Operador:** Gon (sesión claude).

## 2026-09-05 — PR #179 / Task 18.20 (el instalador declara procedencia y `--check` recorre todas las copias) — deploy a las 4 copias

- **SHA:** merge `914dc4a`, head `a9bf51e`, CI 9/9 (run 33934855275). Hook sin cambios.
- **Deploy por copia, como manda el `AGENTS.md` nuevo:** claude `YA AL DIA`,
  grok `YA AL DIA`, dsh `YA AL DIA`, codex **instalado por primera vez** (la copia
  no existía en esta Mac).
- **Primer `--check` real — la razón de ser de la fila:** ROJO al primer intento,
  `codex: falta (copia ausente) ⇒ veredicto=fallo`. Cierre en fallo, no en
  silencio: codex nunca se había cableado y nada lo decía. Tras cablearlo,
  `veredicto=ok (copias al dia; fuente = bytes de origin/master)`, rc=0.
- **Procedencia declarada en cada corrida:** `rama=master sha=914dc4a… sucio=no
  coincide_origin_master=si`, juicio contra el ref local sin fetch, y lo dice.
- **Registro:** `check-hook-registration.sh` exit 0 en claude. Para codex el
  propio instalador reporta el registro como `unknown` («no se pudo mirar»);
  no se afirma cableado. Residual declarado.
- **`check-deploy-log.sh`:** OK sobre este log (2 entradas juzgadas desde el
  corte, ordenadas, sin PR duplicado). `audita-ledger` OK.
- **Cuatro rondas de review**, tres de ellas con CI rojo por colisiones de la
  línea nueva de procedencia con guardianes viejos (`desconocid`, `unknown`);
  la salida fue de diseño: el campo lleva la razón, no un estado. Detalle en
  el PR y en la fila.
- **Operador:** Gon (sesión claude).

## 2026-09-04 — Deploy correctivo fuera de PR: grok y dsh estaban CINCO filas atras

- **Qué pasó:** el cross-review de grok sobre el protocolo de deploy destapó que
  el paso 2 de `AGENTS.md` (`install-hook.sh` sin `--host`) actualiza **una sola**
  copia. Desde 7.5 / Phase 15 / 18.15, grok y dsh tienen `DEST` propio.
- **Medido:** `~/.grok/hooks/…` y `~/.dsh/hooks/…` corrían `4127f79a` con mtime
  del 3 de septiembre — se habían perdido 18.6, 18.7, 18.5, 18.17 y 18.18.
  `~/.claude/hooks/…` (claude + zcode) sí estaba al día.
- **Deploy correctivo del lead:** `install-hook.sh --host grok` y `--host dsh`,
  los dos **REPARADO** con backup (`…saikit-backups/…20260904-080947.bak`).
  Verificado después: los tres perfiles con el mismo `sha256` que la fuente del
  repo. `check-hook-registration.sh` exit 0 en claude y en grok.
- **Corrección a un registro anterior:** la entrada de la 18.13 afirma que grok
  apunta al hook de `~/.claude/hooks/`. Dejó de ser cierto en la 18.15, cuando
  `grok_hook_cmd` pasó a interpolar el `$DEST` propio de grok. Queda anotado acá
  en vez de reescribir el registro histórico.
- **Fila abierta:** 18.20 — el protocolo no puede verificar su invariante. El
  instalador no consulta git (cero referencias a `origin/master` o `HEAD`), así
  que `YA AL DIA` significa «igual a lo que tenga el que lo corrió».
- **Operador:** Gon (sesión claude).

## 2026-09-04 — PR #174 / Task 18.18 (el label acepta el runner del repo) — deploy REAL

- **Qué se mergeó:** el carril del label pasa a aceptar las formas del runner
  propio (`tests/run.sh`), que el carril de evento ya aceptaba y éste no. Antes
  del fix, en un host ciego **ningún comando que fuera la verificación real de
  este repo podía acreditar**: el mecanismo era inusable en su propio repo.
- **SHA del despliegue:** merge `762dcdd`, head desplegado `f538a4b`, CI 9/9
  (run 33852389037). Hook vivo tras el deploy: `sha256` idéntico al de
  `origin/master`, verificado por `install-hook.sh` en su segunda corrida.
- **Contenido del cambio, para el índice:** `SAIKIT_VERIFIED_RUNNER_PROPIO_RE`
  (las dos formas de `tests/run.sh`) interpolada en `SAIKIT_VERIFIED_CMD_RE`;
  el missing line nombra la condición incumplida vía `saikit_verif_motivo`;
  7 casos G2 nuevos y 4 mutaciones; golden regrabada con diff solo de identidad.
- **Por qué este registro decía REAL y una sesión paralela lo anotó como NO-OP:**
  la sesión que implementó la 18.18 deployó desde SU RAMA para poder regrabar la
  golden, así que cuando ella corrió `install-hook.sh` el vivo ya coincidía y le
  dio **YA AL DIA**. El lead, que había repuesto el vivo a `master` al cerrar la
  18.6, obtuvo **REPARADO** con backup al desplegar tras el merge. Las dos
  lecturas son ciertas en su momento; lo que las hace parecer contradictorias es
  que dos sesiones desplegaron el mismo artefacto en distinto orden. **Regla:
  el deploy post-merge y su registro son del lead, uno solo por PR.**
- **Deploy:** `install-hook.sh` → REPARADO con backup en
  `…saikit-backups/summonaikit-harness.sh.nuestro.20260904-011944.bak`.
  `check-hook-registration.sh` exit 0. `audita-ledger` OK.
- **Golden:** `--check` OK, 55 escenarios igual, y la identidad **coincide** con
  el hook vivo — el implementador regrabó después de su último cambio, la regla
  que la 18.6 rompió y hubo que curar.
- **De dónde salió esta fila, que es la parte que conviene no olvidar:** dos
  implementadores reportaron el fallo y el lead los **desmintió dos veces, mal**.
  La primera redacción de la fila dio por buena una lectura sin medirla; la
  segunda midió el regex equivocado (`TEST_RUNNER_CMD_RE`, que gobierna el carril
  de evento) y culpó a `agents_seen`. El carril del label nunca consulta ese
  regex: usa `SAIKIT_VERIFIED_CMD_RE`. Lo destapó el cross-review de kimi
  apuntado a las conclusiones del lead, no a la entrega de nadie.
- **Dos rondas de review del lead sobre la entrega**, las dos por poder
  discriminante: los casos afirmaban solo el mensaje genérico (las cuatro razones
  nuevas podían regresar sin poner roja la batería), y las 27 fixtures del label
  usaban todas `bash` delante (borrar la rama directa del regex pasaba en verde).
- **Método corregido:** los hallazgos del lead se le pasan al implementador como
  texto pegable, no como comentario del PR — los implementadores no leen GitHub;
  el único canal es el operador.
- **Operador:** Gon (sesión claude).

## 2026-09-03 — PR #162 / Task 18.6 (carril `-saikit:autopilot`) — deploy REAL + golden regrabada

- **Qué se mergeó:** el sentinel `-saikit:autopilot` (FULL + `autopilot=1`) y su
  párrafo del contrato en los tres emisores. El párrafo dice que PREPARA y PARA
  A PREGUNTAR antes de publicar; el merge solo con el sí del operador y solo por
  `saikit-merge.sh`.
- **Deploy:** `install-hook.sh` → **REPARADO** con backup en
  `~/.claude/hooks/saikit-backups/summonaikit-harness.sh.nuestro.20260903-231656.bak`.
  `check-hook-registration.sh` exit 0. `audita-ledger` OK.
- **Deriva de identidad de la golden, curada en este PR:** tras el deploy,
  `golden-harness.sh --check` pasaba (55 escenarios se comportan igual) pero la
  cabecera declaraba `e71820af…` mientras el hook vivo era `e2916156…` — el
  implementador regrabó antes de su último arreglo. Regrabada: el diff son
  **3 líneas de cabecera** y los 55 escenarios quedan byte a byte. Es la misma
  clase de deriva que la 18.13 curó una vez; conviene regrabar SIEMPRE después
  del último cambio al hook, no antes.
- **Cuatro hallazgos cerrados por el lead**, el último de ellos el más caro de
  encontrar y el único que NO salió de la revisión del lead: el flag `autopilot` no estaba protegido en los rewrites de mitad de
  turno. Medido antes: quitar el flag del `write_state` de `mark_evidence` dejaba
  `test_gate_behavior` en OK con 0 fallas. Medido después:
  `FAIL: autopilot tras mark_evidence: esperaba [1], dio []`. Salió del
  cross-review de kimi sobre las conclusiones del lead, no de la revisión de la
  entrega.
- **Alcance de esa medición, declarado:** el lead mutó y midió **solo**
  `mark_evidence`. El caso hermano `caso_g1_autopilot_sobrevive_record_agent`
  existe y las dos aserciones (`autopilot=1` y `verified=1`) están escritas en
  los dos casos, pero la mutación de `record_agent` **no se midió por separado**:
  queda `unknown`, no verificada. La aserción de `verified=1` sí quedó probada en
  el caso de `mark_evidence`, y no es decoración — sin ella el caso pasaría sin
  haber ejercitado el rewrite.
- **Residual declarado:** `verdict_registrar_sello` y `adv_reescribir_estado`
  siguen sin caso que ate la preservación del flag.
- **Operador:** Gon (sesión claude).

## 2026-09-03 — PR #161 / Tasks 18.7 y 18.5 (setup del autopilot y aviso post-merge) — deploy PLANTA la skill

- **Qué se mergeó:** las dos filas en un solo PR a propósito — 18.5 lee el
  `.saikit/autopilot.json` que 18.7 crea, así que juntas el esquema se define y
  se consume en el mismo cambio, sin nada que sincronizar después.
- **El deploy NO fue no-op**, aunque el hook no cambió: `install-hook.sh` plantó
  la skill nueva (`recetario: AUSENTE -> ~/.claude/skills/saikit-setup-autopilot/SKILL.md`),
  verificada en el perfil vivo. Segunda corrida: `YA AL DIA`, exit 0.
  `check-hook-registration.sh` exit 0. `audita-ledger` OK.
- **Tres defectos que encontró el lead y GLM cerró**, todos con caso propio: la
  escritura de `autopilot.json` era destructiva (pisaba una config válida antes
  de validar la nueva; ahora escribe un temporal, valida, y recién entonces lo
  mueve — el patrón que ya usaba `install-hook.sh:312`); la `salud_url` con
  esquema roto salía **cruda** por la única rama que no pasa por `aviso()`, o sea
  sin `redactar`; y la guarda anti-sed-obsoleto de las dos baterías de mutación
  estaba **muerta** — `mut_sed` reescribía `HERE=` siempre, así que el `cmp -s`
  contra el original nunca podía dar iguales y una mutación que dejara de
  aplicar habría pasado en falso. Las 14 mutaciones se verificaron aplicando de
  verdad, una por una: ninguna estaba mintiendo todavía.
- **Nota de proceso:** GLM reportó que el gate no le acreditó la verificación
  pese a declarar `VERIFIED BY SUBAGENT`. Medido, su diagnóstico no se sostiene:
  su comando (`bash tests/test_autopilot_config.sh`) no matchea
  `TEST_RUNNER_CMD_RE`, que solo acredita `tests/run.sh`. Ver la fila 18.18,
  reescrita el mismo día por esta causa.
- **Operador:** Gon (sesión claude).

## 2026-09-03 — PR #165 / Task 18.17 (blast es XOR entre la triada y omitido) — deploy NO-OP

- **Qué se mergeó:** el hueco que la 18.3 dejó en el esquema del veredicto.
  `blast` pasa a ser un XOR: la tríada `{nivel, hecho, comando}` cuando corrió,
  o `{"omitido": "<razón no vacía>"}` cuando no. El escalar `"n/a"` pelado,
  la razón vacía y la mezcla de las dos formas quedan inválidos.
- **Deploy:** `install-hook.sh` → **YA AL DÍA** (la fila no toca
  `hooks/summonaikit-harness.sh`; son perfil, plan, validador y su batería).
  `check-hook-registration.sh` exit 0.
- **Auditoría del ledger (paso 4):** OK. Vale la pena anotarlo: los commits
  originales de qwen usaban `fix(18.17):` como scope, que `audita-ledger.sh`
  parsea y habría marcado la fila como «trabajo ya mergeado» de forma
  permanente. Se reescribieron a `fix(veredicto):` con cherry-pick antes de
  abrir el PR, verificando árbol idéntico. El ledger sale OK **porque** se
  corrigió; con el scope original estaría en falso positivo desde hoy.
- **Primera corrida de CI de este trabajo:** la rama de qwen nunca se había
  subido — el código estuvo terminado en local sin que ninguna batería lo
  tocara. Al abrir el PR: 9/9 verde a la primera.
- **Operador:** Gon (sesión claude).

## 2026-09-03 — PRs #160 y #163 (protocolo de entrega + fila 18.18) — deploy REPARA el vivo

- **Qué se mergeó:** #160 (`AGENTS.md` gana la sección "Protocolo de entrega":
  los tres estados, tope de cross-review, "no mergees", y que el número de fila
  no va como scope del commit — medido, ninguna de esas cuatro estaba escrita) y
  #163 (fila 18.18: la declaración `VERIFIED BY SUBAGENT` no acredita en canal
  ciego, hallada en vivo en el turno zcode que cerraba la 18.6). Docs-only las
  dos; ninguna toca `hooks/summonaikit-harness.sh`.
- **El deploy NO fue no-op pese a eso:** `install-hook.sh` reportó **REPARADO —
  el destino era nuestro y difiere de la fuente**, con backup en
  `~/.claude/hooks/saikit-backups/summonaikit-harness.sh.nuestro.20260903-204302.bak`.
  El vivo había derivado porque la ola paralela de las filas 18.5/18.6/18.7/18.17
  compartió un solo checkout y una rama en curso quedó instalada en el perfil
  real. Tras el deploy, vivo == `origin/master`.
- **`check-hook-registration.sh`:** exit 0, silencio.
- **Auditoría del ledger (paso 4):** `audita-ledger` OK — ninguna fila en
  `cc:TODO` con trabajo ya mergeado.
- **Lección de proceso registrada:** la ola paralela partió los ARCHIVOS pero no
  los DIRECTORIOS de trabajo. Los cuatro diffs salieron disjuntos y los cuatro PR
  `MERGEABLE`, pero el reflog del checkout principal rebotó ocho veces entre dos
  ramas y el rastro de la 18.6 (`.saikit/decisiones/18.6.tsv`) registra que su WIP
  se perdió dos veces. El aislamiento correcto es un `git worktree` por
  implementador.
- **Operador:** Gon (sesión claude).

## 2026-09-03 — PR #157 / Task 18.16 (los cuatro tests que quedaban sin ejecutor) — deploy NO-OP

- **Qué se mergeó:** merge `ffd90a0`, CI 9/9 (run 33820109339). Los tres tests
  ex-Windows-bound corren y pasan en macOS; `test_hook_acl` retirado; el skip
  del runner cambia de semántica; `SAIKIT_PY` y `mtime_de` portables.
  Implementó Cursor; midió y revisó el lead.
- **Deploy: NO-OP.** El PR no toca `hooks/summonaikit-harness.sh`.
  `install-hook.sh` reportó `YA AL DIA`; `check-hook-registration.sh` exit 0.
- **Verificado por el lead sobre master, y son DOS grupos distintos** (no
  confundirlos: de los cuatro que el runner salteaba, solo TRES quedaron
  verdes; el cuarto se retiró):
  - los tres ex-Windows-bound, que ahora corren y pasan: `test_install_hook`,
    `test_capture_payloads`, `test_probe_zcode_output` — exit 0 los tres;
  - `test_hook_acl`, el cuarto de aquella lista: **retirado**, no verificado en
    verde. Su archivo ya no existe;
  - `test_runner_guards` — exit 0. **No** era de los cuatro salteados: es el que
    ata el mecanismo nuevo de skip con casos sintéticos.
- **Lo que esto cierra de fondo:** desde hoy no queda ningún test que el runner
  saltee prometiendo que «lo corre Windows». La promesa que quedó incumplida al
  dejar Windows ya no existe; el mecanismo nuevo distingue «lo corre otro» de
  «no lo corre nadie» y cuenta el segundo como `unknown`.
- **Corregido en la revisión:** el PR commiteaba un veredicto sellado, contra el
  diseño de la 18.3. Sacado en `9d92a0a`.
- **Residual declarado, con el hilo ABIERTO a propósito:** escaping de rutas en
  los comandos de hook generados (`zcode_hook_cmd`, `zcode_probe_cmd`,
  `grok_hook_cmd`). Es preexistente de `master`, no de esta rama.

## 2026-09-03 — PR #154 / Task 18.13 (Close cita el sello, líder commitea antes, el veredicto no es trabajo) — deploy REAL

- **Qué se mergeó:** merge `59d45b4`, CI 9/9 en el head `57e32de` (run
  33728651684). Tres cambios al hook en una sola regrabación de la golden.
  Implementó qwen; revisó el lead.
- **Deploy: REPARADO, no no-op.** El hook cambió. `install-hook.sh` reportó
  `REPARADO: el destino era nuestro y difiere de la fuente`, con backup en
  `~/.claude/hooks/saikit-backups/summonaikit-harness.sh.nuestro.20260903-122550.bak`.
  `check-hook-registration.sh` exit 0.
- **La deriva de identidad de la golden, CURADA.** Desde la 18.3 la cabecera
  declaraba un hook que no existía en ninguna forma (187898 bytes / 3116
  líneas). Tras este deploy, hook vivo y cabecera coinciden byte a byte:
  `36b436ae…`, 188880 bytes, 3134 líneas. `golden-harness.sh --check` contra el
  vivo: 55/55 y, por primera vez, **sin** el aviso «el hook cambio de identidad».
- **Efecto en los otros hosts cableados:** zcode y grok apuntan a este mismo
  hook en `~/.claude/hooks/`, así que reciben el cambio con este deploy. dsh
  tiene copia propia en `~/.dsh/hooks/`: la reinstala `--host dsh` cuando toque.
- **Auditoría del ledger (paso 4):** `test_plans_ledger` OK; `audita-ledger`
  sigue marcando la 18.16 (falso positivo por scope `docs(18.16)`, desaparece al
  cerrarla). No marcó la 18.13 porque los commits usaron scope `hook`/`veredicto`.

## 2026-09-03 — PR #153 / Task 18.15 (formas de comando de macOS) — deploy NO-OP del hook, pero el PERFIL cambió

- **Qué se mergeó:** merge `b945da4`, CI 9/9 en el head `a5d5511` (run
  33728994135). Formas POSIX del instalador para grok, dsh, codex y zcode; guarda
  que sondea el instalador; planta atómica del wrap de codex. Implementó Cursor;
  midió y revisó el lead.
- **Deploy del hook: NO-OP.** El PR no toca `hooks/summonaikit-harness.sh`.
  `install-hook.sh` reportó `YA AL DIA`; `check-hook-registration.sh` exit 0.
- **Lo que SÍ cambió, y es lo importante: el perfil real del operador.** Para
  medir el disparo del hook, el lead cableó con el instalador del PR, con
  permiso explícito y respaldos en `~/Desktop/saikit-briefs/respaldos-turnos-*`:
  `zcode` (`hooks.enabled` habilitado, 4 fases, 4 agentes), `dsh` (patch en
  `~/.dsh/cordis.patch.yml` + hook en `~/.dsh/hooks/`), `grok` (registro en
  `~/.grok/hooks/summonaikit.json`, 5 fases, 4 agentes, hook propio). **Los tres
  dispararon en turnos reales.** Antes de hoy, en esta Mac solo Claude estaba
  cableado; ahora lo están Claude, zcode, dsh y grok.
- **codex, para que cuadre con el 4 de 4 de la fila:** su disparo lo midió
  Cursor, no el lead, y en un `CODEX_HOME` **aislado**, no en el perfil real:
  `codex exec ... -c 'features.hooks=true'` → `hook: SessionStart` y
  `hook: UserPromptSubmit` completados, con el marcador del probe
  `FIRED tag=codex TARGET=codex` vía el wrap. Está medido, pero **NO quedó
  cableado en el perfil real del operador** — es el único de los cuatro en esa
  situación, y cablearlo es un paso aparte (`--host codex`).
- **Estado del hook fuera de `~/.claude`:** dsh y grok escriben su estado junto
  a SU hook (`~/.dsh/hooks/state/`, `~/.grok/hooks/state/`). Buscar solo en
  `~/.claude/hooks/state/` da un falso «no disparó».
- **Auditoría del ledger (paso 4):** `test_plans_ledger` OK; `audita-ledger`
  marca la 18.16 — es un falso positivo por el scope `docs(18.16)` de un commit
  de docs, desaparece al cerrarla. La 18.15 no la marcó porque los commits de
  Cursor usaron scope `install-hook`, no el número de fila: el auditor solo ve
  lo que el scope le dice.
- **SEGURIDAD — ACCIÓN ABIERTA, DUEÑO: EL OPERADOR.** Durante la medición el
  lead imprimió en la salida de su sesión dos claves de Z.AI que viven en texto
  plano en la máquina del operador: en el script `glm` y en
  `~/.zcode/cli/config.json`. La exposición fue **solo en la sesión del lead**
  (transcripción y logs de esa sesión); **ningún valor de clave se escribió en
  este repo** — verificado antes de este commit con el escaneo de secretos y con
  grep sobre el árbol. Lo que queda es del operador y no del kit: **revocar las
  dos claves en Z.AI, crear reemplazos y sacarlas del texto plano** (variable de
  entorno o llavero). Esta fila 18.15 se cierra por su alcance (formas de
  comando), NO porque la rotación esté hecha; la rotación se registra aquí con
  fecha cuando ocurra. CodeRabbit mantiene abierto ese hilo hasta entonces, y
  está bien que así sea.

## 2026-09-03 — PR #150 / Task 18.14 (agente_traducido bajo awk BSD) — deploy NO-OP

- **Qué se mergeó:** merge `802611d`, CI 9/9. `agente_traducido` deja de usar una
  regex «que no matchea nada» y pasa sus valores por `ENVIRON` en vez de
  `awk -v`. Implementó qwen; revisó el lead.
- **Deploy NO-OP:** el PR no toca `hooks/summonaikit-harness.sh`.
  `install-hook.sh` reportó `YA AL DIA`; `check-hook-registration.sh` exit 0.
- **Auditoría del ledger (paso 4 de AGENTS.md):** `tests/test_plans_ledger.sh` OK
  (5 celdas en todas las filas) y `tools/audita-ledger.sh` OK. Esto último
  importa: al cerrar la 18.14 **desapareció el falso positivo** que el auditor
  arrastraba desde que la fila se abrió con un scope de commit `docs(18.14)`.
- **Lo que destraba, medido:** `--host kimi` y `--host claude` pasan de morir con
  su error de awk a salir exit 0. El delta de `test_install_hook` en macOS es de
  **230 FAIL a 61**, y los de awk de **45 a 2**. `zcode` ya no muere por awk sino
  por su bloqueo previo, que es de la fila 18.15.
- **Lo que NO destraba, y conviene no confundirlo:** el kit sigue cableando solo
  Claude. Esta fila arregla la traducción de perfiles; el cableado de los otros
  hosts es la 18.15.
- **Hallazgo derivado a la 18.16:** `mtime_de` (`tests/test_install_hook.sh:90`)
  usa `stat -c '%y'` de GNU con `2>/dev/null`, así que en macOS devuelve cadena
  vacía y sus aserciones comparan vacío contra vacío: **pasan en falso**. El repo
  ya había hallado y cerrado ese patrón en el cross-review de la 16.5, pero en un
  solo sitio.

## 2026-09-02 — PR #142 / Task 18.4 (`tools/saikit-merge.sh`) — deploy NO-OP

- **Qué se mergeó:** merge `f1063af`, CI 9/9 en el head `2c58ea1` (run
  33699818088). `tools/saikit-merge.sh` (D18 + D19), su batería de 34 casos con
  banco de 18 mutaciones, y el endurecimiento de
  `tools/lib/veredicto_contract.sh` con un parser JSON real en awk, sin `jq`.
  Implementó GLM; revisó el lead.
- **Deploy NO-OP:** el PR **no toca** `hooks/summonaikit-harness.sh`.
  `install-hook.sh` reportó `YA AL DIA: el destino es nuestro y byte a byte
  igual a la fuente`. `check-hook-registration.sh`: exit 0, sin hallazgos.
- **Ojo para la 18.12:** el instalador **no planta** `tools/saikit-merge.sh` ni
  `tools/lib/veredicto_contract.sh` en el perfil del usuario. Hoy el script solo
  existe en un clon del repo. Plantarlo es alcance de la fila 18.12, y sin eso
  el autopilot de un repo ajeno no tendría con qué mergear.
- **Lo que el lead verificó por su cuenta**, sin tomar el PR por bueno: la suite
  entera (34 casos OK) con **las 18 mutaciones del banco atrapadas** (18/18, cero sobrevivientes), y el
  parser fuzzeado contra el módulo `json` de Python con 33 casos adversarios,
  con **cero discrepancias**.
- **Tres hallazgos cerrados en la revisión:** el registro del merge en
  `--revert-de` escribía en un directorio que puede no existir y aun así
  anunciaba éxito; una clave con escapes `\uXXXX` burlaba las dos guardas del
  parser; y un hallazgo del bot descartado midiendo. Los tres con su caso y su
  rojo medido, salvo el descartado.
- **Queda abierto:** fila **18.13** (las dos piezas del contrato y el crédito
  del `Write` del veredicto, que comparten una regrabación de la golden) y el
  residual declarado del arnés de mutaciones, anotado en la fila 18.4.

## 2026-09-02 — PR #140 / Tasks 18.1+18.2+18.3 (diseño medido, receta cuidar-pr, veredicto sellado) — deploy REAL

- **Qué se mergeó:** merge `15af87a`, CI 9/9 en el head `0e798b7` (run
  33660631758). El plan medido de la Phase 18, `recetas/cuidar-pr.md`, y el
  sello del veredicto en el hook (`SAIKIT-VEREDICTO-SELLO`) con
  `tools/lib/veredicto_contract.sh` y su batería.
- **Deploy: NO fue no-op.** El vivo estaba en **181319 bytes** y con **CERO**
  ocurrencias de `SAIKIT-VEREDICTO-SELLO`, o sea una versión anterior a 18.3.
  `install-hook.sh` reportó `REPARADO: el destino era nuestro y difiere de la
  fuente` y dejó el vivo en **187373 bytes / 3114 líneas / sha `4127f79a`**,
  idéntico a `master`. Backup en
  `~/.claude/hooks/saikit-backups/summonaikit-harness.sh.nuestro.20260902-102625.bak`.
  De paso plantó el recetario y la skill `saikit-verificar-app`, que estaban
  AUSENTES en este perfil.
- **`check-hook-registration.sh`:** exit 0, sin hallazgos.
- **Lo que costó tener el vivo desactualizado, y por qué este paso existe:**
  `resolver_hook_bajo_prueba` prefiere el hook VIVO sobre la fuente del repo.
  Con el vivo viejo, `test_veredicto_contract.sh` daba rojo en TODOS los casos
  del sello y el diagnóstico natural —el que se dio— fue «brecha de macOS».
  Era falso: la batería estaba ejercitando un hook sin el sello. Con
  `SAIKIT_HOOK_VIVO` apuntando a la fuente, la suite cierra OK entera, mutación
  incluida. Media revisión se fue en ese diagnóstico equivocado; el deploy tras
  merge es exactamente lo que lo previene.
- **Deriva detectada y NO resuelta:** la cabecera de `tests/golden/baseline.txt`
  declara `hook_bytes: 187898` / `hook_lineas: 3116` / sha `adc0cb76`, pero el
  hook de `master` y el recién desplegado son **187373 / 3114 / `4127f79a`**.
  La línea base se grabó desde un hook que no existe ni en el repo ni en el
  perfil vivo. El `--check` pasa por COMPORTAMIENTO (55/55) y avisa «el hook
  cambio de identidad». Anotado en la fila **18.13**.
- **Queda abierto:** fila **18.13** (la línea `Close:` del contrato, el «el
  líder commitea antes de despachar», y el `Write` del veredicto acreditado
  como edición de código). Las tres comparten una sola regrabación de la golden.

## 2026-09-01 — PR #138 / Task 16.12 (caller por defecto de -RutasExtra) — deploy NO-OP; cierra la Phase 16

- **Qué traía:** `hook-acl.ps1` deriva y AUDITA por defecto la carpeta de
  skills del perfil (solo con `-Path` en la forma exacta `<perfil>\.claude\hooks`);
  corregirla con `-Fix` sigue exigiendo `-RutasExtra` explícito. Premisa de la
  fila corregida y medida: `hooks/recetas` ya estaba cubierto por la recursión.
- **La task "chica" que no lo era:** tres ciclos internos — adversary (9
  hallazgos, 3 altas: derivación fuera de `.claude` con la invocación
  documentada de la 0.2, junctions, TOCTOU) y reviewer que la declaró NO
  PUBLICABLE dos veces; la segunda por la **segunda puerta**
  (`Repair-StaleInherited` mutaba bajo la raíz derivada SIN respaldo), atrapada
  midiendo un HIJO de la carpeta y no el directorio — la granularidad de la
  aserción decidió el veredicto.
- **Cross-review externo (pedido por el operador):** codex 3/5 reales; grok
  encontró el hallazgo de la ronda — con `-Path` LIMPIO y solo la derivada
  sucia, `-Fix` sin flags le cortaba la herencia a un árbol sin hallazgos
  propios (corrida que antes era no-op). Reproducido en vivo por el lead y
  cerrado: el no-op se decide por el radio mutable. Nadie lo vio en tres
  ciclos internos — el valor de la ronda externa quedó medido.
- **Incidente del harness, declarado:** el candado del adversary (13.4) bloqueó
  el cierre del turno porque el rol escribió sus fixtures fuera de
  `.saikit/findings/` — su trabajo real lo exige y no tiene zona declarada;
  va a la Phase 18. El revert incluyó desenlazar un junction con `rmdir` (no
  `rm -rf`, que borra el destino). Un verifier murió por sesión expirada y se
  reintentó una vez (regla del contrato).
- **Merge:** `d203b864`. CI 9/9. Suite del guardrail: 24 casos, 0 FAIL.
- **Deploy:** NO-OP verificado — el guardrail vive en `tools/` del repo, no en
  el perfil; hook vivo byte a byte igual, perfiles y skills intactos.
- **Con esta fila cierra la Phase 16 completa.**

## 2026-09-01 — PR #136 / Task 17.6 (cierre de la Phase 17) — deploy REAL (skill nueva)

- **Qué traía:** el instalador planta `saikit-verificar-app` (los DOS archivos),
  spec § **Límites MEDIDOS de la Phase 17** (qué runners acredita la lane de app
  real y qué no), guía de usuario con `verificar-app` en **ya funciona** y el
  mapa explicado sin jerga, README § recetario y skills.
- **El hallazgo del cierre, con rojo medido:** la marca `saikit_owned` se lee del
  PRIMER bloque `---` del archivo, y en `verificar.sh` ese bloque era el heredoc
  que escribe el frontmatter del `LEEME.md` (el lector devolvía `generado: ...`,
  no la marca). El generador que el kit MISMO planta se clasificaba DESCONOCIDO
  y **no se actualizaba nunca**, en silencio. Cerrado con la marca en un bloque
  no-op al inicio + 5 casos; 9 líneas de FAIL contra el instalador sin arreglar.
- **CodeRabbit: 2 Minor, los dos reales.** Placeholders literales
  (`#PRNUM`/`MERGESHA`/`CIRES`) en una fila marcada `cc:完了`, y **un caso vacuo
  del lead**: la precondición del caso de `--quitar-recetas` solo cubría
  `SKILL.md`, así que la aserción de ausencia pasaba en vacío si el install no
  publicaba `verificar.sh`. Cerrado con mutación medida (`el instalador publica
  solo SKILL.md` ⇒ la precondición nueva se pone roja).
- **Merge:** `8504e585`. CI 9/9 (run `33518589146`).
- **Deploy REAL:** `AUSENTE -> ~/.claude/skills/saikit-verificar-app/SKILL.md` y
  `.../verificar.sh`. Verificado byte a byte contra el repo; hook y perfiles ya
  al día. **Evidencia independiente:** tras el deploy, el propio harness lista
  `saikit-verificar-app` entre las skills disponibles de la sesión — no solo mi
  diff dice que aterrizó.
- **Límite declarado:** la cobertura del instalador es **Windows-bound** (el CI
  Linux saltea `test_install_hook.sh` entero), así que plantar la skill en Linux
  queda `unknown`, no supuesto.

## 2026-08-31 — PR #133 / Tasks 17.7+17.8 (candado local pinneado + concurrencia del rastro) — deploy NO-OP

- **Qué traía:** 17.7 — gitleaks pinneado 8.30.1 como capa local (opción a),
  AVISO ante versión distinta, fallback grep que DECLARA que su PASS no es el
  veredicto; el hallazgo #3 de 17.3 reproducido (el fallback lo pasa, el
  pinneado lo atrapa). 17.8 — lock con token dueño `pid:nonce`, reclamación
  re-verificada con `mv` atómico, guard de fila truncada + delta de bytes en
  el append (tradeoff declarado: detecta, no repara), `--check` bajo candado,
  `stat` GNU declarado. Casos deterministas con pausa inyectable (`test_knee`).
- **Implementó DeepSeek.** Auditoría del lead: 3 mutaciones medidas, las 3
  atrapadas; el caso fuerte de 17.7 corrido con el binario 8.30.1 real.
  CodeRabbit: 1 Major REAL — `SAIKIT_GITLEAKS` pisado por el PATH, la
  remediación documentada era mentira; cerrado por el lead con rojo medido
  (2 FAIL) y shims que registran QUIÉN corrió. Noted declarado: microventana
  SIGKILL en la reclamación puede dejar el lock clavado.
- **Merge:** `ecee3b4e`. CI 9/9.
- **Deploy:** NO-OP (tools/tests; hook vivo == repo verificado byte a byte,
  perfiles intactos).

## 2026-08-31 — PR #131 / Tasks 17.2+17.4 (lane de app real + el hecho único) — deploy REAL (perfiles)

- **Qué traía:** 17.2 y 17.4 agrupadas (un solo toque a `agents/verifier.md`):
  la lane de app real (`verify/` corrido = evidencia; sin `verify/` se propone,
  no se inventa; "inconcluso o superficie equivocada no es PASS") y el hecho
  único (D13): `tools/saikit-blast.sh` escribe `.saikit/findings/blast-<task>.json`
  con orden aplana → redacta → recorta → re-redacta, contrato de `--task`
  reusado byte a byte de `saikit-decision.sh`, adjudicación en `reviewer.md`.
- **Implementó DeepSeek**; corrió por su cuenta un cross-review codex+glm y un
  adversary y cerró hallazgos reales (comando de solo espacios, orden de
  redacción, control chars). El PR no traía el rojo medido: lo midió el lead
  con 3 mutaciones (evidencia comentada en el PR #131).
- **Hallazgo del lead:** el caso de la credencial `user:pass@` cortada era
  VACUO — con la mutación de orden quedaba verde (padding 990: el corte caía
  en `https://FA` y el user jamás sobrevivía ni con el código roto). Corregido
  en `c1107b0` (padding 975 = corte justo tras la clave), rojo/verde
  re-medidos. La clase ya conocida: un caso que no puede ponerse rojo no es
  un caso.
- **Merge:** `4e17f07e`. CI 9/9 (run `33449646189` sobre `c1107b0`).
  CodeRabbit NO revisó — rate limit semanal agotado; cero hilos = "no corrió",
  declarado.
- **Deploy:** hook `YA AL DIA` (el PR no lo toca). Perfiles: `AGENTE CLAUDE
  REPARADO: verifier, reviewer` — OJO: la corrida pelada de `install-hook.sh`
  NO toca perfiles; para cambios de `agents/*.md` el deploy es
  `bash tools/install-hook.sh --host claude`. Verificado byte a byte.
- **Registro faltante de hoy más temprano:** el PR #130 (CodeRabbit sobre la
  ronda kimi+qwen de 17.3) se mergeó y deployó sin entrada propia — deploy
  `YA AL DIA` (tool+tests, hook intacto); queda registrado aquí.

## 2026-08-31 — PR #128 / cross-review de 17.3 (codex+grok) — deploy NO-OP

- **Qué traía:** los hallazgos con rojo medido del cross-review pedido por el
  operador sobre el código mergeado de 17.3 — 27 hallazgos entre los dos
  revisores. Cerrados con tests-primero (7 FAIL contra el código mergeado,
  citados en el commit): los 6 campos del rastro se redactan, `--task` ya no
  admite rutas, el parser ya no cuelga con un flag sin valor (el bug de la
  0.4, medido con rc=124), CR y líneas `#` inyectadas son malformado, y el
  grep vacío del caso (e) — error del lead — quedó con needle real más la
  aserción de que la COLA tampoco quede.
- **Merge:** `8bde4fa`. CI 9 checks en verde. El hook NO cambió (la familia de
  redacción del hook quedó como estaba; los arreglos son de la lib y el tool).
- **Deploy:** `YA AL DIA`.
- **Lo estructural va a la fila 17.8**, no a un parche: carrera ABA del
  candado, trap que borra el lock ajeno, atomicidad del append ante
  SIGKILL/ENOSPC, `--check` sin candado. Y la nota para la Phase 18: el blast
  debe APLANAR antes de redactar, porque la lib procesa por líneas.

## 2026-08-31 — PR #126 / Task 17.3 (rastro de decisiones) — deploy REAL, tras TRES rondas de gitleaks

- **Qué traía:** `tools/lib/redactar.sh` compartido, `tools/saikit-decision.sh`
  (append seguro), la batería, el rastro `17.3.tsv`, y la familia de redacción
  del hook extendida (`ghp_`/`github_pat_`/`gho_`/`sk-`/`AKIA`/`xox[bp]-`).
  Implementó DeepSeek (#122); el lead corrigió la higiene de fixtures.
- **Merge:** `aecae38` (rama `phase-17/17.3c`, head `d164316`). CI run
  `33424788197` success, con **`secrets` en verde — el criterio de esta task**.
- **Deploy:** `REPARADO` con backup fechado; vivo == master por sha256
  (`017515e21f2c8b53…`); registro completo en las 3 fases.
- **El incidente que costó tres rondas, contado entero:** gitleaks escanea el
  HISTORIAL, así que cada arreglo exigió rama nueva + borrado de la anterior
  (el force-push está prohibido por el guard). Ronda 1: fixtures con forma de
  secreto real. Ronda 2: mi corrección dejó `xox[bp]-1234567890` contiguo en
  los format strings — `slack-legacy-token` matchea el prefijo con UN segmento.
  Ronda 3: un COMENTARIO de redactar.sh con `flag=-sk-proj` de ejemplo —
  `generic-api-key` salta con palabra-clave + forma de asignación incluso en
  comentarios; se identificó agregando `-v` al job en una rama desechable
  (#125), porque sin `-v` gitleaks solo imprime el conteo.
- **Lección, tres veces pagada:** el verificador es gitleaks, no un grep
  propio. Y el candado local (`check-secrets.sh`) dejó pasar los tres — queda
  como fila 17.7.

## 2026-08-31 — PRs #120 (Task 17.1) y #119 (decisión de la Phase 18) — deploy NO-OP

- **Qué traían:** #120: la skill `saikit-verificar-app` (fuente en
  `skills/saikit-verificar-app/`, con su batería portable) — la Phase 17
  arranca. #119: la decisión del operador de que el autopilot prepara y PARA
  antes de publicar, escrita en ledger y diseño, con dos correcciones de
  CodeRabbit: el propósito de la fase contradecía la decisión diez líneas más
  arriba, y `--confirmado` ahora revalida el gate completo, no solo el sha.
- **Merges:** `7dd2ba9` (#120) y `3cb9c5b` (#119). Master en `3cb9c5b`.
- **Deploy:** `YA AL DIA`, 0 líneas de recetario. La skill nueva NO se instala
  en el perfil todavía: eso es de la 17.6, y está declarado en la fila 17.1.
- **Verificación del lead sobre #120:** reproducción propia de los tres Major
  (test falso ⇒ `n/a`; ESM ⇒ `drive.test.cjs` corre — distinguiendo fallo de
  carga de aserción del fixture; fecha rota + sha real ⇒ `unknown`). Trampa
  medida en el camino: editar un archivo del sandbox MSYS con python de Windows
  falla en silencio por la ruta `/tmp/...` — la primera medición del sello dio
  `al_dia` sobre el archivo INTACTO y no probaba nada; se repitió con `sed`.

## 2026-08-30 — PR #117 / Task 16.9 (cierre de la Phase 16) — deploy NO-OP

- **Qué traía:** guía de usuario, spec, README, archivo de la Phase 15 y filas.
  Sin código.
- **Merge:** `03ebcad`. CI run `33349348268` success: **8 jobs** del workflow,
  incluido el agregado `gate`; el PR mostraba **9 checks** en verde porque suma
  los de los bots. (La primera versión decía «9 checks» atribuyéndoselos al run,
  que tiene 8 — cross-review kimi.) Master en
  `03ebcad`; el hook vivo quedó en `10649d2e93115d67…`, el mismo de la 16.10.
- **Deploy:** `YA AL DIA`, 0 líneas de recetario. `check-hook-registration.sh`
  exit 0 sin salida.
- **Esta entrada faltaba, y su ausencia es parte del incidente de abajo.**

### Incidente: el cierre se dio por hecho sin cumplir su propia DoD

Un cross-review con codex y grok sobre el diff del cierre encontró que 16.9 se
marcó terminada sin **cuatro** de los cinco puntos de su DoD — el único cumplido
era `Plans.md ≤200 líneas`. Se completaron después:

- `tests/test_recetas.sh` → **OK**, **30 casos** (el archivo tiene 30 llamadas a
  `caso` y las corre todas; no acepta filtro).
  **La primera versión de esta entrada decía «4 casos»** (CodeRabbit lo atrapó):
  leí la salida con `tail -5` y reporté los cuatro últimos como si fueran el
  total. Es el **tercer** error de conteo de esta misma jornada y los tres tienen
  la misma causa — tomar una vista parcial por el total: «tres instrucciones» que
  eran dos, «tres puntos de la DoD» que eran cuatro, y ahora «4 casos» que son 30.
  Cuando el número importa, hay que contarlo con un comando, no leerlo de una
  cola.
- `python tools/check_context_docs.py . --sweep` → **limpio**.
- Contraste de los sentinels de la guía contra el hook. **Encontró un
  incumplimiento real:** la guía listaba `-saikit:autopilot` y el hook NO
  reconoce ese sufijo, así que escribirlo hoy da un turno normal sin avisar de
  nada. La guía ahora lo dice.
- Esta entrada del deploy-log, que era el cuarto.

**Y una corrección sobre la corrección** (cross-review kimi, misma fecha): la
primera versión de este párrafo decía «tres puntos» y listaba cuatro viñetas,
llamando «el tercero» a la cuarta. Un incidente sobre no declarar lo que no se
corrió, contando mal lo que no se corrió. Está anotado porque el error importa
menos que la forma en que se repite.

**Lo que hay que aprender de esto**, y por eso queda escrito acá y no solo en el
ledger: el cierre citó las comprobaciones que sí se corrieron y no notó las que
faltaban. Un recibo que solo lista éxitos no distingue «lo corrí y pasó» de «no
lo corrí». La DoD estaba escrita en la propia fila desde el principio.

## 2026-08-30 — PR #115 / Task 16.11 (`funcion` contiene el alcance) — deploy REAL del recetario

- **Qué traía:** `recetas/funcion.md` gana el paso 3 (nombrar y proponer aparte
  lo que aparece de más, en vez de hacerlo) y una línea nueva del recibo
  `Fuera de alcance (propuesto aparte): <…; si no hubo, ninguno>`. Manifiesto
  regenerado. El hook no cambió.
- **Merge:** `5128410`. CI run `33347396488` success. Master en `5128410`.
- **Deploy:** hook `YA AL DIA`; el instalador reportó
  `NUESTRO_DISTINTO -> funcion.md` y `-> MANIFEST.sha256` y los republicó.
  Aquí el `NUESTRO_DISTINTO` es lo ESPERADO —la receta cambió de verdad— a
  diferencia del de la 16.8, que resultó ser solo fin de línea. Comprobado en el
  perfil vivo: `~/.claude/hooks/recetas/funcion.md` ya trae el paso nuevo.
  `check-hook-registration.sh` exit 0 sin salida.
- **Por qué el manifiesto viaja con la receta:** si el sha no coincide, el hook
  NO ofrece esa receta y el recetario queda mudo sin avisar. Por eso los dos
  archivos se publican juntos.

## 2026-08-30 — PR #113 / Task 16.10 (el menú pide la conducta, no una herramienta) — deploy REAL

- **Qué traía:** el texto del menú del recetario en `recetas_menu`. Deja de pedir
  `copy its steps into your todolist` y pide `follow its steps IN ORDER`, con los
  saltos nombrados en el recibo.
- **Merge:** `0fd64db`. CI run `33342983052` success. Master en `0fd64db`.
- **Deploy:** `REPARADO: el destino era nuestro y difiere de la fuente`, con
  backup en `saikit-backups/summonaikit-harness.sh.nuestro.20260830-165734.bak`.
  Vivo == master por sha256 (`10649d2e93115d67…` en los dos), y la instrucción
  nueva está en el hook vivo (comprobado por `grep`). Registro completo en las
  3 fases.
- **Por qué importa este deploy en particular:** es el primero que cambia lo que
  el contrato le PIDE al líder en cada turno armado, en todos los hosts. Los
  anteriores agregaban capacidades; este edita la instrucción.

## 2026-08-30 — PR #110 / Task 16.8 (smoke de las 6 recetas) — deploy NO-OP del hook, pero **reparó la skill `/sencillo`**

- **Qué traía:** solo `docs/smoke-recetas-2026-08-30.md`. El hook no cambió.
- **Merge:** `28d55ad`. CI run `33339398780` success. Master en `28d55ad`.
- **Deploy:** `YA AL DIA` para el hook, pero el instalador reportó
  `NUESTRO_DISTINTO -> ~/.claude/skills/sencillo/SKILL.md` y la republicó con
  backup.
- **Qué era esa deriva, medido antes de alarmarse:** solo el **fin de línea**.
  El contenido es idéntico; la copia instalada el 2026-08-30 09:33 tenía LF (464
  bytes) y la del repo tiene CRLF (470). Una segunda corrida del deploy sale
  **limpia** (0 líneas de recetario), así que fue un desajuste de una sola vez y
  no un bucle que reescriba en cada deploy. Quedan 2 backups en
  `~/.claude/skills/sencillo/saikit-backups/`, ninguno perdido.
- **Por qué se anota igual:** un `NUESTRO_DISTINTO` sobre un archivo que nadie
  editó es exactamente el aviso que este log existe para no dejar pasar. Se
  miró, se midió y resultó inocuo — que es distinto de suponerlo.

## 2026-08-30 — PR #108 / Task 16.5 (el instalador planta el recetario y `/sencillo`) — deploy REAL y **primera vez que el recetario llega al perfil vivo**

- **Qué traía:** `install-hook.sh` planta `~/.claude/hooks/recetas/` (7 archivos +
  `MANIFEST.sha256`) y `~/.claude/skills/sencillo/SKILL.md`, con la máquina de
  estados por archivo (marca `saikit_owned`; lo ajeno se reporta y no se toca) y
  publicación todo-o-nada por directorio. `--quitar-recetas` borra solo lo
  nuestro. El advisory del recetario en `check-hook-registration.sh`.
  El hook (`summonaikit-harness.sh`) NO cambió en este PR.
- **Merge:** `aa9c0ac` (rama `phase-16/16.5`, head `463f61c`). Master en `aa9c0ac`.
- **CI:** run `33301267516` success, los 8 jobs incluido el agregado `gate`.
- **Deploy medido:** primera corrida ⇒ 9 × `AUSENTE ->` (las 7 recetas, el
  manifiesto y la skill) y todo plantado; segunda corrida ⇒ silencio sobre el
  recetario (idempotente) y `YA AL DIA` para el hook.
  `check-hook-registration.sh` ⇒ exit 0 sin salida = registro completo en las 3
  fases. **El harness levantó la skill `sencillo` en el acto**, sin reiniciar.
- **Trampa a no repetir:** la primera vez que se corrió el deploy fue con
  `install-hook.sh 2>&1 | head -8`, y salió `exit 2` sin plantar nada. NO era un
  defecto del instalador: `head` cierra el pipe y lo mata por SIGPIPE a mitad de
  la publicación. Para mirar la salida del deploy, `tee` a un archivo — nunca
  `head`.
- **Verificación del lead sobre el árbol real** (4ª ronda de cross-review, corrida
  por el lead a pedido del operador): 10 hallazgos, 6 reales cerrados con rojo
  medido uno por uno, 3 falsos positivos VERIFICADOS (entre ellos el junction de
  Windows: se creó uno con `mklink /J` y `[ -L ]` da verdadero en MSYS2) y 1
  fuera de alcance. Artefacto: `.saikit/findings/grok-16.5-r4.md`.
- **Límite declarado:** la carrera TOCTOU entre el chequeo `-L` y el borrado no
  se cierra; se declara. Ver la fila 16.5.

## 2026-08-29 — PR #105 / Tasks 16.4 + 16.6 (menú de recetas en el contrato, alias del carril fast) + PR #104 (guía de usuario) — deploy REAL (el hook cambió)

- **Qué traía:** `recetas_menu()` y `receta_valida()` en el hook — el menú se arma
  desde `recetas/MANIFEST.sha256` verificando el sha de **cada archivo**, y el
  título/carril que se inyectan al contrato se leen del **archivo autenticado**,
  nunca de las columnas del manifiesto (quien pudiera editar el manifiesto
  escribiría el contrato de cada turno armado). Alias `-saikit:pregunta` y
  `-saikit:boceto` ⇒ `lane=fast` + `receta_alias`, con guard estricto: si la
  receta no existe con su hash, el alias NO baja el carril. `podar_dir_sesion`
  limpia `receta_alias`. Del #104 no salió código de hook: guía de usuario,
  escape de pipes del ledger y dos candados de prueba.
- **Merge:** `8ca9bab` (#105, rama `phase-16/16.4-16.6`, head `df13ca9`) y
  `ebfd2e5` (#104, rama `docs/guia-usuario`, head `94931f5`). Master quedó en
  `ebfd2e5`.
- **CI:** run `33270136308` success sobre `df13ca9` (10 checks, incluido el job
  agregado `gate`); run `33273108526` success sobre `94931f5`.
- **Verificación del lead, sobre el árbol real y no sobre el reporte del autor:**
  - `mut_menu_sin_corte_frontmatter` corrida aparte ⇒ acreditada a **un solo**
    caso (`caso_g1_receta_menu_lee_solo_frontmatter`).
  - Golden regrabado auditado: 2258 líneas de estructura **idénticas** entre
    master y la rama, los 54 escenarios en el mismo orden, ningún `exit` ni
    estado cambió. Lo único que cambió es el texto del contrato y los hashes.
- **Deploy:** `tools/install-hook.sh` ⇒ `REPARADO: el destino era nuestro y
  difiere de la fuente`; backup en
  `~/.claude/hooks/saikit-backups/summonaikit-harness.sh.nuestro.20260829-132315.bak`.
  Vivo == master comprobado por sha256 (`6bcc4f9e4619e312b923…` en los dos).
- **Registro:** `tools/check-hook-registration.sh` ⇒ exit 0 **sin salida**, que
  en ese script significa registro completo en las 3 fases (el silencio es su
  diseño: "un aviso en cada arranque sin nada que decir es como se entrena a un
  operador a ignorarlos").
- **Límite declarado:** el fix del frontmatter es **preventivo**. Hoy ninguna
  receta del repo tiene `titulo:`/`carril:` fuera del frontmatter, así que el
  caso planta la situación sintéticamente; 16.5 agrega recetas y skills.

## 2026-08-28 — PR #98 / Task 16.2 (recetario fuente: 6 recetas + `00-lider`, manifiesto TSV, linter) — deploy NO-OP (el hook no cambió)

- **Qué traía:** `recetas/` (7 archivos, ≤80 líneas, español), `recetas/MANIFEST.sha256`
  (TSV por TAB, hash normalizado a LF), `tests/lib/recetas_lint.sh`,
  `tests/test_recetas.sh` (29 casos en sandbox), `tools/gen-recetas-manifest.sh`
  (`--check`, `--dir`, exit 5 en IO), `.gitattributes` con `recetas/** eol=lf`.
  Implementó DeepSeek (5 commits + merge de master); merge `89ff713`.
- **Revisión del lead (2 vueltas):** 13 sondas con archivos fuera del repo
  (81 líneas sin salto, `nombre != archivo`, `-gt`/`right`/`cursor` aceptados,
  `gt`/`Cursor`/`Bugbot`/`AskQuestion`/`/loop` rechazados, `--dir` ausente/al
  día/stale ⇒ 1/0/1) y dos mutaciones del linter (quitar `gt` del regex; volver
  a `wc -l`) que ponen el test en ROJO — el test discrimina. Cross-review real
  con grok (7 hallazgos; #2 era artefacto de base vieja, verificado); Greptile
  y CodeRabbit: 9 hilos, todos cerrados. Desviación aceptada: el borde de `gt`
  excluye `-` para no cazar el operador `-gt`.
- **¿Cambió el hook? NO** (las recetas solo son fuente; se instalan en 16.5).
  `install-hook.sh`: **YA AL DIA**. `cmp` vivo vs `master` `89ff713`: idéntico.
- **`check-hook-registration.sh`:** 3 fases OK, exit 0.
- **Proceso:** el worker no mergeó, no empujó a master, no desplegó ni tocó
  `Plans.md`; dejó un `AGENTS.md` modificado SIN commitear (fuera de alcance,
  no entró). Operador: Gon; lead desde el worktree `-wt-lead`.

## 2026-08-28 — PR #97 (plan de workers de la Phase 16, `docs/phase-16-recetario-plan.md`) — deploy NO-OP (docs-only)

- **Qué traía:** el plan paso a paso de 16.2–16.9 para DeepSeek (sin plugins;
  cada task en un turno `-saikit`), con 12 hilos de bots atendidos y 2
  residuales declarados para 16.5. Merge `60dd872`. `install-hook.sh`: YA AL
  DIA; `check-hook-registration.sh`: 3 fases OK; vivo == master byte a byte.
  Operador: Gon (lead, worktree `-wt-lead`).

## 2026-08-28 — PR #95 / Task 16.1 (plan de Phases 16–18: recetario, verificación real, autopilot) — deploy NO-OP (docs-only)

- **Qué traía:** el plan completo de las Phases 16–18 — diseño
  `docs/phase-16-18-recetario-autopilot-design.md` (D0–D24, triage de 69
  piezas de pstack, Apéndice C con las revisiones), `Plans.md` con 25 tasks y
  事前確認 acotado, spec § "Ampliación — Phases 16–18", Phases 13–14 movidas a
  `docs/plans-archivo.md`, y un fix de test: `test_adversary_artifact_contract`
  anclaba la fila 14.3 solo a `Plans.md` y se puso rojo en CI al archivarla
  (run `33196774677`); ahora sigue al ledger archivado y valida solo esa
  fila, con 4 casos sintéticos en sandbox. Merge `dd37809` (merge commit, sin
  `--delete-branch`; rama remota borrada aparte por `gh api`).
- **Revisiones del PR:** 3 revisores internos (43), Greptile P1 (1),
  cross-review externo codex + grok en paralelo (22), CodeRabbit (9) — 10
  hilos, 10 resueltos con respuesta que cita el commit. CI final: 6/6 en
  `1d455f3`.
- **¿Cambió el hook? NO.** `install-hook.sh`: **YA AL DIA** (destino nuestro y
  byte a byte igual a la fuente). `cmp` vivo vs `master` `dd37809`: idéntico.
- **`check-hook-registration.sh`:** 3 fases OK, exit 0, silencio.
- **Aprobaciones:** 事前確認 de Phases 16–18 aprobado por el operador y
  registrado en `.claude/state/plan-preapprovals.json` (v2, 5 entradas; la de
  "merge automático en repos del usuario" queda `denied` a propósito: la
  autorización real es por repo con las dos llaves).
- **Operador:** Gon (sesión Claude Code; el lead corrió el deploy).

## 2026-08-28 — Phase 15 (host dsh, PRs #84–#86 + #91; fix de master #92) — deploy NUEVO del gate dsh, verificado y firmado por el lead

- **Qué traía:** la Phase 15 completa — 15.1 captura (#84, `5c4a37d`), 15.2
  `HOST=dsh` en el hook (#85, `3c3b71f`), 15.3 adaptador `@summonaikit/dsh-gate`
  (#86; su merge `7b9680b` quedó huérfano — el contenido entró por el merge local
  `d49efea`), 15.4 instalador y 15.5 docs (commits `fc29fff`…`ebff9c8`, PRs
  #87–#90 cerrados sin mergear, entraron por `d49efea`), más el #91 (`d05284d`:
  rutas Windows en el patch + plugin en el flat module fallback, hallados en el
  turno vivo). El #85 se mergeó con `suite` en rojo (tres mutaciones ancladas al
  `case` viejo de la ceremonia quedaron obsoletas); master estuvo rojo desde
  `3c3b71f` hasta el #92 (`3327710`), que las re-ancló — medido: cada una pone
  rojo solo a su caso.
- **Deploy — dsh (una pasada, la corrió el worker desde la task — fuera del
  proceso, que lo reservaba al lead):** `bash tools/install-hook.sh --host dsh`
  instaló el hook `~/.dsh/hooks/summonaikit-harness.sh`, el adaptador
  `~/.dsh/profiles/node_modules/@summonaikit/dsh-gate/` (4 archivos, dir real en
  el fallback: dsh no resuelve un plugin custom por ruta `C:/...` y en MSYS
  `ln -s` no crea symlinks) y la entrada del patch en `~/.dsh/cordis.patch.yml`
  (bloque entre marcas: `name: '@summonaikit/dsh-gate'`, `hook:`/`bash:` en forma
  Windows `C:/...`, + las 4 personas `subagent_<rol>` inline).
- **Deploy — claude/codex/grok + perfiles (2026-08-28 00:19, lead; Greptile
  del PR #93 lo reclamó: el hook cambió en la fase y los vivos seguían en el
  sha del #81):** `install-hook.sh` REPARÓ `~/.claude/hooks` (backup
  `saikit-backups/summonaikit-harness.sh.nuestro.20260828-001911.bak`),
  `--host codex` REPARÓ `~/.codex/hooks` (`…-001916.bak`), `--host grok`
  REPARÓ `~/.grok/hooks` (`…-001923.bak`). `cmp` byte a byte contra la fuente
  (== `master` `d05284d`): **IDÉNTICO los tres**, sha
  `e563fe8064d5425e80a0013b61725066187f6dcfb66bad7afa709d2df19d1b7c`.
  Perfiles: `adversary.md` (fila dsh en la tabla por host, 15.5) REPARADO en
  `~/.claude/agents`, `~/.zcode/agents`, `~/.grok/agents`, `~/.agents/agents`
  (kimi); zcode re-REGISTRADO (4 fases, backup
  `config.json.zcode.20260828-001935.bak`). `verifier` ajeno de grok intacto
  (DESCONOCIDO — no se tocó). `check-hook-registration.sh`: **SILENCIO** en
  sus cinco formas (claude settings + local, `--codex-hooks-json`,
  `--grok-hooks-dir`, `--zcode-config`, `--dsh-home`), re-corrido y citado.
- **Verificación del lead de dsh (2026-08-28, sesión claude; sin re-desplegar dsh):** hook
  `~/.dsh/hooks/…` == `master` byte a byte; los 3 JS del plugin == `master`
  (solo CRLF); `check-hook-registration.sh --dsh-home ~/.dsh` → **SILENCIO**,
  re-corrido y citado; `dsh --profile web --dump-config` compone
  `summonaikit-gate` + las 4 `subagent_<rol>`; `dsh --version` = `0.1.1-rc.2` =
  `summonaikit.measuredAgainst`. Los profiles `headless` y `saikit-smoke` los
  instaló el worker fuera del alcance (web): se dejan, declarados; no son parte
  del deploy.
- **Turno vivo (`docs/smoke-dsh-2026-08-28.md`, en `headless`):** escenario 1
  (`-saikit` + delegación implementer→verifier→reviewer → recibo cierra) ✅;
  escenario 3 (sin `-saikit` → nada del harness) ✅; escenario 2 (cerrar sin
  recibo) NO reprodujo el GATE (observó `DELEGATED`) — declarado.
- **Turno vivo en la UI WEB (2026-08-28 07:18–07:25 PDT, operador; leído por
  el lead del `session.jsonl.zstd`, ver smoke doc § UI WEB):** escenario 1 ✅
  (contrato inyectado — literal en el `reasoning` del modelo —,
  `subagent_implementer` → `_verifier` → `_reviewer` → `_adversary` con
  artefacto esquema-conforme → adjudicación → recibo con `ADVERSARY:`);
  escenario 3 ✅ (turnos sin `-saikit` sin marcadores). El gate se cargó en el
  `dsh web` ya abierto sin reiniciar (`watchUserPatches` recarga el patch en
  vivo). **Escenario 2 (GATE en la UI) sigue `unknown`** — sin ningún followup
  del adaptador en 28 turnos; cubierto por la suite del hook y el banco del
  adaptador (spec § Límites de dsh).
- **Operador:** Gon (deploy: sesión dsh del worker; verificación, merges y
  firma: sesión claude del lead).

## 2026-08-27 — PR #81 (veto del fallo PELADO en el label, residual del #72 cerrado) — deploy REPARA los tres hooks vivos

- **Qué traía:** el residual declarado en el #72 (Greptile r3): `VERIFIED BY
  SUBAGENT: pytest -q, ok, failed.` acreditaba. Veto propio del label en dos
  pasos (`saikit_verif_fallo_pelado`: extraer `fail*`/`error*` con su palabra
  previa y sufijo, descontar negaciones de éxito — `0 failed`, `no failures`,
  `failures: 0` — y rutas/archivos del comando — `error.py`,
  `tests/errors.py` — tras normalizar la puntuación pegada). Merge `5ba0355`
  (tip `61a013e`), dos rondas de bots (4 hilos, todos atendidos con caso +
  mutación; medido que un fixture no discriminaba y se corrigió). Límites
  declarados en el spec: negación por vocabulario (`failed 0`) y un
  argumento suelto del comando que sea la palabra a secas (`pytest -k error`)
  vetan de más.
- **Deploy — hook (una pasada):** REPARADO en `~/.claude/hooks`
  (backup `saikit-backups/summonaikit-harness.sh.nuestro.20260827-083908.bak`),
  `~/.codex/hooks` (`…-083911.bak`), `~/.grok/hooks` (`…-083916.bak`). `cmp`
  byte a byte: **IDÉNTICO los tres**, sha
  `a2f4c7a8ddaf937f2238de310b108b4120f9485d8aea48739c4369aa66009f87`.
  Perfiles sin cambio (no se tocaron). `verifier` ajeno de grok intacto
  (DESCONOCIDO — no se tocó, como siempre).
- **`check-hook-registration.sh`:** SILENCIO en sus cuatro formas (claude
  settings + local, `--codex-hooks-json`, `--grok-hooks-dir`,
  `--zcode-config`), re-corrido y citado.
- **Verificación previa al merge:** CI 5/5 sobre `61a013e` (suite completa,
  quality, secrets, Greptile, CodeRabbit). Local: driver de casos (rojo/verde
  por mutación, 17 strings de sonda directa); la batería completa la corrió
  CI — regla del repo, una sola vez donde es barato.
- **Higiene de docs instalada en este mismo PR** (`install-repo-hygiene.ps1`):
  `tools/check_context_docs.py` + hook `context-docs-budget` en
  `.pre-commit-config.yaml`. Primera corrida: capa de contexto dentro de
  presupuesto; sweep de basura limpio. Cierra el `unknown` que la 13.9 dejó
  declarado ("higiene opcional, aún no corrida").
- **Operador:** Gon (sesión claude; review, merge y deploy ejecutados por el
  lead).

## 2026-08-27 — PR #72 (Phase 14: 14.2–14.4, atestación de verificación delegada) + PR #79 incluido — deploy REPARA los tres hooks vivos y los perfiles en 4 hosts

- **Qué traía:** cierre de la Phase 14 — 14.2 (vía de crédito del label
  `VERIFIED BY SUBAGENT:` en hosts de canal interno ciego, con el predicado
  sobre TODOS los spans, veto de conteo cero y juicio sobre el turno actual),
  14.3 (esquema del artefacto en `agents/adversary.md` + reviewer que declara
  malformado), 14.4 (spec/ledger). Merge `ffd9987` (tip `3ea6b1e`). El PR
  cerró con 3 rondas de bots + cross-reviews qwen r1/r2 y grok r1; el lead
  cerró los últimos tres hallazgos (Greptile P1 `head -n1`, CodeRabbit
  `0 passed`, caso faltante de `fe81de5`) — rojo medido por mutación en cada
  uno. **También cubre el PR #79** (`;` y `)` en el delimitador del strip),
  mergeado el 27 sin deploy propio: codex y grok estaban DOS PRs atrás (#75
  y #79), claude uno (#79).
- **Deploy — hook (una pasada):** el default REPARÓ `~/.claude/hooks`
  (backup `saikit-backups/summonaikit-harness.sh.nuestro.20260827-045435.bak`),
  `--host codex` REPARÓ `~/.codex/hooks` (`…-045438.bak`), `--host grok`
  REPARÓ `~/.grok/hooks` (`…-045443.bak`). `cmp` byte a byte contra la
  fuente: **IDÉNTICO los tres**, sha
  `c96e7cdfed94da4954f9d617f0321d528fb4d800ba73a34fe042ba8cba6f828c`.
- **Deploy — perfiles:** `reviewer.md` y `adversary.md` REPARADOS en
  `~/.claude/agents` (`--host claude`), `~/.zcode/agents` (`--host zcode`,
  que además re-REGISTRÓ el harness en el user-config, 4 fases, backup
  `config.json.zcode.20260827-045454.bak`), `~/.grok/agents` (con el hook) y
  `~/.agents/agents` (`--host kimi`; el port kimi ya no escribe ahí en
  paralelo — PR #77). Verificado: los 4 `adversary.md` vivos llevan
  `"attacked"` y `OMIT the timestamp` (esquema del contrato, 14.3).
- **`check-hook-registration.sh`:** SILENCIO (ningún diagnóstico en stdout/
  stderr) en sus cuatro formas — claude settings + local, `--codex-hooks-json`,
  `--grok-hooks-dir`, `--zcode-config`. El `rc` no informa: el checker siempre
  sale 0 y habla por texto (completo/incompleto/`unknown`/advisory); lo que
  acredita es el silencio, re-corrido y citado tal cual.
- **Verificación previa al merge:** CI 5/5 sobre `3ea6b1e` (suite completa,
  quality, secrets, Greptile, CodeRabbit); local contra el hook de la rama:
  `test_gate_mutations`, `test_golden_harness`, `test_hook_source`,
  `test_adversary_artifact_contract` en verde; línea base regrabada con el
  tooling del #76 (header sin la barra de escape; 0 bloques movidos).
- **Límite residual declarado (Greptile r3, hilo abierto a propósito):** un
  `failed`/`error` PELADO sin conteo (`pytest -q, ok, failed.`) no lo veta ni
  `FAILURE_SIGNAL_RE_CI/CS` ni el veto propio del label — el raíl de evento
  usa las mismas constantes, así que el label queda A LA PAR del raíl (el
  invariante de la 14.2), no más laxo. Escrito en el spec § Atestación con
  el arreglo candidato; va en un PR propio con caso + mutación + regrabado.
- **Operador:** Gon (sesión claude; review, merge y deploy ejecutados por el
  lead).

## 2026-08-26 — PR #77 (perfil adversary honesto por host + límite newline-filename) — deploy REPARA hook claude y ambos perfiles

- **Qué traía:** docs del perfil. Publica en `agents/adversary.md` la
  distinción de enforcement por host que la Phase 13 retenía: hosts CON
  atribución de tool-events (claude/grok/codex) conservan el candado
  Edit/Write; hosts SIN (kimi `not_observed`, zcode `unknown`) declaran el
  hueco y describen el enforcement real (perfil disuasivo + escaneo por
  época + gitignore). El spec gana el límite de filename con newline (misma
  clase de evasión deliberada que `touch -t`). La publicación se retuvo a
  propósito hasta que el escaneo y el gitignore existieran en el port kimi
  (P4 mergeada) y el strip de redactados quedara corregido (PR #75).
- **Deploy — hook:** el default (`install-hook.sh`) REPARÓ
  `~/.claude/hooks/summonaikit-harness.sh` — le faltaba el strip del PR
  #75, que se había mergeado sin deploy propio. Backup
  `…/saikit-backups/summonaikit-harness.sh.nuestro.20260826-131621.bak`;
  `cmp` byte a byte contra la fuente: IDÉNTICO.
- **Deploy — perfiles:** `--host kimi` y `--host claude` REPARARON el
  `adversary.md` de `~/.agents/agents/` y `~/.claude/agents/` (ambos con
  marca `saikit_owned: summonaikit-claude`, estados de backup en sus
  `saikit-backups/`). Verificado: ambos llevan el texto honesto-por-host.
  La corrida sin pisada: el port kimi terminó su trabajo en paralelo, así
  que `~/.agents/agents/` vuelve a tener un solo escritor activo.
- **`check-hook-registration.sh`:** rc=0 (registrado en las 3 fases).
- **Verificación previa al merge:** CI 4/4 (suite 5m52s, quality, secrets,
  Greptile); `pre-commit run --files` en verde; texto fuente validado
  contra el parser real de kimi-code (PROBE-ADVPORT-OK, en el port).

## 2026-08-26 — PR #73 (fix de la trampa de orden del adversary tardío) — deploy ACTUALIZA los tres hooks vivos

- **Qué traía:** un solo fix de gate. La trampa: el dedupe de `record_agent`
  conserva la posición de la PRIMERA aparición, así que un lead que ya corrió
  `implementer→verifier→reviewer` y DESPUÉS agregaba el adversary quedaba con
  `implementer,verifier,reviewer,adversary` — orden inválido para la regex de
  4 roles — y **ningún re-despacho lo arreglaba**: el turno solo salía agotando
  presupuesto. El camino honesto castigado, vivo desde la Phase 13 en los 4
  hosts. Arreglo local a `record_agent`, sin campo nuevo de estado: un
  RE-despacho del reviewer, y solo con adversary ya en `agents_seen`, mueve al
  reviewer al final (la regla protege que la adjudicación ocurra DESPUÉS del
  ataque, que es justo lo que pasó). Cualquier otro rol re-despachado conserva
  su posición.
- **Procedencia del hallazgo:** Greptile, revisando el **port** de kimi
  (PR #12 de `summonaikit-kimi`) — no el original. Confirmado acá
  ejecutándolo. La suite de 9 casos D6 de la 13.5 no lo cubría (probaba
  "adversary dos veces", no "reviewer → adversary tarde → reviewer").
- **Deploy:** sha de la fuente
  `e20ef92e2a1ba11c13edd48f33fa747dc24a1fe48c3b2b5fb691febf94bd75f7`;
  REPARADO con backup en los tres vivos — `~/.claude/hooks`
  (`.nuestro.20260825-222031.bak`), `~/.codex/hooks` (`…-222035.bak`),
  `~/.grok/hooks` (`…-222041.bak`). `cmp` byte a byte: IDÉNTICO los tres.
- **Perfiles:** sin cambio (el fix es solo del hook); no se corrió `--host
  kimi` a propósito: `~/.agents/agents/` lo comparte el port que trabaja en
  paralelo y un deploy simultáneo se pisaría.
- **`check-hook-registration.sh` en sus tres formas:** claude (settings) rc=0;
  codex (`--codex-hooks-json`) rc=0; grok (`--grok-hooks-dir`) rc=0.
- **Verificación previa al merge:** rojo medido pre-fix
  (`caso_g3_adversary_tardio_con_re_review_cierra`), `test_gate_behavior: OK`,
  `golden --check` con 54 escenarios sin divergencia (sin regrabar), CI 5/5.
- **Paridad con el port:** el port de kimi dejó la regla escrita como semántica
  ("el cierre exige reviewer DESPUÉS del último adversary") y porta la forma
  exacta desde acá, verbatim.
- **Operador:** Gon (sesión claude; deploy ejecutado por el lead).

## 2026-08-25 — PR #72 (Phase 14: 14.2–14.4) — deploy PENDIENTE del lead

- **Qué traía:** 14.2 (vía de crédito del label `VERIFIED BY SUBAGENT:` en el
  hook) + 14.3 (esquema del artefacto en `agents/adversary.md`) + 14.4
  (spec/ledger). (La 14.1, diseño, fue docs-only y no requirió deploy.) **El
  hook SÍ cambió** (14.2: constantes `SAIKIT_VERIFIED_*`, helpers
  `saikit_verif_subagente_credita`/`saikit_verif_evidence_ok`, condición de
  evidencia del Stop).
- **Deploy:** NO ejecutado en esta sesión. El deploy post-merge (`bash
  tools/install-hook.sh` + `tools/check-hook-registration.sh`) lo hace el
  lead, que además coordina el deploy a `~/.agents/agents/` (kimi). **NO se
  corrió `tools/install-hook.sh --host kimi`** desde acá: ese directorio lo
  comparte el port `summonaikit-kimi` que corre en paralelo y se pisarían.
- **Estado:** pendiente del lead tras el merge del PR #72.

## 2026-08-25 — PR #67 / Task 13.9 (cierre Phase 13) — deploy ACTUALIZA los tres hooks vivos + planta adversary en 4 hosts

- **Qué traía:** Phase 13 completa mergeada a master — diseño (PR #63 + fix
  #64), 13.2–13.6 (PR #65, merge `1d05905`, con los fixes del cross-review r2
  en el mismo PR), 13.7–13.8 (PR #66, merge `411abf2`, implementó kimi +
  fixes del cross-review r1). El hook SÍ cambió (candado adversary 13.4 +
  gate condicional 13.5).
- **Deploy del hook (tres pasadas):** primera con sha
  `12a02885902733864c682b399a04997aa4b983fcd8a6be5611b837f5eeae2b86` —
  REPARADO con backup en los tres vivos — `~/.claude/hooks`
  (backup `.nuestro.20260825-101053.bak`), `~/.codex/hooks`
  (`.nuestro.20260825-101056.bak`), `~/.grok/hooks`
  (`.nuestro.20260825-101103.bak`). El estreno EN VIVO del rol adversary
  sobre este mismo cierre (abajo) halló un HIGH en el hook → fix + segunda
  pasada (backups `.nuestro.20260825-104959/105003/105008.bak`, sha
  `064997a2…`). El candado recién deployado bloqueó después al PROPIO lead
  con un falso positivo del guard de Bash (bug vivo #4, abajo) → fix +
  tercera pasada (backups `.nuestro.20260825-105452/105457/105503.bak`),
  **sha final
  `d0639d196b06721ab075f4a0cc789d1ef6003f10b4379dc92dfdd8cece548036`**,
  `cmp` byte a byte IDÉNTICO los tres contra la fuente.
- **Perfiles:** `adversary.md` INSTALADO con marca `saikit_owned` en
  `~/.claude/agents`, `~/.zcode/agents`, `~/.grok/agents` (frontmatter
  traducido, sin `skills:`) y `~/.agents/agents` (kimi, sin `model:`/
  `effort:` — sellado 12.3). En claude y kimi, los tres perfiles preexistentes
  del vendor quedaron ADOPTADOS (`VENDOR_CONOCIDO`) y ahora llevan el ruteo
  del router. `verifier` ajeno de grok intacto (cksum 353659411, el mismo de
  7.1/7.2). zcode re-REGISTRADO (4 fases, id 5.4) en TRES corridas de
  escritura — backups `config.json.zcode.20260825-101124.bak` (la corrida
  que gritó `command not found`, bug #1), `…-101611.bak` (re-deploy limpio
  post-fix) y `…-110955.bak` (cuarta pasada, abajo); el `…-102205.bak` lo
  dejó el `--dry-run` que escribía (bug #2). **Cuarta pasada (solo
  perfiles):** la reconciliación de `agents/adversary.md` y el fix del LOW
  del estreno se editaron DESPUÉS de la primera instalación de perfiles —
  REPARADO en claude/zcode/kimi (grok ya lo tenía por la tercera pasada);
  verificado: los 4 vivos llevan el texto reconciliado.
- **BUGS VIVOS atrapados por el propio deploy (cuatro):**
  1. `--host zcode` gritó `limpiar_trads_vendor: command not found` — la
     función se declaraba DESPUÉS del dispatch de zcode (regresión del fix
     two-phase del PR #66; invisible para tests y CI porque no movía ningún
     veredicto: solo stderr sucio y trads sin limpiar). Corregido
     (declaración movida junto a `ZCODE_AGENT_ROLES` + caso que afirma la
     ausencia de `command not found`); re-deploy de zcode limpio, rc=0.
  2. Un `--host zcode --dry-run` de verificación dejó un backup REAL del
     user-config (`config.json.zcode.20260825-102205.bak`): el dispatch de
     zcode nunca miraba `DRY_RUN` (el 12.9 #4 solo cubrió claude/kimi) —
     un dry-run que escribe. Corregido (guard con reporte de clasificación
     por rol, sin tocar agentes/config/backups) + caso nuevo.
  3. **Estreno EN VIVO del rol adversary sobre su propio cierre** (artefacto
     `.saikit/findings/adversary-20260825T174034Z.json`, 4 hallazgos, máx.
     HIGH; el gitignore de la capa 3 apareció solo con su primer evento —
     D2 verificada en vivo): el HIGH — el descuento de `=[REDACTED]` dejaba
     la comilla de cierre pegada al `=` en el formato JSON que el propio
     contrato exige, y el artefacto bien redactado volvía a bloquear el
     Stop. Corregido en el hook (el strip deja un espacio) + caso con el
     fixture JSON; los dos LOW (el perfil omitía la salida por presupuesto;
     esta misma entrada omitía la registración de las 10:22) corregidos acá
     mismo. El MEDIUM (el fixture de texto plano era la única forma
     cubierta) quedó cerrado por el mismo caso JSON.
  4. **El candado bloqueó al PROPIO lead** en el primer turno armado tras
     el deploy: el guard best-effort de Bash registró como "escrituras"
     los blancos `/dev/null)` (el paréntesis de un subshell entra al token
     del regex) y `/dev/null/necho` (un `\n` literal del JSON pegado al
     blanco, con la `\` vuelta `/` por la canonicalización) — la exclusión
     solo cubría `/dev/null` exacto. Falso positivo en la entrada
     fail-closed: la sesión del lead quedó bloqueada y salió por el camino
     de presupuesto agotado (la salida documentada, ejercida en vivo).
     Corregido (exclusión por prefijo `/dev/null*`, dirección segura del
     best-effort: nada real se escribe "bajo" un archivo) + dos asserts
     nuevos en el caso de Bash best-effort.
- **`check-hook-registration.sh` en sus tres formas:** claude (settings)
  rc=0; codex (`--codex-hooks-json ~/.codex/hooks.json`) rc=0 en silencio;
  grok (`--grok-hooks-dir ~/.grok/hooks`) rc=0.
- **Operador:** Gon (sesión claude; deploy ejecutado por el lead).

## 2026-08-24 — Deploy NO-OP + PR #64 (Greptile P1 + reviews de bots) — follow-up 13.1

- **Qué traía:** **PR #64** (`0ddb3ba` + `25b94f0`, docs-only) — el P1 de
  Greptile del PR #63 ("el escaneo mezcla sesiones") integrado como fix de
  diseño: alcance del escaneo POR SESIÓN (rutas registradas como escritas
  por el adversary + mtime `>=` época de armado); el armado inicializa
  época/rutas/violación (no appendea); evasión por `touch -t` declarada
  (instancia del hueco Bash); caso DoD bidireccional + tick + touch -t.
  Además se atendieron los reviews de bots: CodeRabbit (2 Major + 1 Minor,
  los tres aceptados) y Greptile P2 (igualdad de tick). Previo: cross-review
  externo de 2 rondas (r1 codex+claude: 17 hallazgos; r2 kimi+qwen: 5 bajos
  — commits directos `ee13d87`/`cb22564`, CI en verde en ambos pushes).
- **Deploy:** NO-OP — el hook no cambió. `install-hook.sh`: "YA AL DIA";
  `check-hook-registration.sh`: exit 0.
- **CI del PR #64:** suite/quality/secrets verde en ambos pushes (runs
  32789684601, 32790280765).
- **Operador:** Gon (sesión zcode).

## 2026-08-24 — Deploy NO-OP + cierre de la Task 13.1 (PR #63, `b91c7a3`) — arranque Phase 13

- **Qué traía:** **13.1 (PR #63, `b91c7a3`)** — diseño medido del cuarto rol
  `adversary` (`docs/phase-13-adversary-design.md`, 609 líneas al momento
  del merge; 685+ tras el cross-review externo de la misma task — entradas
  históricas posteriores lo dejan claro aquí, docs-only). Decisiones: modo degradado (detección post-hoc + bloqueo en Stop; sin
  `PreToolUse` en ningún host), atribución interna medida en claude/grok/codex
  (zcode/kimi `unknown` declarados; despacho zcode confirmado EN VIVO en la
  sesión que escribió el doc — los tres despachos de la ceremonia acreditados
  en orden), artefacto dir-scoped keyless `.saikit/findings/` (diverge del
  borrador: el `session_id` no tiene canal uniforme de propagación, grok ignora
  `additionalContext` — 7.2), fail-open default + 2 excepciones fail-closed
  justificadas, tier `review`, mapeo de rol con keyword `adversar` con
  precedencia sobre la rama reviewer, escotillas DELEGATED/ROLE FALLBACK
  extendidas, 9 casos con nombre para 13.5.
- **Deploy:** NO-OP — el merge no tocó `hooks/summonaikit-harness.sh`.
  `tools/install-hook.sh`: "YA AL DIA: el destino es nuestro y byte a byte
  igual a la fuente". `tools/check-hook-registration.sh`: exit 0.
- **CI del PR:** suite/quality/secrets en verde (run 32785920816) — batería
  completa una vez, en CI (política 2026-08-15).
- **Operador:** Gon (sesión zcode).

## 2026-08-17 — Deploy NO-OP + cierre de las Tasks 11.6, 11.9 y 11.10 (PRs #48, #49, #50) y residuales de kimi (PR kimi#9)

- **Qué traía:**
  - **11.6 (PR #48, `f1d4f68`)** — captura real de zcode con el operador
    adelante. El `last_assistant_message` llega COMPLETO (4522 chars con el
    recibo); el truncado es `responsePreview`, que el hook no lee;
    `lastAssistantMessage` camel NO existe. **La rama de la 11.4 no alcanza a
    zcode**, probado por falsificación sobre el mismo payload. El camino 1 (A6
    al tmpdir) queda RECHAZADO. Residual declarado: el fallo original de GLM
    queda sin explicación medida.
  - **11.9 (PR #49, `b6eab45`)** — los 12 `*.stop.zcode.json` alineados a las
    18 claves medidas, más el candado de forma en `test_fixtures_json.sh`
    (la línea base graba conducta, no payloads, así que no podía custodiarlos).
  - **11.10 (PR #50, `4b679ae`)** — los 10 `*.prompt.zcode.json` (13 claves) y
    los 22 `*.tool.zcode.json` (21 claves). Cero veredictos movidos, MEDIDO,
    aun pisando A1 (`subagent_type` duplicado en el payload crudo) y el guard
    de la 10.15 (`toolResultPreview`).
- **Este repo NO cambió su hook** en ninguno de los tres: `install-hook.sh` ⇒
  **YA AL DIA** en los tres perfiles con copia (claude, codex, grok), `cmp`
  byte a byte contra `master` en los tres. `check-hook-registration.sh` en sus
  tres formas: exit 0.
- **En `summonaikit-kimi` (PR #9, `4c44845`)**: cierre de los dos residuales
  bajos de la 11.5. El del `awk` era **falso VERDE** (un heredoc impostor
  después del real dejaba `check_absorbed.sh` en exit 0 sobre el bloque
  equivocado), ahora con `anclas_unicas()`; el de la doble corrida **no se
  reproduce** (medido sobre las 6 corridas reales). Tools/tests only:
  `check_deploy` ⇒ AL DIA.
- **Higiene:** ramas remotas mergeadas borradas en los dos repos; las dos que
  tenían commits propios (`feat/7.6-grok-baseline`,
  `fix/paquete-A-defectos-del-gate`) se verificaron superadas —master tiene el
  mismo escenario grok con nombres reescritos— y también se borraron. Queda
  `origin/master` solo.
- **Operador:** Gon (sesión Claude).

## 2026-08-17 — Deploy NO-OP acá + deploy REAL en kimi (correcciones del review, PR #47 y PR kimi#8)

- **Qué traía acá (PR #47, `126165c`):** declaración de que la forma del
  escenario 46 NO está medida (la 5.1 midió `last_assistant_message` PRESENTE en
  un Stop real de zcode), `README-zcode.md` extendido para cubrirlo, y la fila
  11.7 corregida (la mutación de kimi fue ad-hoc, no registrada). Regrabación de
  la línea base porque el README del escenario vive DENTRO de ella: `--check`
  ANTES exit 1 señalando solo el 46, `--record` 45 escenarios, `--check` DESPUÉS
  exit 0; diff real 6 líneas agregadas / 0 quitadas.
- **Este repo NO cambió su hook**: `install-hook.sh` ⇒ **YA AL DIA** en los tres
  perfiles con copia (claude, codex, grok), los tres byte a byte iguales a
  `master` (`cmp` OK). `check-hook-registration.sh` en sus tres formas
  (settings / `--codex-hooks-json` / `--grok-hooks-dir`): exit 0.
- **Sin tocar, declarado (D7):** el agente `verifier` de grok sigue reportándose
  DESCONOCIDO — no lleva `saikit_owned`, es el mismo ajeno de 7.1/7.2.
- **En `summonaikit-kimi` (PR #8, `c534e82`) el hook SÍ cambió** (comentario del
  corte unknown honesto: declara que `implemented` sale del ESTADO y que por eso
  el corte es más ancho que su padre; más el guard del seed del wire en dos
  suites). Deploy allá corrido: `tools/install.sh` reinstaló el hook,
  `tools/check_deploy.sh` ⇒ **AL DIA**, instalado == repo byte a byte.
- **CI:** PR #47 con `quality`/`secrets`/`suite`/review verdes; PR kimi#8 con
  `suite`/`drift-absorbed`/review verdes (`drift-upstream` es de cron).
- **Operador:** Gon; correcciones del review del lead (sesión Claude).

## 2026-08-17 — Deploy NO-OP + cierre Task 11.8 (escenario dorado de canales ciegos, PR #45)

- **Qué traía:** la Task 11.8 (mitad ejecutable) — escenario dorado
  `46-zcode-ambos-canales-ciegos` que ejercita la rama unknown honesto de la
  11.4 en la capa que graba comportamiento, baseline 44→45 puramente aditiva,
  prueba negativa medida dos veces (rama neutralizada ⇒ `--check` exit 1
  señalando solo el 46) y declaración de fidelidad de los fixtures zcode
  (`tests/fixtures/escenarios/README-zcode.md`; alineación = alcance restante
  que se reabre con la 11.6).
- **Este repo NO cambió su hook**: `install-hook.sh` ⇒ YA AL DIA.
  `check-hook-registration.sh`: exit 0.
- **Operador:** Gon; cierre desde la sesión GLM/zcode (Task 11).

## 2026-08-17 — Deploy NO-OP + cierre Task 11.7 (espejo en summonaikit-kimi, PR kimi#6)

- **Qué traía:** la Task 11.7 cierra EN el repo hermano: port del unknown
  honesto de la 11.4 a su stop_gate (wire ausente ⇒ stderr + exit 0 sin ciclo
  + estado limpio; wire hallado sin recibo sigue bloqueando). Commits
  `a0134c1`+`d11984d`+`8eefd54`, mergeado por PR kimi#6; fila cerrada con el
  PR kimi#7.
- **Este repo NO cambió su hook**: `install-hook.sh` ⇒ YA AL DIA (claude vivo
  == master). `check-hook-registration.sh`: exit 0.
- **Deploy allá:** `tools/install.sh` + `tools/check_deploy.sh` en
  summonaikit-kimi ⇒ AL DIA.
- **Operador:** Gon; cierre desde la sesión GLM/zcode (Task 11).

## 2026-08-17 — Deploy a los tres perfiles con copia (Task 11.4, PR #42) + no-op (Task 11.5)

- **Qué traía la 11.4 (PR #42, fix de review `8d3dadd`):** unknown honesto en
  el Stop gate — con AMBOS canales de texto no observados (sin
  last_assistant_message/lastAssistantMessage en el payload y transcript
  ausente/ilegible/fuera de perfil), el gate cierra con diagnóstico por
  stderr, exit 0 sin consumir ciclo y estado limpio (mismo desenlace que el
  presupuesto agotado). Campo presente sin recibo sigue bloqueando. La 11.5
  vive en summonaikit-kimi (PRs kimi#4/#5); acá no tocó el hook.
- **Deploy por perfil:** claude, codex y grok **REPARADO** con backup
  (`…nuestro.20260817-005026.bak`, `…005059.bak`, `…005103.bak`). zcode sin
  copia propia (registro apunta a la de claude).
- **Verificado:** `check-hook-registration.sh` en sus tres formas (default,
  `--codex-hooks-json ~/.codex/hooks.json`, `--grok-hooks-dir ~/.grok/hooks`)
  — exit 0 las tres. `tools/golden-harness.sh --check` contra el hook
  instalado: OK, 44/44 sin veredictos movidos.
- **Operador:** Gon; merge y deploy desde la sesión GLM/zcode (Task 11).

## 2026-08-16 — Deploy NO-OP + cierre Task 11.3 (espejo en summonaikit-kimi, PR kimi#3)

- **Qué traía:** la Task 11.3 cierra EN el repo hermano: port de la guardia
  `!recibo` de 11.2 a la escotilla PAUSED de `summonaikit-harness-kimi.sh`
  (commit `1509821`, PR gon0801/summonaikit-kimi#3), con refresh del bloque
  vendorizado, re-pin de su `check_drift.sh` (`20ecee4f…`) y absorciones de
  drift que el re-pin destapó (nuestras 9.1+9.2 en `FAILURE_SIGNAL_RE_*`, el
  ancla del heredoc de 7.4 r2 y el literal `$TOOL_HINT`).
- **Este repo NO cambió su hook en la task**: `install-hook.sh` ⇒ YA AL DIA
  (byte a byte, claude vivo == master). `check-hook-registration.sh`: exit 0.
- **Deploy allá:** `tools/install.sh` + `tools/check_deploy.sh` en
  summonaikit-kimi ⇒ AL DIA (instalado == repo).
- **Operador:** Gon; cierre desde la sesión GLM/zcode (Task 11).

## 2026-08-16 — Deploy a los tres perfiles con copia (Task 11.2, PR #39)

- **Qué traía:** la Task 11.2 — la escotilla PAUSED gana la cláusula `!recibo`
  (paridad con DELEGATED), bullet del contrato en "Asking is not failing" y
  comentarios de ambas escotillas con el datapoint Kimi 2026-08-16. Único
  cambio de lógica del PR: el `if` de la escotilla.
- **Deploy por perfil:** claude YA AL DÍA (el install corrió desde la rama con
  el fix de review; el merge es idéntico byte a byte). codex y grok
  **REPARADO** con backup (`…220433.bak` y `…220438.bak`). zcode sin copia
  propia (registro apunta a la de claude). Verifier ajeno de grok intacto (D7).
- **Verificado:** `check-hook-registration.sh` en sus tres formas (default,
  `--codex-hooks-json ~/.codex/hooks.json`, `--grok-hooks-dir ~/.grok/hooks`)
  — exit 0 las tres. `tests/test_golden_baseline.sh` contra el hook
  instalado: OK.
- **Operador:** Gon; merge y deploy desde la sesión GLM/zcode (Task 11).

## 2026-08-16 — Deploy a los cuatro perfiles (master `544bc51`, PR #38 / Task 11.1)

- **Qué traía:** la Task 11.1 (higiene de base de rama, hallazgo del run de
  campo con Kimi) — bullet nuevo en las reglas permanentes (rama desde
  `origin/<default>` con fetch previo; antes del PR, `git log
  origin/<default>..HEAD` con SOLO los commits de la task) y la línea `Close:`
  del recibo pide declararlo. Solo texto de contrato; cero cambios de lógica.
- **Deploy por perfil:** claude ya estaba al día (GLM corrió `install-hook.sh`
  desde la rama; el contenido del merge es idéntico). codex y grok estaban un
  PR atrás ⇒ `install-hook.sh --host codex` y `--host grok`, ambos
  **REPARADO** con backup en sus `saikit-backups/` (`…193428.bak` y
  `…193432.bak`). zcode sin copia propia (su registro apunta a la de claude),
  nada que hacer. El verifier ajeno de grok intacto, como siempre (D7).
- **Después:** los tres perfiles con copia (`claude`, `codex`, `grok`) en
  `1627467692 120958`, byte a byte iguales a `master` (`cmp`).
- **Verificado:** `check-hook-registration.sh` en sus tres formas (claude,
  `--codex-hooks-json`, `--grok-hooks-dir`) — exit 0 las tres.
  `tests/test_golden_baseline.sh` contra el hook instalado: OK (la baseline
  regrabada en el PR #38 describe exactamente lo que corre en los perfiles).
- **Operador:** Gon; merge y deploy desde la sesión Claude que revisó el PR.

## 2026-08-16 — Deploy del perfil Grok: deuda vieja, no de la Task 10.9

Encontrada al auditar los cuatro perfiles tras el deploy de la 10.9. **No es
deuda de esa fila**: Grok se midió `ignorada` y por diseño NO recibe las reglas
permanentes. Lo que estaba mal es otra cosa y venía de antes.

- **Qué estaba desactualizado:** `~/.grok/hooks/summonaikit-harness.sh` seguía en
  `2129441864 113112`, la versión de la Phase 7.6 (`SAIKIT-CLAUDE-OWNED
  summonaikit-claude 1.0.0`). Le faltaban **50 commits** al hook — toda la
  Phase 8, la 9 y la 10. O sea que el gate de Grok corría con los defectos que
  esas fases cerraron.
- **Deploy:** `bash tools/install-hook.sh --host grok` ⇒ **REPARADO**. Quedó en
  `112284225 120124`, byte a byte igual a `master`. Backup en
  `~/.grok/hooks/saikit-backups/`.
- **El JSON de registro NO cambió** (`464166032 1894`, byte a byte): los 5
  eventos canónicos de la 7.5 siguen igual, porque la 10.9 no le agrega la fase
  de arranque a Grok — su veredicto es `ignorada`.
- **El instalador se abstuvo donde debía:** reportó `AGENTE GROK DESCONOCIDO:
  verifier — no se toco. No lleva saikit_owned`. Ese perfil de agente lo editó
  el operador a mano; el instalador no lo pisa (D7).
- **Verificado con turno real**, y las dos mitades importan porque el salto fue
  de 50 commits:
  - el turno cierra normal (`rc=0`, el modelo responde) y **sin errores de
    hook** — o sea que las fases 8-10 no rompieron nada en Grok;
  - la sesión nueva tiene **0 ocurrencias** de `SUMMONAIKIT STANDING RULES`, que
    es lo correcto: Grok NO debe recibirlas. (Cuidado con el falso positivo: hay
    4 archivos de sesión viejos que sí contienen ese texto, de turnos donde Grok
    **leyó el repo** — el string vive en el código fuente del hook y en los docs.
    Se distinguen por fecha.)
- **Estado de los cuatro perfiles tras esto:** claude, codex y grok con el hook
  de `master`; zcode sin copia propia (su registro apunta a la de claude).

## 2026-08-16 — Deploy a los perfiles zcode y Codex (cierre de la Task 10.9)

Completa el deploy de la 10.9 en los dos hosts que la medición habilitó. El
artefacto de producción de este repo es el perfil **Claude** (`AGENTS.md`), así
que estos dos van como cierre de la fila y no como deploy obligatorio.

- **zcode:** `bash tools/install-hook.sh --host zcode` ⇒ registro de **3 a 4
  fases** (id 5.4). El grupo ajeno de `SessionStart` sobrevivió. Backup en
  `~/.zcode/cli/saikit-backups/`. **No verificado en vivo por este lado:** el
  login del operador quedó en un almacén que el TUI lee y el `--prompt` headless
  no (`config.json` no tiene `apiKey`), así que la comprobación end-to-end en
  zcode queda pendiente de un turno del operador. Lo que **sí** está medido es
  que la inyección llega (turno real del TUI durante la medición).
- **Codex:** cerrado y **verificado end-to-end**. Hicieron falta **DOS** cosas, y
  la primera entrada de este día sólo nombró una:
  1. La entrada `SessionStart` en `~/.codex/hooks.json`, apendeada al FINAL
     (índice nuevo = el último, así los `trusted_hash` de los ajenos no se
     mueven), más el **trust concedido por el operador** desde una sesión
     interactiva. Verificado: los registros `hooks.json:session_start` de
     `config.toml` pasaron de **2 a 3**, y la traza del host pasó de imprimir
     **dos** `hook: SessionStart` a **tres**.
  2. **La copia del harness del propio perfil Codex estaba vieja.** `~/.codex/
     hooks/summonaikit-harness.sh` estaba en `2129441864 113112`, sin la rama de
     la 10.9: el hook corría y no emitía nada. `install-hook.sh --host codex` lo
     dejó en `112284225 120124`, byte a byte igual a `master`.
- **Prueba final (Codex), turno real:** el texto de `SUMMONAIKIT STANDING RULES`
  aparece en el rollout de la sesión como `role: "developer"`, en
  `.payload.content[0].text` — **la misma forma que la 6.2 midió para UPS**, que
  es lo que la medición de la 10.9 había predicho para esta fase.
- **Lección para el próximo deploy multi-host:** "el hook está registrado" y "el
  hook emite" son dos cosas distintas, y cada perfil tiene **su propia copia**
  del archivo. Verificar el registro sin verificar la salida deja pasar
  exactamente este caso.

## 2026-08-16 — Deploy del perfil Claude (master `51110e0`, PR #37 / Task 10.9)

- **Qué se mergeó:** PR #37 `feat/10.9-standing-rules-otros-hosts` → master. La
  Task 10.9 saca a zcode, Codex y Grok de `unknown` respecto de las reglas
  permanentes de la 10.6, **con la medición delante de cada decisión**.
  Resultado: **zcode ACEPTADA, Codex ACEPTADA, Grok IGNORADA** — dos de tres
  habilitan, y el resultado **no fue uniforme**, que es lo que justifica
  retroactivamente que la 10.6 se negara a extrapolar desde Claude.
- **Deploy:** `bash tools/install-hook.sh` ⇒ **REPARADO** (el destino era
  nuestro y difería de la fuente). **No fue no-op:** el hook vivo pasó de
  `2954439412 118023` a `112284225 120124`, byte a byte igual a `master`
  (verificado por `cksum` antes y después). Backup en
  `~/.claude/hooks/saikit-backups/summonaikit-harness.sh.nuestro.20260816-172627.bak`.
- **Registro:** `bash tools/check-hook-registration.sh` ⇒ **exit 0 en silencio**
  (las fases siguen registradas; sin advisory).
- **Qué gana el perfil vivo:** la rama de `SessionStart` ahora también emite en
  `TARGET=codex`. Para Claude el comportamiento no cambia.
- **Lo que este deploy NO hizo (y se completó después; ver la entrada de cierre
  más abajo):** los perfiles de zcode y Codex quedaron fuera, porque este paso
  fue sobre el perfil **Claude**.
  - **Regla operativa de Codex:** los índices son parte de la clave de
    confianza, así que **no se reordena** el array de una fase — reordenar
    desalinea el `trusted_hash` de los hooks ya registrados y los apaga en
    silencio.
- **Perfiles de medición, restaurados:** de los 8 archivos tocados durante la
  medición, 7 volvieron byte a byte a su cksum previo. El octavo
  (`~/.zcode/cli/config.json`) cambió **por acción del operador** —su `/login`
  escribe ahí la API key— y se verificó por estructura, no por cksum.

## 2026-08-16 — Deploy del perfil Claude (master `727049d`, PR #35 / Task 10.15)

- **Que se deployo:** el hook de `master` al perfil **Claude** con
  `bash tools/install-hook.sh`. Destino clasificado NUESTRO-pero-distinto y
  reparado con backup en
  `~/.claude/hooks/saikit-backups/summonaikit-harness.sh.nuestro.20260816-114020.bak`.
- **Que traia:** la Task 10.15 — un DESPACHO en background ya no acredita
  verificacion. Es A11 volviendo por otra puerta: la 3.8 la cerro grepeando
  senales de fracaso en la salida, y en el despacho de un job en background esa
  salida todavia no existe.
- **Despues:** vivo `2954439412 118023`, identico al repo (`cmp` byte a byte).
- **Verificado:** `tools/check-hook-registration.sh` exit 0, y
  `tests/test_golden_baseline.sh` **OK** contra el hook ya instalado. La linea
  base NO se regrabo en este cambio: `--check` dio exit 0 porque ningun
  escenario ejercita un despacho en background (deriva de identidad tolerada
  por diseno, decision 2 del arnes).
- **Efecto practico a tener presente:** a partir de ahora, lanzar la bateria en
  background NO acredita verificacion por si solo. El resultado real se declara
  en la prosa del recibo, que es donde de verdad se ve si paso o fallo.

## 2026-08-16 — Deploy del perfil Claude (master `5de0e27`, PRs #30, #33 y #34)

- **Que se deployo:** el hook de `master` al perfil **Claude**, con
  `bash tools/install-hook.sh` (no `cp`). El instalador clasifico el destino
  como NUESTRO-pero-distinto y lo reparo con backup en
  `~/.claude/hooks/saikit-backups/summonaikit-harness.sh.nuestro.20260816-110614.bak`.
- **Que traia:** las tres filas del paquete A (10.12 forma del recibo en el
  contrato, 10.13 caso de regresion del credito en background, 10.14 guarda
  contra notificaciones de tarea) mas la 10.16 (la regla permanente nombra el
  LUGAR donde correr la bateria) y la correccion de la colision de la marca.
- **Antes:** vivo `2129441864 113112`. **Despues:** vivo `3139286255 116465`,
  identico al repo (`cmp` byte a byte).
- **Verificado:** `tools/check-hook-registration.sh` sale **0 y en silencio**
  (sin advisories), y `tests/test_golden_baseline.sh` da **OK** contra el hook
  ya instalado — o sea la linea base grabada en el repo describe exactamente lo
  que corre en el perfil. Antes del deploy esa prueba fallaba en local por
  diseno, porque compara contra el vivo y el vivo estaba viejo.
- **Nota de proceso:** este deploy se hizo DESPUES de repasar los comentarios de
  coderabbit y greptile en los PRs #30 y #33 a pedido del operador. Ese repaso
  encontro un hallazgo a medias que habria llegado al perfil: un prompt humano
  que solo MENCIONA `<task-notification>` dejaba vivo el estado armado anterior
  (sintoma A4). Se corrigio en el PR #34 antes de instalar.

## 2026-08-15 — Deploy pendiente del perfil Claude (master `d41f85d`)

- **Qué se deployó:** el hook de `master` al perfil **Claude**. No corresponde a
  un PR nuevo: el PR #26 (9.8 + política de gate en CI) **cambió el hook** y su
  deploy fue sólo a `~/.codex`, así que `~/.claude/hooks/` quedó atrás.
  Detectado al revisar el cierre de la jornada: vivo `3755086874 97179` contra
  master `678207720 98088`.
- **`install-hook.sh`:** `REPARADO: el destino era nuestro y difiere de la
  fuente.` Backup:
  `~/.claude/hooks/saikit-backups/summonaikit-harness.sh.nuestro.20260815-134654.bak`
  **Vivo vs master:** cksum idéntico (`678207720 98088`).
- **`check-hook-registration.sh`:** exit 0 y silencio.
- **Verificación viva:** un turno headless `claude -p` en un repo nuevo, sin
  `-saikit`, devolvió `OK + REGLAS` — la sesión funciona y las reglas
  permanentes de 10.6 siguen llegando con el hook nuevo.
- **Regla que esto confirma:** el deploy es **por perfil**. Un PR que toca el
  hook y se deploya sólo a un host deja los otros atrás en silencio; la única
  señal es comparar `vivo` contra `origin/master`, que es justo el chequeo que
  la nota de coordinación pide hacer SIEMPRE antes de instalar.
- **Operador:** Gon.

## 2026-08-15 — PR #22 / Phase 9: seis defectos del gate (merge `637330a`)

- **Mergeado:** PR #22 `feat/phase-9-gate-defects` → master — Tasks **9.1, 9.2,
  9.4, 9.5, 9.6 y 9.7**. Reparto acordado con la sesión de Phase 6, que tomó
  9.3 y 9.8 (viven en `stop_gate`) y cerró Phase 6 en paralelo.
- **¿Cambió el hook?** **Sí**, y en seis lugares:
  - **9.4** el fallback al payload crudo se acota a `PHASE=session` (sin eso, un
    `-saikit` en un campo de resumen **armaba la ceremonia sin que nadie la
    pidiera**);
  - **9.5** la frontera izquierda del sentinel excluye `/` y `-` (referenciar
    `docs/-saikit.md` o citar `--saikit` armaba);
  - **9.6** el walker resetea `en_text`/`en_assistant` al cerrar llaves — sin
    eso **el gate CERRABA por texto que el asistente no escribió**;
  - **9.7** `podar_dir_sesion` + `barrer_estado_viejo` (TTL 14 días): `state/`
    dejaba un directorio inmortal por sesión;
  - **9.1** `failed` entra a la vía B del CI y los literales de gradle al CS
    (dotnet y gradle **reventados acreditaban verificación**);
  - **9.2** `ECHO_LEAD_RE` y el crédito deja de mirar `tool_name` (`echo pytest`
    acreditaba, y una tool MCP llamada como un runner también).
- **`install-hook.sh`:** `REPARADO: el destino era nuestro y difiere de la
  fuente.` Backup:
  `~/.claude/hooks/saikit-backups/summonaikit-harness.sh.nuestro.20260815-114439.bak`
  **Vivo vs master:** cksum idéntico (`3755086874 97179`).
- **`check-hook-registration.sh`:** exit 0 y **silencio**.
- **Gates:** `tests/run.sh` **OK (18 tests)** con `SAIKIT_HOOK_VIVO` a la fuente
  (corrida al final, tras integrar master); `pre-commit run --all-files` Passed.
- **Mutaciones:** 8 nuevas, todas atrapadas por su propio caso. Se **retiró**
  `tool_name_desacotado` (se quedó sin detector al sacar `tool_name` del
  crédito) y se **reemplazó** por `credito_por_tool_name`, que sí es observable.
- **CodeRabbit (PR #22):** 3 hallazgos, los 3 válidos y atendidos. El segundo
  proponía dejar sólo `TEST_RUNNER_CMD_RE`: **se probó y rompió tres casos
  legítimos** — esa constante cubre únicamente el runner propio del repo, así
  que habría borrado el crédito de pytest y compañía. El agujero era real, la
  receta no. El tercero encontró que mi propio caso de regresión **no probaba
  lo que decía**: el fixture ponía el `tool_name` real en `Bash`. Corregido con
  un fixture nuevo y su mutación.
- **Integración con la sesión paralela:** master avanzó con los PRs #23/#24/#25
  durante la review; se integró por **merge** (force-push prohibido). Los dos
  conflictos fueron de UNIÓN, no de decisión: las listas `CASOS_G1`/`CASOS_G4` y
  las filas 9.x de `Plans.md`. **Lección anotada:** la primera resolución salió
  invertida (en `git merge` el primer lado es HEAD, no el entrante) y pisó los
  cierres propios con el estado de master; se detectó verificando fila por fila
  después de resolver, no antes.
- **Operador:** Gon.

## 2026-08-15 — PR #19 / Task 10.6: reglas permanentes en `SessionStart` (merge `3f4f076`)

- **Mergeado:** PR #19 `feat/10.6-standing-rules-sessionstart` → master — el kit
  gana un canal para **invariantes permanentes**: en la fase `SessionStart`
  inyecta 3 reglas de velocidad **arme o no** el turno. No gatea, no arma, no
  cuenta ciclos, y **no toca el invariante del sentinel**.
- **Por qué existe, medido:** el transcript `e86ddb2c` (2026-08-14) mostró una
  task de ~7 h con **2.6 h bloqueado esperando** (51 % del tiempo de
  herramientas), ~1.75 h evitables. **La regla ya estaba** en el contrato desde
  la 10.2 — pero `harness_context()` sólo corre en el camino **armado**, y esa
  sesión nunca armó (`/goal`, sin `-saikit`). La regla existía y era invisible.
- **¿Cambió el hook?** **Sí.** `standing_rules()` + `emit_standing_rules()` y una
  rama en `start_harness` acotada a `PHASE=session` **y** `TARGET=claude`,
  después del desarme y antes del `emit_allow`.
- **`install-hook.sh`:** `REPARADO: el destino era nuestro y difiere de la
  fuente.` Backup:
  `~/.claude/hooks/saikit-backups/summonaikit-harness.sh.nuestro.20260815-001541.bak`
  **Vivo vs master:** cksum idéntico (`1303783510 88474`).
- **`check-hook-registration.sh`:** exit 0 y **silencio** — sin el advisory de
  `SessionStart` (la fase quedó registrada) y sin el advisory de A9 (el matcher
  ya cubre `Agent`).
- **Registro (acción de operador, no del instalador):** entrada `SessionStart`
  sin matcher con `PHASE=session` en `~/.claude/settings.json`, con backup
  (`settings.json.bak-10.6-20260814-215110`), las 7 entradas ajenas intactas y
  JSON validado antes de escribir. `install-hook.sh` **no** registra en Claude:
  sólo instala el archivo, y su única rama de registro es `--host zcode`.
- **Verificación viva POST-DEPLOY:** un turno headless `claude -p` en un repo
  nuevo, **sin `-saikit` y sin staging**, devolvió las 3 reglas **textuales**. La
  medición previa (antes de diseñar) ya había confirmado que `SessionStart` en
  Claude acepta `hookSpecificOutput.additionalContext`.
- **Alcance:** sólo `TARGET=claude`. zcode, Codex y Grok quedan `unknown`, no
  "no lo tienen": registrar a ciegas es el error que la 6.2 evitó por un pelo.
- **CodeRabbit (PR #19):** 3 hallazgos, los 3 válidos. Dos arreglados; el Major
  (un `summary` de sesión reanudada que cite un `-saikit` viejo hace que la
  sesión arme y las reglas no salgan) **no se arregló a propósito**: ese fallback
  es C9 / Task 9.4, cuya DoD decide conservarlo, y acotarlo puso rojo
  `caso_g6_armado_por_target`. Queda **atado por caso** y declarado como pérdida
  de cobertura.
- **Integración con la sesión paralela:** master avanzó con PR #17/#18/#20
  durante la review y el #20 tocó el hook (`TEST_RUNNER_CMD_RE`). Se integró por
  **merge** (el force-push está prohibido acá) dejando el árbol byte a byte igual
  al ya verificado, y la suite se re-corrió **después** de fusionar los dos
  cambios del hook.
- **Gates:** `tests/run.sh` OK (18 tests) con `SAIKIT_HOOK_VIVO` a la fuente;
  `pre-commit run --all-files` Passed.
- **Operador:** Gon.

## 2026-08-15 — PR #15 / Task 6.2: contrato de salida de Codex (merge `5006de7`)

- **Mergeado:** PR #15 `feat/6.2-probe-codex` → master — `probe-zcode-output.sh`
  gana `--host codex` (registro por **colocación de shim**, no mutación de
  config), el modo `block2`, cuatro guardas nuevas con su caso, veredictos
  medidos (`docs/task-6.2-salida.md`), plan (`docs/task-6.2-plan.md`) y cierre
  de la fila 6.2 con la restricción heredada escrita en la DoD de 6.4.
- **¿Cambió el hook?** **No.** Cero commits sobre `hooks/`; sólo andamiaje de
  medición (`tools/`), tests y docs.
- **`install-hook.sh`: NO se ejecutó, y es deliberado.** El merge trajo el hook
  de Phase 10 (PR #16), y el working tree de esta sesión estaba en la rama 6.2,
  o sea con el hook **anterior**. Correr el instalador desde ahí habría **pisado
  el hook vivo con una copia vieja** — el deploy habría revertido Phase 10 en
  silencio. En su lugar se verificó la igualdad, que es lo que el deploy
  realmente afirma: `cksum` del vivo == `cksum` de
  `origin/master:hooks/summonaikit-harness.sh`. Deploy **no-op verificado**.
- **`check-hook-registration.sh`:** exit 0; mismo advisory conocido de A9
  (matcher PostToolUse sin `Agent`), preexistente.
- **Medición 6.2 (contexto):** 12 turnos headless (`codex exec --json`) en
  `C:\dev\saikit-probe-codex`, Codex CLI 0.147.0, sesión nueva por turno.
  **Hallazgo que decide la 6.4:** con el MISMO JSON de bloqueo, `exit 0` ⇒ 4
  Stops y 3 `hook_prompt` (bloquea); `exit 2` ⇒ 1 Stop y 0 `hook_prompt` (no
  bloquea, 2/2). Codex **descarta el stdout del hook cuando el exit no es 0**,
  así que `emit_gate_failure` tal como emite hoy sería **decorativo** ahí.
  `additionalContext` aceptada (2/2, entra como rol `developer`); clave extra
  **rechazada** (0/3) ⇒ esquema **estricto**, al revés que zcode. Perfil
  `~/.codex` byte a byte intacto (3 cksum antes/después); ninguna config
  editada.
- **CodeRabbit (PR #15):** 4 hallazgos, los 4 verificados contra el código y
  válidos, atendidos en `559e952` — orden marca→shim (el shim quedaba vivo y
  `--quitar` se negaba a sacarlo), marca ajena que se pisaba, symlinks bajo la
  raíz del repo (esquivaban la negativa a tocar el perfil real) y un error
  factual del doc. **Límite declarado:** el caso del symlink reporta `unknown`
  en Windows/MSYS y su mutación no queda atrapada en esta máquina.
- **Vivo vs master:** cksum idéntico (`3561109110 81554`).
- **Operador:** Gon.

## 2026-08-14 — PR #14 / Task 7.2: contrato de salida Grok (merge `fcccf87`)

- **Mergeado:** PR #14 `feat/7.2-probe-grok` → master — `probe-zcode-output.sh`
  gana `--host grok` (con 2 ciclos de corrección: reviewer interno +
  cross-review Codex, 3 hallazgos), tests, veredictos medidos
  (`docs/task-7.2-salida.md`), párrafo spec y cierre de la fila 7.2.
- **¿Cambió el hook?** **No.** Sólo andamiaje de medición (`tools/`), tests y
  docs; `hooks/summonaikit-harness.sh` intacto.
- **`install-hook.sh`:** `YA AL DIA: el destino es nuestro y byte a byte igual a
  la fuente.` (deploy no-op, exit 0).
- **`check-hook-registration.sh`:** exit 0; mismo advisory conocido de A9
  (matcher PostToolUse sin `Agent`), preexistente.
- **Medición 7.2 (contexto):** 7 rondas headless + 4 variantes oráculo en
  `C:\dev\saikit-captura-grok`; bloquean `decision:block` (exit 0) y
  `continue:false`; ignoradas `exit 2`, `additionalContext` (4 formas) y
  `systemMessage`; perfil `~/.grok` byte a byte intacto (cksums), trust
  revocado. Decisión: `TARGET=grok` con forma propia; armado se re-planifica
  en 7.3.
- **Operador:** Gon.

## 2026-08-13 — PR #13 / Phase 8: auditoría del sentinel (merge `ed8ff80`)

- **Mergeado:** PR #13 `fix/phase-8-sentinel-audit` → master — tasks 8.1–8.4
  (lectores escape-aware en armado/evidencia, escotillas PAUSED/DELEGATED al
  turno actual, etiquetas `**Label**:`, contrato honesto sobre el desarme).
  Incluye el trabajo validado de la sesión anterior (escotilla DELEGATED +
  ROLE FALLBACK, Task 6.3) que estaba sin commitear.
- **¿Cambió el hook?** **Sí.** `json_top_level_decoded` para `prompt`;
  `command`/`file_path` acotados a `tool_input`; `tool_name`/`transcript_path`
  top-level; `text_hatch` para las escotillas; bold en `has_receipt_label`;
  bullets PAUSED/DELEGATED del contrato reescritos.
- **`install-hook.sh`:** `REPARADO: el destino era nuestro y difiere de la
  fuente.` Backup:
  `~/.claude/hooks/saikit-backups/summonaikit-harness.sh.nuestro.20260813-235148.bak`
- **`check-hook-registration.sh`:** registro en las 3 fases OK (exit 0). Mismo
  advisory conocido de A9 (matcher PostToolUse sin `Agent`).
- **Vivo vs master:** cksum idéntico (`2905702708 80780`).
- **Nota:** deploy corrido desde worktree limpio de `origin/master` — el árbol
  de trabajo principal tenía WIP de la Task 7.2 de otra sesión y no se tocó.
- **Operador:** Gon.

## 2026-08-13 — PR #12 / diseño Phase 7 corregido + plan 7.2 (merge `4088213`)

- **Mergeado:** PR #12 `docs/7.2-plan-y-diseno` → master — diseño de Phase 7
  actualizado con la evidencia de la 7.1 (D2/D3/D5/D6/D7, JSON canónico con
  comando PowerShell, riesgos cerrados), párrafo "Medido …, Task 7.1" en el
  spec, filas 7.2–7.6 de `Plans.md` corregidas, y `docs/task-7.2-plan.md` con
  cross-review de Codex incorporado (1 ronda, 6 hallazgos aceptados).
- **¿Cambió el hook?** **No.** Todo el PR es documentación.
- **`install-hook.sh`:** `YA AL DIA: el destino es nuestro y byte a byte igual a
  la fuente.` (deploy no-op, exit 0).
- **`check-hook-registration.sh`:** exit 0. Mismo advisory conocido de A9
  (matcher de `PostToolUse` sin `Agent`), sin cambios.
- **Vivo vs master:** cksum idéntico (`2628234111 70227`).
- **Coordinación:** deploy corrido desde el worktree; el checkout principal
  sigue con cambios sin commitear de la 6.3 (otro agente) y su `git pull`
  queda pendiente hasta que esa task commitee.
- **Operador:** Gon (vía kimi).

## 2026-08-13 — PR #11 / Task 7.1 (merge `e41f7da`)

- **Mergeado:** PR #11 `feat/7.1-grok-capture` → master — Task 7.1 medida y
  cerrada (`cc:完了`): captura de **37 payloads reales de Grok Build 1.0.3** en
  5 rondas sobre `C:\dev\saikit-captura-grok` (descartable). Writeup:
  `docs/task-7.1-captura.md`. `tools/capture-payloads.sh` gana `--host grok`
  (andamiaje de medición, como 5.1/6.1) + 13 casos en
  `tests/test_capture_payloads.sh`.
- **¿Cambió el hook?** **No.** Todo el PR es medición + herramienta de
  captura; `hooks/summonaikit-harness.sh` no se toca. Grok no se instala hasta
  la 7.6.
- **`install-hook.sh`:** `YA AL DIA: el destino es nuestro y byte a byte igual a
  la fuente.` (deploy no-op, exit 0).
- **`check-hook-registration.sh`:** exit 0. Mismo advisory conocido de A9
  (matcher de `PostToolUse` sin `Agent`), sin cambios.
- **Vivo vs master:** cksum idéntico (`2628234111 70227`), sha256
  `ef9a66bf3a51ee5b…`.
- **Lo que la 7.1 mide, y no vale perder:** **D3 se prende entero** — el rol
  del subagente llega por 3 canales (`SubagentStart`, despacho
  `spawn_subagent`, eventos internos) y el `env` map entrega
  `SUMMONAIKIT_HOOK_TARGET=grok`. `transcriptPath` cae en `~/.grok/sessions/`
  (A6 contiene). Premisas caídas, declaradas: `PostToolUseFailure` no dispara
  (las fallas llegan como `post_tool_use` con `toolResult` de error), el runner
  de hooks en Windows ejecuta vía **powershell.exe** (la 7.5 emite
  `& "bash.exe" "hook"`), la tool de escritura real es `write` además de
  `search_replace`. Perfil `~/.grok` byte a byte intacto (cksums
  antes/después); trust declarado y revocado.
- **Nota de coordinación:** el trabajo se hizo en worktree
  (`C:\dev\summonaikit-claude-7.1`) para no colisionar con la Phase 6 en curso
  en el checkout principal. El `git pull` post-merge en el checkout principal
  queda **pendiente**: tiene cambios sin commitear de la 6.3 que tocan
  `Plans.md` y bloquean el ff — se sincroniza cuando esa task commitee.
- **Operador:** Gon (vía kimi).

## 2026-08-13 — PR #10 / Phase 6 + Phase 7 + Task 6.1 (merge `454b02a`)

- **Mergeado:** PR #10 `docs/phase-6-codex-design` → master. Diseño de **Phase 6
  (codex como tercer host)** con D1–D5, diseño de **Phase 7 (Grok Build TUI)**
  con D1–D8, las 6 filas de Phase 6 en `Plans.md`, y **Task 6.1 medida y
  cerrada** (`cc:完了`).
- **¿Cambió el hook?** **No.** Todo el PR es medición, diseño y herramienta de
  captura; `hooks/summonaikit-harness.sh` no se toca. Codex no se toca hasta
  la 6.6.
- **`install-hook.sh`:** `YA AL DIA: el destino es nuestro y byte a byte igual a
  la fuente.` (deploy no-op, exit 0).
- **`check-hook-registration.sh`:** exit 0. Repite el advisory conocido de A9
  (el matcher de `PostToolUse` no cubre `Agent`), sin cambios respecto de los
  deploys anteriores.
- **Vivo vs master:** cksum idéntico (`2628234111 70227`), sha256
  `ef9a66bf3a51ee5b…`.
- **Lo que el PR mide, y no vale perder:** el rol del subagente **llega al gate
  en Codex**, en `agent_type` de primer nivel, y `:927` ya lo lee sin cambios
  ⇒ D3 se prende en la 6.4. `transcript_path` cae dentro de
  `~/.codex/sessions/` ⇒ la contención de A6 funciona allá. El perfil de codex
  del operador **no se tocó** en ninguna de las 3 corridas de captura (los 3
  cksum idénticos antes y después).
- **Revisión:** kimi (1 ronda, 5 hallazgos bajos) + **CodeRabbit (6 hallazgos,
  4 Major, los 4 legítimos)**. Con codex no se pudo — su skill `harness-review`
  secuestró el prompt; arreglado en `quality-kit` `138fe42`, medido.
- **Operador:** Gon.

## 2026-08-13 — PR #9 / Task 5.5 (merge `b401fdd`)

- **Mergeado:** PR #9 `feat/5.5-zcode-golden` → master — escenarios 17–25
  (zcode) + token `ZCODE_*` en el arnés + baseline de 25 escenarios
  (`--check` reproducible). Cierra `Plans.md` 5.5.
- **¿Cambió el hook?** **No.** 5.5 es línea base + arnés; el harness intacto.
- **`install-hook.sh`:** `YA AL DIA` (deploy no-op).
- **Vivo vs master:** cksum idéntico (`2628234111 70227`).
- **Operador:** Gon. Phase 5 del target zcode queda cerrada (5.1–5.6).

## 2026-08-12 — PR #8 / G2 skip ES (merge `024e0ec`)

- **Mergeado:** PR #8 `feat/g2-verify-skip-es` → master — `VERIFY_SKIP_RE`
  acepta `no corri` / `no se corrio` / `sin tests` (el vivo zcode decía
  "No corrí los candados" y el gate no lo leía). Cierra STOP vivo de
  5.3 y 5.4 en `Plans.md`.
- **¿Cambió el hook?** **Sí.** Skip de Verify + contrato UPS nombra las frases.
- **`install-hook.sh`:** `YA AL DIA` (el vivo se había reparado antes del
  merge; cksum idéntico `2628234111 70227`).
- **`check-hook-registration.sh`:** 3 fases OK. Advisory A9 de siempre
  (matcher PostToolUse sin `Agent`).
- **Vivo vs master:** cksum idéntico (`2628234111 70227`).
- **Operador:** Gon. El próximo `-saikit` (sesión nueva) ya usa este hook.

## 2026-08-12 — PR #7 / Task 5.6 (merge `269802a`)

- **Mergeado:** PR #7 `feat/5.6-zcode-agent-profiles` → master — Task 5.6:
  `install-hook --host zcode` instala `implementer`/`verifier`/`reviewer` en
  `~/.zcode/agents/` (tres estados, marca solo en frontmatter, bash.exe
  antes de escribir, backup al quitar). Spec + `Plans.md` 5.6.
- **¿Cambió el hook?** **No.** 5.6 tocó el instalador y las plantillas;
  `hooks/summonaikit-harness.sh` intacto.
- **`install-hook.sh`:** `YA AL DIA: el destino es nuestro y byte a byte igual
  a la fuente.` (deploy no-op del hook).
- **`install-hook.sh --host zcode`:** `REGISTRADO: harness en el user-config de
  zcode (3 fases, id 5.4).` Perfiles vivos **IDENTICO** a `agents/*.md`
  (NUESTRO_IDENTICO, sin reescribir). Backup del config:
  `~/.zcode/cli/saikit-backups/config.json.zcode.20260812-231448.bak`.
- **`check-hook-registration.sh --zcode-config`:** **silencio** (registro
  completo).
- **`check-hook-registration.sh` (Claude):** 3 fases OK. Advisory conocido de
  A9 (matcher PostToolUse sin `Agent`).
- **Vivo vs master:** cksum idéntico (`1507687064 69327`).
- **Operador:** Gon. Los tres tipos ya están en `~/.zcode/agents/`. Hace falta
  **sesión zcode nueva** para que Agent los liste (la pausada nació antes).

## 2026-08-12 — PR #2 / Task 5.1 (merge `2420162`)

- **Mergeado:** PR #2 `feat/5.1-capture-payloads-zcode` → master — Task 5.1:
  `tools/capture-payloads.sh --host zcode` (utilidad de captura) + tests TDD +
  `docs/task-5.1-captura.md` + spec + cierre de `Plans.md:97`.
- **¿Cambió el hook?** **No.** 5.1 tocó `tools/capture-payloads.sh` (utilidad)
  y docs; `hooks/summonaikit-harness.sh` intacto.
- **`install-hook.sh`:** `YA AL DIA: el destino es nuestro y byte a byte igual
  a la fuente.` (deploy no-op).
- **`check-hook-registration.sh`:** registro en las 3 fases OK (exit 0).
  Advisory conocido: el matcher PostToolUse (`Bash|Edit|Write|apply_patch|Task`)
  no cubre `Agent` — gap de A9 en Claude (en zcode lo cierra el alias
  `Task`↔`Agent` medido en esta misma task).
- **Vivo vs master:** cksum idéntico (`3605963032 66538`).
- **Operador:** Gon (config real restaurada tras `--quitar` en el cierre de 5.1).

## 2026-08-12 — PR #4 / Task 5.2 (merge `b722150`)

- **Mergeado:** PR #4 `feat/5.2-probe-zcode-output` → master — Task 5.2: probe de
  las 4 formas de stdout + `exit 2` para medir el contrato de salida de zcode
  (`tools/probe-zcode-output.sh` + tests TDD), `docs/task-5.2-salida.md`
  (veredictos), spec § segundo host corregido (esquema no estricto + `exit 2` en
  Stop sí bloquea), cierre de `Plans.md:98`. Decisión: `TARGET=claude` alcanza.
- **¿Cambió el hook?** **No.** 5.2 sumó un tool de medición + docs;
  `hooks/summonaikit-harness.sh` intacto.
- **`install-hook.sh`:** `YA AL DIA: el destino es nuestro y byte a byte igual a
  la fuente.` (deploy no-op).
- **`check-hook-registration.sh`:** registro en las 3 fases OK (exit 0). Mismo
  advisory conocido de A9 (matcher PostToolUse sin `Agent`).
- **Vivo vs master:** cksum idéntico (`3605963032 66538`).
- **Operador:** Gon (config de zcode restaurada tras `--quitar` del probe en el
  cierre de 5.2; el probe midió en sesiones nuevas sobre repo descartable).

## 2026-08-12 — PR #6 / Task 5.4 (merge `fdb875c`)

- **Mergeado:** PR #6 `feat/5.4-zcode-registration` → master — Task 5.4: el harness
  queda registrado en las 3 fases del user-config de zcode (`hooks.events.*`).
  `check-hook-registration --zcode-config` y `install-hook --host zcode` aprenden
  la segunda forma de registro. Hook: `TARGET` por `ZCODE_*` (A10 cerrado en
  zcode), budget zcode→`exit 2`, `PHASE` lee `hookEventName` (camel). Plans.md 5.4
  queda `cc:TODO` hasta el STOP vivo (turno `-saikit` real en zcode).
- **¿Cambió el hook?** **Sí.** TARGET (fallback por `ZCODE_*`), budget (rama zcode
  `exit 2`), PHASE (lectura camel además de snake).
- **`install-hook.sh`:** `REPARADO: el destino era nuestro y difiere de la fuente.`
  Backup: `~/.claude/hooks/saikit-backups/summonaikit-harness.sh.nuestro.20260812-212905.bak`
- **`install-hook.sh --host zcode`:** `REGISTRADO: harness en el user-config de
  zcode (3 fases, id 5.4).` Backup del config:
  `~/.zcode/cli/saikit-backups/config.json.zcode.20260812-212918.bak`. Primera task
  que cablea el harness en el segundo host.
- **`check-hook-registration.sh --zcode-config`:** **silencio** (registro completo:
  3 fases, `enabled:true`, sin matcher indebido en UPS/Stop, PTU cubre Agent).
- **`check-hook-registration.sh` (Claude):** 3 fases OK (exit 0). Advisory conocido
  de A9 (matcher PostToolUse sin `Agent`); en zcode lo cierra el alias
  `Task`↔`Agent` (5.1).
- **Vivo vs master:** cksum idéntico (`1507687064 69327`).
- **Operador:** Gon. **STOP §D pendiente:** turno `-saikit` real en zcode que arme
  y deje estado bajo `state/zcode/` (cierra `Plans.md:100`).

## 2026-08-12 — PR #5 / Task 5.3 (merge `053c853`)

- **Mergeado:** PR #5 `feat/5.3-host-state-isolation` → master — Task 5.3:
  `STATE_ROOT` llavea por host (`claude`/`zcode`/`other`). Un turno de zcode y
  uno de Claude sobre el mismo `$0` ya no comparten `harness-state.env` ni
  `RN_PENDING`. Plans.md 5.3 queda `cc:TODO` (STOP vivo pide el registro de 5.4).
- **¿Cambió el hook?** **Sí.** `PROJECT_DIR` pasa a
  `STATE_ROOT/$HOST/$PROJECT_KEY`.
- **`install-hook.sh`:** `REPARADO: el destino era nuestro y difiere de la
  fuente.` Backup:
  `~/.claude/hooks/saikit-backups/summonaikit-harness.sh.nuestro.20260812-190346.bak`
- **`check-hook-registration.sh`:** registro en las 3 fases OK (exit 0). Mismo
  advisory conocido de A9 (matcher PostToolUse sin `Agent`).
- **Vivo vs master:** cksum idéntico (`4023882360 67915`).
- **Operador:** Gon.

## 2026-08-14 — PR #16 / Phase 10 (Tasks 10.1, 10.2 y 10.3)

- **Mergeado:** PR #16 `feat/phase-10-ceremonia-velocidad` → master — Phase 10
  (velocidad de la ceremonia): 10.1 carril `-saikit:fast` (lane= en el estado,
  Stop exige recibo+verify pero no los 3 subagentes; clasificadores muertos
  retirados), 10.2 contrato con re-review dirigido al delta + evidencia en
  batch + coletilla al aviso RN, 10.3 role files del repo sin verificación
  duplicada. 9.x y 10.4 quedan `cc:TODO`. Plan doc commiteado byte-idéntico al
  staged de la sesión de 6.2 (coordinación en `.harness-mem/`).
- **¿Cambió el hook?** **Sí** (10.1 + 10.2: detección de lane, `write_state`
  con lane, `stop_gate` con exención de ceremonia, contrato con carril y
  bloque CHEAP-way, aviso RN con coletilla).
- **`install-hook.sh`:** `REPARADO/ACTUALIZADO: el destino era nuestro y difiere
  de la fuente` — vivo actualizado a master. **Desviación declarada:** deploy
  ejecutado desde el worktree `summonaikit-claude-wt-p10` (master) porque el
  árbol principal está ocupado por la sesión de `feat/6.2-probe-codex` con
  trabajo sin commitear; `git checkout master && git pull --ff-only` hechos en
  el worktree.
- **`check-hook-registration.sh`:** registro en las 3 fases OK (exit 0). Mismo
  advisory conocido del matcher PostToolUse sin `Agent`.
- **Vivo vs master:** cmp byte a byte idéntico (verificado por la sesión).
- **10.3 Step 4 (reinstalar perfiles al host, flujo 5.6):** sigue diferido —
  instala sólo a `~/.zcode/agents` con `--host zcode`; no se ejecutó en este
  deploy (ver fila 10.3 en Plans.md). El dir neutral `~/.agents/agents/` es
  propiedad del kit vendor y NO se toca (medido: contenido propio, no deriva
  de este repo).
- **Operador:** Gon (sesión zcode, goal "fase de eficiencia de kimi").

## 2026-08-15 — PR #17 / Task 9.10 + PR #18 / Task 10.5

- **Mergeado:** PR #17 `feat/9.10-runner-bash` — `TEST_RUNNER_RE` reconoce el
  runner bash propio (`bash tests/run.sh`, ruta absoluta, tras `&&`, invocación
  directa `./tests/run.sh`), sin reabrir A3 (`cat tests/run.sh` y
  `grep run.sh tests/run.sh` no cuentan; corpus G2 32 casos verde). Motivación:
  en hosts sin transcript legible el gate de verificación quedaba insatisfible
  para repos bash-only. PR #18 `feat/10.5-ci-linux` — job `suite` en
  ubuntu-latest (~1m35s vs ~18 min de MSYS2), `SAIKIT_CI_LINUX=1` salta los 4
  tests Windows-bound con listado explícito (capture/install/probe exigen
  bash.exe de Windows; hook_acl clasifica SIDs vía PowerShell).
- **¿Cambió el hook?** **Sí** (9.10: dos ramas nuevas en TEST_RUNNER_RE).
- **`install-hook.sh`:** vivo actualizado a master. **Desviación declarada:**
  deploy desde worktree `summonaikit-claude-wt-p10` (árbol principal sigue
  ocupado por la sesión de 6.2).
- **`check-hook-registration.sh`:** 3 fases OK, exit 0 — y sin el advisory del
  matcher: el operador agregó `Agent` (y `SendMessage`) al matcher de
  PostToolUse de settings.json (backup `.pre-agent-matcher-20260815.bak`), la
  acción que la 3.7 pedía.
- **Vivo vs master:** cmp byte a byte idéntico (verificado).
- **Operador:** Gon (sesión zcode).

## 2026-08-15 — PR #20 / Cross-review codex r1 (9.10 cmdpos + runner)

- **Mergeado:** PR #20 `feat/9.10-cmdpos` — fix del hallazgo ALTA del
  cross-review codex r1: las ramas run.sh salen de `TEST_RUNNER_RE` (vuelve a
  su forma pre-9.10) y viven en `TEST_RUNNER_CMD_RE` nueva, sin wrapper, con
  posición de comando estricta y segmentos de path — los 5 decoys
  (`bash contest/run.sh`, `bash tests/run.sh/typo`, `grep bash tests/run.sh`,
  `printf 'bash tests/run.sh'`, `echo bash tests/run.sh`) medidos en ROJO y
  cerrados. Además: resumen de SKIP del runner siempre imprime (hallazgo BAJA)
  y env-determinism del caso nuevo (`env -u SAIKIT_CI_LINUX`). Residual
  declarado en 10.5: skip linux-ci por archivo entero.
- **¿Cambió el hook?** **Sí** (constante nueva + call sites del crédito).
- **`install-hook.sh`:** vivo actualizado a master (worktree, desviación de
  siempre: árbol principal ocupado por la sesión de 6.2).
- **`check-hook-registration.sh`:** 3 fases OK, exit 0.
- **Vivo vs master:** cmp byte a byte idéntico. CI del PR: quality PASS,
  suite PASS (1m43s), CodeRabbit PASS.
- **Operador:** Gon (sesión zcode). Ronda de cross-review: 1 de 1 (tope
  respetado; residuales declarados, sin re-revisión).

## 2026-08-15 — PR #21 / Task 10.7 (ceremonia por tarea)

- **Mergeado:** PR #21 `feat/10.6-ceremonia-por-tarea` — Task 10.7: el contrato
  gana "One ceremony per task, not per edit" (batch de ediciones + la
  secuencia UNA vez sobre el diff estable; ediciones triviales no re-delegan,
  se verifican una misma con check enfocado y se declaran en el recibo).
  Origen: feedback del operador post-10.2 (re-cadena por rename/move). Sin
  cambio de condición del gate; auditoría de línea base 0 veredictos.
- **¿Cambió el hook?** **Sí** (solo texto del contrato, 6 líneas).
- **Deploy:** install desde blob de origin/master (desviación adicional: el
  worktree no pudo hacer checkout de master — lo tiene tomado el árbol
  principal de la sesión 6.2; se desplegó el blob exacto de origin/master
  post-merge y se verificó byte a byte + registro OK).
- **`check-hook-registration.sh`:** 3 fases OK, exit 0.
- **CI del PR:** quality PASS, suite PASS (1m43s), CodeRabbit PASS.
- **Operador:** Gon (sesión zcode).

## 2026-08-15 — Merge ajeno 9.4+9.5 (f78e9c7) — deploy desde sesión zcode

- **Mergeado/pusheado por la sesión de Phase 9** (`f78e9c7` fix(9.4+9.5): el
  sentinel deja de armar por texto citado — campo ausente; `0b4c77f` reserva
  de filas 6.4/6.5/6.6/9.3/9.8 en cc:WIP). Su sesión sigue trabajando; este
  deploy sincroniza el vivo a master para no dejar el artefacto atrás
  (regla: deploy tras merge, SIEMPRE — su próximo deploy será no-op).
- **Deploy:** install desde blob de origin/master (worktree, desviación de
  siempre). **Vivo vs master:** cmp byte a byte idéntico (0b4c77f).
- **`check-hook-registration.sh`:** 3 fases OK, exit 0.
- **Operador:** Gon (sesión zcode).

## 2026-08-15 — PR #23 (2e7a181): Phase 6 (6.4+6.5+línea base 6.6) + 9.3 — deploy `~/.codex` (TERCER HOST)

- **Mergeado por la sesión de Phase 6** (worktree `wt-p6`). Contenido: HOST=codex
  por señal explícita (D2), ceremonia `case claude|codex` (D3 prendida), bloqueo
  con exit 0 en codex (lo que 6.2 midió), `--host codex` en el instalador,
  manifiesto con el vivo de Codex, verificador con la cadena wrapper, frontera
  anti-cita de 9.3, y línea base con los escenarios codex 27-33.
- **Deploy `~/.codex` (PRIMERA VEZ):** `install-hook.sh --host codex` desde wt-p6
  con contenido == origin/master (diff vacío verificado antes). Destino clasificó
  **VENDOR CONOCIDO** (etiqueta del manifiesto 6.5) → backup
  `saikit-backups/summonaikit-harness.sh.vendor.20260815-094928.bak` → reemplazo
  byte a byte (cmp OK). `--restore-vendor` queda como red (backup en manifiesto).
- **Verificador codex:** silencio, exit 0 (registro→wrapper y wrapper→hook verdes).
- **Perfiles ajenos intactos:** `~/.codex/hooks.json` cksum 2271698800 y
  `~/.claude/hooks/summonaikit-harness.sh` cksum 4159550777, idénticos antes/después.
- **Turnos reales (codex exec, headless):** `-saikit` ARMÓ — contrato inyectado,
  el modelo intentó `spawn_agent`, reintentó una vez como exige el flujo y declaró
  `SUMMONAIKIT HARNESS DELEGATED - awaiting implementer` (la escotilla, viva);
  estado en `state/codex/1686855735/<session>/`. El turno pelado NO armó (1 solo
  estado tras ambos). Nota: `codex exec` corre read-only por defecto — el patch
  del turno A fue rechazado por el sandbox de Codex, no por el gate.
- **`~/.claude` NO se tocó en este deploy**: el hook vivo de Claude quedó en el
  estado del deploy anterior (98ef786) y ahora está DETRÁS de master (6.4/9.3
  también lo cambian) — le toca al flujo de siempre de la sesión zcode/Phase 9
  en su próximo ciclo (avisado por broadcast).
- **Operador:** sesión Claude Phase 6 (autónoma), Gon dormido.

## 2026-08-15 — PR #25 (e332def): review de bots del PR #23 atendida — deploy no-op

- **Contenido:** Greptile P1 (la afirmación (b) del wrapper aceptaba una mención
  solo-en-comentario — ahora exige línea de código, con el límite "no se parsea
  PowerShell" declarado, criterio de la 0.4) + minor de CodeRabbit (el caso
  aserta el diagnóstico exacto). CodeRabbit no había alcanzado a correr en el
  #23 (mergeado antes de su pasada — lección aprendida: el #25 esperó a los DOS
  bots + CI antes de mergear). ROJO medido; CI 4/4.
- **Deploy `~/.codex`:** no-op — "YA AL DIA: el destino es nuestro y byte a byte
  igual a la fuente" (el merge tocó tools/tests, no el hook). Se corre y se
  registra igual, para no perder la costumbre.
- **Operador:** sesión Claude Phase 6 (autónoma).

## 2026-08-15 — PR #24 (73307cc): detección de secretos (Recommended) — deploy ACTUALIZA el vivo ~/.claude pendiente desde el PR #23

- **Mergeado por la sesión zcode** (worktree aparte, rama `feat/ci-secret-detection`).
  Contenido: `tools/check-secrets.sh` (gitleaks por archivo + fallback grep con los
  falsos conocidos excluidos), hook local de pre-commit, job `secrets` del CI
  (gitleaks 8.30.1 sobre el historial, sha256 pineado, `persist-credentials: false`),
  `.gitleaks.toml` (config default extendida + allowlist `tests/`) y test con 12
  casos y mutaciones acreditadas. Cierra el ítem "Recommended" de Plans.md.
- **Review de bots atendida en 2 rondas:** Greptile P1 real y confirmado por
  medición (`gitleaks dir` multi-arg IGNORA los archivos y escanea el CWD entero
  — fix: una invocación por archivo, con caso que lo habría atrapado y mutación
  roja), P2 checksum del binario, CR Major-sec (`persist-credentials`,
  `curl --fail`) y 3 minors (reporte `archivo:linea`, PATH del test verificado,
  wording de Plans.md). Greptile final: **5/5, sin blockers**. CI:
  quality/secrets/suite PASS.
- **¿Cambió el hook? El PR #24 NO lo toca — pero el deploy NO fue no-op:** el
  vivo estaba DETRÁS, cksum `4159550777` (= `f78e9c7`, exactamente el estado que
  el deploy del PR #23 dejó declarado pendiente "para el próximo ciclo").
  `install-hook.sh` lo REPARÓ con backup
  `saikit-backups/summonaikit-harness.sh.nuestro.20260815-105455.bak`. El vivo
  ahora incluye lo que trajeron #23/#25: HOST=codex por señal explícita (D2),
  ceremonia `claude|codex` (D3), bloqueo con exit 0 en codex y la frontera
  anti-cita de 9.3.
- **`check-hook-registration.sh`:** 3 fases OK, exit 0.
- **Vivo vs master:** cmp byte a byte idéntico.
- **Operador:** Gon (sesión zcode).

## 2026-08-15 — PR #26 (443aa7e): 9.8 + política de gate en CI — deploy `~/.codex`

- **Mergeado por la sesión de Phase 6.** Contenido: 9.8 (el aviso RN pendiente
  solo lo borra un cierre limpio — `rn_pendiente_borrable` en el elif, `rm`
  dentro de `[ -z "$missing" ]`), validado sobre el MERGE con el lote de
  Phase 9 (19 tests, **70 mutaciones/70**, golden 34 escenarios, 0 divergencia;
  composición del bloque compartido con los `podar_dir_sesion` de 9.7a
  verificada caso por caso). Además `AGENTS.md` gana la **política de gate en
  CI** (local acotado; el job `suite` de ubuntu como gate final — este mismo PR
  la estrenó: suite completa en CI en 2m28s; excepción Windows-bound; candado
  endurecido: corredor real ≠ huérfano).
- **Bots:** CI 4/4 (suite 2m28s, quality, secrets, Greptile sin hallazgos);
  CodeRabbit quedó "in progress" al mergear (rate-limited como en #25) — si
  publica hallazgos tarde, se triagean post-merge (camino probado en #23→#25).
- **Deploy `~/.codex`:** REPARADO con backup
  `saikit-backups/summonaikit-harness.sh.nuestro.20260815-133404.bak`; vivo ==
  fuente byte a byte; `hooks.json` cksum 2271698800 intacto; verificador codex
  en silencio. **`~/.claude`:** deployado por la sesión zcode (entrada previa).
- **Operador:** sesión Claude Phase 6 (autónoma).

## 2026-08-15 — PR #27 / Task 7.3 (envelope y señal Grok) — deploy ACTUALIZA el vivo ~/.claude

- **Mergeado por la sesión zcode** (worktree `wt-p7`). Contenido: HOST=grok por
  setness de `GROK_HOOK_EVENT` (arriba de codex: `grok > codex > zcode >
  claude > other`), aliases camel con precedencia snake (`sessionId`,
  `toolName`, `toolInput`, `transcriptPath`, walker), literales
  `user_prompt_submit`/`session_start` en el case de PHASE, veto D5
  (`toolResult.exit_code` + variantes, grep acotado al objeto), `search_replace`
  en la señal de edición, filtro D6 de Stop `reason=end_turn`. **Merge con
  conflictos contra master** (los PRs #22/#26/#10.10 entraron mientras): el
  veto D5 quedó integrado dentro de la condición de crédito de 9.2; el
  auto-merge perdió 3 funciones que se recuperaron de master; la primera
  unión de listas duplicaba 82 casos y el guard de huérfanos del behavior lo
  cazó. Validación del mundo combinado: behavior 139 casos OK, **77 mutaciones
  / 77 atrapadas**, línea base 33/33 sin mover veredictos.
- **Review de bots atendida (2 rondas)**: Greptile P2 + CR Minor (señal
  exportada vacía → `${VAR+x}`, caso + mutación propios), CR Major (`write`
  con caso; la mutación pedida se declaró sin killer posible — `implemented`
  es laxo por diseño vendor). CI 4/4.
- **¿Cambió el hook? SÍ** (D2-D6). `install-hook.sh`: destino nuestro y
  distinto ⇒ REPARADO con backup
  `saikit-backups/summonaikit-harness.sh.nuestro.20260815-182912.bak`.
- **`check-hook-registration.sh`:** 3 fases OK, exit 0.
- **Vivo vs origin/master:** cmp byte a byte idéntico.
- **Operador:** Gon (sesión zcode).

## 2026-08-16 — PR #28 / Task 7.4 (ceremonia grok) + PR #29 / Task 7.5 (--host grok) — deploy ACTUALIZA el vivo ~/.claude

- **Mergeados por la sesión zcode** (worktree `wt-p7`; 7.5 implementada por subagente
  implementer supervisado). **7.4**: ceremonia `case claude|codex|grok`, bloqueo con
  `decision:block` + exit 0 (exit 2 ignorado en Grok, medido 7.2), armado re-planificado
  — el contrato viaja adosado al `reason` de cada bloqueo (único canal medido que llega
  al modelo), `TOOL_HINT` por host (los mensajes jamás nombran una tool que no exista en
  el host), budget con la forma default aceptada. **7.5**: `--host grok` (hook + JSON
  canónico + 3 perfiles con `skills:` omitido por el loader), preflight sin escribir ante
  desconocido, rollback, `--quitar-grok` (el `verifier.md` ajeno sobrevive), verificador
  `--grok-hooks-dir` con 3 afirmaciones separadas. 26+ casos nuevos con TDD.
- **Reviews de bots: 5 rondas atendidas** entre ambos PRs (Greptile P1 heredoc literal,
  aserto inerte CR, rollback de agentes, rutas con espacios, umask) + **deuda 9.1
  saldada de paso**: backticks en descripciones del catálogo de mutaciones EJECUTABAN
  comandos en cada corrida del CI (`failed: command not found`) — misma clase que la
  lección 9.10.
- **Outage de GitHub Actions**: los últimos pushes de ambos PRs no dispararon runs
  (verificado con commits vacíos y API; apps externas sí corrieron). Validación local
  completa: behavior, mutaciones (78/78 tras el merge), línea base 34 escenarios — con
  merge de master (10.8) resuelto tomando su base + regrabada auditada (30 sha, 0
  veredictos).
- **¿Cambió el hook? SÍ** (7.4). `install-hook.sh`: REPARADO con backup
  `…nuestro.20260816-004901.bak`. 7.5 es tools-only (no toca el hook).
- **`check-hook-registration.sh`:** 3 fases OK, exit 0.
- **Vivo vs origin/master:** cmp byte a byte idéntico.
- **Operador:** Gon (sesión zcode).

## 2026-08-16 — PR #32 / Task 7.6 (línea base grok + staging + install + turno real — cierre Phase 7) — deploy ACTUALIZA los tres vivos

- **Cierre de Phase 7**: escenarios 35-42 en la línea base dorada (recaptura headless,
  22 payloads, perfil byte a byte), staging real con hook de proyecto (disparó sin
  tocar el global; grok corre AMBOS registros con estados separados), install verificado
  (YA AL DIA con identidad sha256 — lo había publicado una sesión gemela paralela,
  declarada) y turno real (`-saikit` armó bajo `state/grok/`, ceremonia completa,
  cierre limpio; pelado no creó estado). El hook NO cambió en el PR (7.6 es
  tests/tools-only; 7.3/7.4 lo dejaron listo). CI del PR: 5/5, `suite` verde (gate final).
- **El vivo de Claude y Codex estaban un PR atrás** (el deploy post-PR #30 no se llegó
  a correr): `install-hook.sh` REPARADO los tres perfiles con backup —
  `~/.claude/…nuestro.20260816-075853.bak`, `~/.codex/…075856.bak`,
  `~/.grok/…075901.bak`. Los tres quedaron en `cea9f4c1…` == master byte a byte.
- **`check-hook-registration.sh`** en sus tres formas: claude (settings), codex
  (`--codex-hooks-json`), grok (`--grok-hooks-dir`) — exit 0, silencio.
- **verifier ajeno de grok**: DESCONOCIDO (no lleva marca), intacto — cksum `353659411`
  (el de 7.1/7.2). Nuestros `implementer.md`/`reviewer.md` presentes con frontmatter
  traducido.
- **Operador:** Gon (sesión zcode).
