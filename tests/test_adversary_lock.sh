#!/usr/bin/env bash
# Task 13.4 — el candado del rol adversary: deteccion post-hoc + bloqueo en el
# Stop, escaneo de secretos por sesion y gitignore del consumer.
#
# QUE AFIRMA CASO POR CASO (DoD de 13.4, docs/phase-13-adversary-design.md):
#   - caso que PERMITE: el adversary escribe su artefacto bajo .saikit/findings/
#     y el turno cierra limpio con la ceremonia completa.
#   - caso que BLOQUEA: un Edit atribuido al adversary fuera del dir registra
#     violacion y el Stop bloquea con entrada unsatisfiable-by-label.
#   - orden A2: la violacion bloquea ANTES de las escotillas PAUSED/DELEGATED.
#   - Greptile P1 BIDIRECCIONAL, con el escaneo corrido de verdad: un artefacto
#     con secreto de una sesion ANTERIOR (mtime pre-epoca) no bloquea; uno de la
#     sesion ACTUAL si — incluida la variante con estado previo en disco, donde
#     el armado INICIALIZA (reemplaza, jamas appendea) epoca/rutas/violacion.
#   - Greptile P2: mtime IGUAL a la epoca escanea (>=, no estricto).
#   - CodeRabbit #64-a: mtime retrocedido con touch sale del escaneo — limite
#     del filtro mtime citado, instancia del hueco Bash declarado.
#   - traversal ../, ruta absoluta, symlink en el file_path Y symlink del
#     propio findings/ (claude #9: findings symlink = violacion de setup).
#   - Bash best-effort: redireccion/heredoc/tee OBVIOS detectados; /dev/null y
#     programas entre comillas (awk '$2 > n') no dan falso positivo; cp queda
#     fuera (hueco declarado).
#   - gitignore del consumer: idempotente, jamas reescribe uno ajeno, y sin
#     sesion armada no se crea nada (alcance por sesion, A1).
#   - falla de infraestructura: postura fail-open (Core Rule 1), sin crash.
#
# La mitad mutation-test vive al final: cada mutacion rompe UNA condicion del
# candado y algun caso tiene que ponerse rojo — la acreditacion que pide la DoD.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/hook_lab.sh"

if [ ! -r "$here/lib/hook_bajo_prueba.sh" ]; then
  echo "test_adversary_lock: unknown — falta tests/lib/hook_bajo_prueba.sh; no se pudo resolver que archivo probar." >&2
  exit 3
fi
. "$here/lib/hook_bajo_prueba.sh"
vivo="$(resolver_hook_bajo_prueba "$here/.." "test_adversary_lock")" \
  || exit "$SAIKIT_EXIT_UNKNOWN"

fail=0
CASO_ROJO=0
_mal()      { printf '      FAIL: %s\n' "$1"; CASO_ROJO=1; }
_igual()    { if [ "$2" != "$3" ]; then _mal "$1: esperaba [$3], dio [$2]"; fi; }
_vacio()    { if [ -n "$2" ]; then _mal "$1: esperaba vacio, dio [$(printf '%s' "$2" | head -c 200)]"; fi; }
_no_vacio() { if [ -z "$2" ]; then _mal "$1: esperaba algo, quedo vacio"; fi; }
_contiene() { if ! printf '%s' "$2" | grep -Fq "$3"; then _mal "$1: no contiene [$3]"; fi; }
_no_contiene() { if printf '%s' "$2" | grep -Fq "$3"; then _mal "$1: NO deberia contener [$3]"; fi; }

# El banco se monta ANTES del primer caso (el driver de abajo corre cada caso
# con estado y arbol del consumer recien lavados).
tmp="$(mktemp -d "${TMPDIR:-/tmp}/saikit-advlock-XXXXXX")" || exit 1
if ! lab_init "$vivo"; then
  echo "test_adversary_lock: FAIL — no se pudo montar el banco de pruebas" >&2
  rm -rf "$tmp"
  exit 1
fi
trap 'lab_fin; rm -rf "$tmp"' EXIT

# Cada caso arranca de cero: estado borrado y arbol del consumer virgen. Sin
# esto, el .saikit/ de un caso contamina el alcance del escaneo del siguiente.
adv_reset() {
  lab_limpiar_estado
  rm -rf "$LAB/proyecto" 2>/dev/null || true
  mkdir -p "$LAB/proyecto" || true
}

caso() { printf '  caso: %s\n' "$1"; CASO_ROJO=0; adv_reset; }
fin_caso() {
  if [ "$CASO_ROJO" -ne 0 ]; then
    printf '    ROJO: %s\n' "$1" >&2
    fail=1
  else
    printf '    ok: %s\n' "$1"
  fi
}

# ------------------------------------------------------------------- fixtures
# Un evento de Edit DENTRO del subagente adversary: el rol viaja en agent_type
# de primer nivel (forma medida Task 3.7 / fixture 16) y el blanco en
# tool_input.file_path (forma del lab).
adv_payload_edit_interno() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","prompt_id":"adv00000-0000-4000-8000-000000000001","permission_mode":"auto","agent_id":"aadv00001adversa","agent_type":"%s","effort":{"level":"xhigh"},"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b","replace_all":false},"tool_response":{"filePath":"%s","structuredPatch":[]},"tool_use_id":"toolu_01a4d5e6f7a8b9c0d1e2f3a4","duration_ms":1200}' "$1" "$2" "$2"
}

# Recibo del turno con adversary: desde 13.5 el gate exige la linea ADVERSARY
# cuando el turno corrio un adversary (label-only), asi que el recibo verde la
# lleva — igual que _RECIBO_ADV del gate_cases.
_ADV_RECIBO='SUMMONAIKIT HARNESS RECEIPT\n- Understand: pediste atacar el cambio con un adversary.\n- Implement: el cambio y el artefacto de hallazgos quedaron escritos.\n- Verify: se corrio pytest.\n- Review: sin hallazgos.\n- Close: entregado.\n- ADVERSARY: 2 hallazgos, severidad máxima media.\n- Retro: none.'

_TEXTO_PAUSA='Espere: SUMMONAIKIT HARNESS PAUSED - awaiting your answer'

# Armar la sesion (la epoca de armado viaja al estado) y despachar adversary.
adv_armar() {
  lab_run prompt claude "$(lab_payload_prompt '-saikit ataca el cambio con adversary')"
}
adv_despachar() {
  lab_run tool claude "$(lab_payload_agent 'adversary')"
}

# Sembrar estado COMPLETO a mano (los 10 campos, forma de 13.4) para simular el
# estado sobreviviente de una sesion muerta con la misma llave.
adv_sembrar_estado_previo() {
  mkdir -p "$(dirname "$LAB_ESTADO_PATH")" 2>/dev/null || true
  {
    printf 'task_hash=viejo\n'
    printf 'cycle=0\n'
    printf 'implemented=1\n'
    printf 'verified=0\n'
    printf 'agents_seen=implementer,adversary\n'
    printf 'lane=full\n'
    printf 'adv_epoch=2020-01-01T00:00:00Z\n'
    printf 'adv_paths=%s\n' "$1"
    printf 'adv_violation=1\n'
    printf 'adv_violation_paths=/fuera/viejo.ts\n'
  } > "$LAB_ESTADO_PATH"
}

# Symlinks REALES o caso saltado con declaracion: en MSYS `ln -s` copia por
# default y un "symlink" que es copia prueba otra cosa (o nada). El CI de Linux
# los crea siempre; local puede quedar not_observed (Core Rule 2).
adv_symlink_o_skip() {
  MSYS=winsymlinks:nativestrict ln -s "$1" "$2" 2>/dev/null \
    || ln -s "$1" "$2" 2>/dev/null || return 1
  [ -L "$2" ] || { rm -f "$2" 2>/dev/null; return 1; }
  return 0
}

# Pre-vuelo de las herramientas de epoca que el escaneo y los casos necesitan
# (GNU date/touch). Si faltan, los casos que dependen de ellas se declaran
# saltados, no pasan como verde.
ADV_EPOCA_OK=0
_adv_touch_probe="$(mktemp)"
if date -u -d '2026-01-01T00:00:00Z' +%s >/dev/null 2>&1 \
   && touch -d '2020-01-01T00:00:00Z' "$_adv_touch_probe" 2>/dev/null; then
  ADV_EPOCA_OK=1
fi
rm -f "$_adv_touch_probe"

# -------------------------------------------------------------------- casos

caso "advlock_permite_escribir_el_artefacto"
advlock_permite_escribir_el_artefacto() {
  mkdir -p "$LAB/proyecto/.saikit/findings"
  adv_armar
  lab_run tool claude "$(lab_payload_agent 'implementer')"
  lab_run tool claude "$(lab_payload_agent 'verifier')"
  adv_despachar
  lab_run tool claude "$(adv_payload_edit_interno adversary '.saikit/findings/adversary-20260824T120000Z.json')"
  _igual "violacion registrada" "$(lab_estado adv_violation)" ""
  _contiene "ruta permitida registrada" "$(lab_estado adv_paths)" ".saikit/findings/adversary-20260824T120000Z.json"
  _contiene "gitignore creado" "$(cat "$LAB/proyecto/.saikit/findings/.gitignore" 2>/dev/null)" '*'
  lab_run tool claude "$(lab_payload_agent 'reviewer')"
  lab_run tool claude "$(lab_payload_bash 'pytest -q')"
  lab_run stop claude "$(lab_payload_stop "$_ADV_RECIBO")"
  _igual "exit code del cierre" "$LAB_RC" "0"
  if lab_hay_estado; then _mal "un cierre limpio debe borrar el estado del turno"; fi
}
advlock_permite_escribir_el_artefacto; fin_caso "advlock_permite_escribir_el_artefacto"

caso "advlock_bloquea_escritura_fuera"
advlock_bloquea_escritura_fuera() {
  mkdir -p "$LAB/proyecto/src"
  adv_armar
  adv_despachar
  lab_run tool claude "$(adv_payload_edit_interno adversary 'src/foo.ts')"
  _igual "violacion registrada" "$(lab_estado adv_violation)" "1"
  _contiene "ruta de la violacion" "$(lab_estado adv_violation_paths)" 'src/foo.ts'
  lab_run stop claude "$(lab_payload_stop 'Listo.')"
  _igual "exit code" "$LAB_RC" "2"
  _contiene "motivo" "$LAB_ERR" 'adversary'
}
advlock_bloquea_escritura_fuera; fin_caso "advlock_bloquea_escritura_fuera"

caso "advlock_bloqueo_antes_de_escotillas"
advlock_bloqueo_antes_de_escotillas() {
  mkdir -p "$LAB/proyecto/src"
  adv_armar
  adv_despachar
  lab_run tool claude "$(adv_payload_edit_interno adversary 'src/foo.ts')"
  _igual "violacion registrada" "$(lab_estado adv_violation)" "1"
  # A2: la escotilla PAUSED no puede perdonar una violacion — cero ciclos, cero
  # senal seria eludir la unica entrada fail-closed del diseno.
  lab_run stop claude "$(lab_payload_stop "$_TEXTO_PAUSA")"
  _igual "exit code con PAUSED + violacion" "$LAB_RC" "2"
  _contiene "motivo" "$LAB_ERR" 'adversary'
  # Idem DELEGATED (con la forma adversary, que 13.5 agrega a la escotilla).
  lab_run stop claude "$(lab_payload_stop 'SUMMONAIKIT HARNESS DELEGATED - awaiting adversary')"
  _igual "exit code con DELEGATED + violacion" "$LAB_RC" "2"
  _contiene "motivo" "$LAB_ERR" 'adversary'
}
advlock_bloqueo_antes_de_escotillas; fin_caso "advlock_bloqueo_antes_de_escotillas"

caso "advlock_secreto_sesion_actual_bloquea_y_anterior_no"
advlock_secreto_sesion_actual_bloquea_y_anterior_no() {
  [ "$ADV_EPOCA_OK" = "1" ] || { printf '    SKIP declarado: sin GNU date/touch no se puede fijar la epoca\n'; return 0; }
  mkdir -p "$LAB/proyecto/.saikit/findings"
  printf 'repro output: token=sekret-alpha-123\n' > "$LAB/proyecto/.saikit/findings/adversary-viejo.json"
  touch -d '2020-01-01T00:00:00Z' "$LAB/proyecto/.saikit/findings/adversary-viejo.json"
  adv_armar
  adv_despachar
  # (a) artefacto con mtime ANTERIOR a la epoca = sesion anterior: NO bloquea.
  lab_run stop claude "$(lab_payload_stop 'Listo.')"
  _no_contiene "sin secreto de sesion anterior" "$LAB_ERR" 'adversary-viejo.json'
  # (b) artefacto de ESTA sesion (mtime >= epoca, escrito por Bash): SI bloquea,
  # nombrando archivo y linea, JAMAS el contenido.
  printf 'repro output: token=sekret-beta-456\n' > "$LAB/proyecto/.saikit/findings/adversary-actual.json"
  lab_run stop claude "$(lab_payload_stop 'Listo.')"
  _igual "exit code con secreto actual" "$LAB_RC" "2"
  _contiene "nombra archivo" "$LAB_ERR" 'adversary-actual.json'
  _contiene "nombra linea" "$LAB_ERR" ':1'
  _no_contiene "no muestra el contenido" "$LAB_ERR" 'sekret-beta-456'
}
advlock_secreto_sesion_actual_bloquea_y_anterior_no; fin_caso "advlock_secreto_sesion_actual_bloquea_y_anterior_no"

caso "advlock_armado_inicializa_estado_previo"
advlock_armado_inicializa_estado_previo() {
  [ "$ADV_EPOCA_OK" = "1" ] || { printf '    SKIP declarado: sin GNU date/touch no se puede fijar la epoca\n'; return 0; }
  mkdir -p "$LAB/proyecto/.saikit/findings"
  printf 'repro output: token=sekret-previo-789\n' > "$LAB/proyecto/.saikit/findings/adversary-fantasma.json"
  # El artefacto fantasma es de una sesion ANTERIOR: su mtime queda claramente
  # pre-epoca (sin el touch, la igualdad de tick del mismo segundo lo dejaria
  # DENTRO del alcance — Greptile P2 — y el caso mediria otra cosa).
  touch -d '2020-01-01T00:00:00Z' "$LAB/proyecto/.saikit/findings/adversary-fantasma.json"
  # Estado sobreviviente de una sesion muerta con la MISMA llave: violacion
  # pendiente + ruta registrada vieja + epoca vieja (CodeRabbit Major #64-b).
  adv_sembrar_estado_previo "$LAB/proyecto/.saikit/findings/adversary-fantasma.json"
  adv_armar
  _no_vacio "epoca nueva presente" "$(lab_estado adv_epoch)"
  _no_contiene "epoca vieja fuera" "$(lab_estado adv_epoch)" '2020-01-01'
  _igual "violacion vieja fuera" "$(lab_estado adv_violation)" ""
  _igual "rutas viejas fuera" "$(lab_estado adv_paths)" ""
  adv_despachar
  # Ni la violacion fantasma ni el secreto de la ruta vieja bloquean ahora: el
  # artefacto fantasma quedo fuera de alcance (no registrado, mtime pre-epoca).
  # Las aserciones miran el NOMBRE de archivo, no el valor del secreto: el
  # bloqueo jamas muestra el contenido, asi que el valor no discrimina.
  lab_run stop claude "$(lab_payload_stop 'Listo.')"
  _no_contiene "sin violacion fantasma" "$LAB_ERR" 'viejo.ts'
  _no_contiene "sin secreto fantasma" "$LAB_ERR" 'adversary-fantasma.json'
  # Y un secreto NUEVO de esta sesion sigue bloqueando (el armado no mato el
  # escaneo, lo reinicio).
  printf 'repro output: token=sekret-nuevo-000\n' > "$LAB/proyecto/.saikit/findings/adversary-nuevo.json"
  lab_run stop claude "$(lab_payload_stop 'Listo.')"
  _igual "exit code con secreto nuevo" "$LAB_RC" "2"
  _contiene "nombra archivo nuevo" "$LAB_ERR" 'adversary-nuevo.json'
}
advlock_armado_inicializa_estado_previo; fin_caso "advlock_armado_inicializa_estado_previo"

caso "advlock_mtime_igual_a_epoca_escanea"
advlock_mtime_igual_a_epoca_escanea() {
  [ "$ADV_EPOCA_OK" = "1" ] || { printf '    SKIP declarado: sin GNU date/touch no se puede fijar la epoca\n'; return 0; }
  mkdir -p "$LAB/proyecto/.saikit/findings"
  adv_armar
  adv_despachar
  _epoca="$(lab_estado adv_epoch)"
  _no_vacio "epoca en estado" "$_epoca"
  printf 'token=sekret-tick-111\n' > "$LAB/proyecto/.saikit/findings/adversary-tick.json"
  # Greptile P2: la igualdad de tick cuenta (>=, no estricto) — algunos
  # filesystems resuelven a 1 s y la igualdad es plausible, no teorica.
  touch -d "$_epoca" "$LAB/proyecto/.saikit/findings/adversary-tick.json"
  lab_run stop claude "$(lab_payload_stop 'Listo.')"
  _igual "exit code con mtime == epoca" "$LAB_RC" "2"
  _contiene "nombra archivo" "$LAB_ERR" 'adversary-tick.json'
}
advlock_mtime_igual_a_epoca_escanea; fin_caso "advlock_mtime_igual_a_epoca_escanea"

caso "advlock_mtime_retrocedido_no_escanea"
advlock_mtime_retrocedido_no_escanea() {
  [ "$ADV_EPOCA_OK" = "1" ] || { printf '    SKIP declarado: sin GNU date/touch no se puede fijar la epoca\n'; return 0; }
  mkdir -p "$LAB/proyecto/.saikit/findings"
  adv_armar
  adv_despachar
  printf 'token=sekret-evasor-222\n' > "$LAB/proyecto/.saikit/findings/adversary-evasor.json"
  # CodeRabbit Major #64-a: un touch pre-armado saca al artefacto del escaneo.
  # Limite citado del filtro mtime: instancia del hueco Bash best-effort — el
  # escaneo persigue persistencia ACCIDENTAL, no a un evasor deliberado (eso
  # es trabajo del reviewer leyendo el artefacto).
  touch -d '2020-01-01T00:00:00Z' "$LAB/proyecto/.saikit/findings/adversary-evasor.json"
  lab_run stop claude "$(lab_payload_stop 'Listo.')"
  _no_contiene "el evasor no es bloqueado por el grep" "$LAB_ERR" 'adversary-evasor.json'
}
advlock_mtime_retrocedido_no_escanea; fin_caso "advlock_mtime_retrocedido_no_escanea"

caso "advlock_traversal_y_ruta_absoluta"
advlock_traversal_y_ruta_absoluta() {
  mkdir -p "$LAB/proyecto/src"
  adv_armar
  adv_despachar
  # Traversal relativo: ../fuera.ts resuelve FUERA del root del proyecto.
  lab_run tool claude "$(adv_payload_edit_interno adversary '../fuera.ts')"
  _igual "violacion por traversal" "$(lab_estado adv_violation)" "1"
  _contiene "ruta canonica registrada" "$(lab_estado adv_violation_paths)" 'fuera.ts'
  # Ruta absoluta (dinamica: apunta al propio sandbox del lab).
  lab_run tool claude "$(adv_payload_edit_interno adversary "$LAB/proyecto/src/foo.ts")"
  _contiene "violacion por absoluta" "$(lab_estado adv_violation_paths)" 'src/foo.ts'
  # El traversal desde el propio findings tambien es fuera (canonicalizado).
  lab_run tool claude "$(adv_payload_edit_interno adversary '.saikit/findings/../../escape.ts')"
  _contiene "traversal desde findings" "$(lab_estado adv_violation_paths)" 'escape.ts'
}
advlock_traversal_y_ruta_absoluta; fin_caso "advlock_traversal_y_ruta_absoluta"

caso "advlock_symlinks"
advlock_symlinks() {
  mkdir -p "$LAB/afuera"
  adv_armar
  adv_despachar
  # (a) symlink EN el file_path dentro de findings apuntando afuera: el blanco
  # canonico del enlace esta fuera => violacion, no ruta permitida.
  printf 'secreto\n' > "$LAB/afuera/target.txt"
  if adv_symlink_o_skip "$LAB/afuera/target.txt" "$LAB/proyecto/.saikit/findings/eye.json"; then
    lab_run tool claude "$(adv_payload_edit_interno adversary '.saikit/findings/eye.json')"
    _contiene "symlink en file_path es violacion" "$(lab_estado adv_violation_paths)" 'eye.json'
  else
    printf '    SKIP declarado: sin symlinks reales (MSYS copia); el CI de Linux los ejercita\n'
  fi
  # (b) findings/ MISMO es un symlink (plantable por el hueco Bash): setup
  # violado, TODO lo que caiga ahi es violacion (claude #9).
  lab_limpiar_estado
  rm -rf "$LAB/proyecto/.saikit"
  mkdir -p "$LAB/proyecto/.saikit"
  if adv_symlink_o_skip "$LAB/afuera" "$LAB/proyecto/.saikit/findings"; then
    adv_armar
    adv_despachar
    lab_run tool claude "$(adv_payload_edit_interno adversary '.saikit/findings/dentro-del-enlace.json')"
    _igual "findings symlink = violacion de setup" "$(lab_estado adv_violation)" "1"
  else
    printf '    SKIP declarado: sin symlinks reales (MSYS copia); el CI de Linux los ejercita\n'
  fi
}
advlock_symlinks; fin_caso "advlock_symlinks"

caso "advlock_bash_best_effort"
advlock_bash_best_effort() {
  mkdir -p "$LAB/proyecto/src" "$LAB/proyecto/data"
  adv_armar
  adv_despachar
  # Redireccion obvia fuera del dir: violacion.
  lab_run tool claude "$(lab_payload_bash_en_subagente adversary 'echo x > src/out.txt')"
  _igual "redireccion fuera" "$(lab_estado adv_violation)" "1"
  _contiene "blanco registrado" "$(lab_estado adv_violation_paths)" 'src/out.txt'
  # Redireccion DENTRO del dir: permitida (la cubre el escaneo por mtime).
  lab_run tool claude "$(lab_payload_bash_en_subagente adversary 'echo x >> .saikit/findings/nota.txt')"
  _no_contiene "dentro del dir no es violacion" "$(lab_estado adv_violation_paths)" 'nota.txt'
  # /dev/null y dup de fd: no son escrituras de archivo.
  lab_run tool claude "$(lab_payload_bash_en_subagente adversary 'pytest -q 2>/dev/null > /dev/null')"
  _no_contiene "dev/null no es violacion" "$(lab_estado adv_violation_paths)" 'dev/null'
  # tee fuera: violacion.
  lab_run tool claude "$(lab_payload_bash_en_subagente adversary 'cat data/x | tee src/log.txt')"
  _contiene "tee fuera" "$(lab_estado adv_violation_paths)" 'src/log.txt'
  # Programa awk entre comillas con '>' comparativo: NO falso positivo (los
  # tramos entrecomillados no son redirecciones obvias).
  lab_run tool claude "$(lab_payload_bash_en_subagente adversary "awk '\$2 > 100 {print}' data/x > /dev/null")"
  _no_contiene "awk citado no es falso positivo" "$(lab_estado adv_violation_paths)" '100'
  # cp/mv: fuera del alcance declarado (redireccion/heredoc/tee OBVIOS).
  lab_run tool claude "$(lab_payload_bash_en_subagente adversary 'cp data/x src/copy.txt')"
  _no_contiene "cp es hueco declarado" "$(lab_estado adv_violation_paths)" 'copy.txt'
  # Heredoc con redireccion: cubierto por la rama de redireccion.
  lab_run tool claude "$(lab_payload_bash_en_subagente adversary 'cat > src/heredoc.txt <<EOF')"
  _contiene "heredoc fuera" "$(lab_estado adv_violation_paths)" 'src/heredoc.txt'
}
advlock_bash_best_effort; fin_caso "advlock_bash_best_effort"

caso "advlock_gitignore_idempotente_y_ajeno"
advlock_gitignore_idempotente_y_ajeno() {
  mkdir -p "$LAB/proyecto/.saikit/findings"
  adv_armar
  adv_despachar
  _contiene "gitignore creado" "$(cat "$LAB/proyecto/.saikit/findings/.gitignore" 2>/dev/null)" '*'
  # Un gitignore AJENO presente no se reescribe jamas (limite declarado: si no
  # cubre los artefactos, quedan expuestos — no es asunto del hook).
  printf 'custom-ajeno\n' > "$LAB/proyecto/.saikit/findings/.gitignore"
  lab_run tool claude "$(lab_payload_agent 'adversary')"
  _igual "gitignore ajeno intacto" "$(cat "$LAB/proyecto/.saikit/findings/.gitignore" 2>/dev/null)" 'custom-ajeno'
  # Sin sesion armada el hook no crea NADA en el consumer (A1: alcance por
  # sesion — el gitignore dispara con el primer evento adversary de una sesion
  # armada, no con la mera existencia del repo).
  lab_limpiar_estado
  rm -rf "$LAB/proyecto/.saikit"
  lab_run tool claude "$(lab_payload_agent 'adversary')"
  if [ -e "$LAB/proyecto/.saikit" ]; then
    _mal "sin sesion armada no se crea .saikit en el consumer"
  fi
}
advlock_gitignore_idempotente_y_ajeno; fin_caso "advlock_gitignore_idempotente_y_ajeno"

caso "advlock_falla_infra_fail_open"
advlock_falla_infra_fail_open() {
  # .saikit como ARCHIVO (no dir) bloquea el namespace entero: mkdir falla, el
  # gitignore no se crea, y el hook tiene que seguir sin crash ni inventar
  # violaciones (Core Rule 1: fallo de infraestructura => fail-open).
  printf 'ocupado\n' > "$LAB/proyecto/.saikit"
  adv_armar
  adv_despachar
  _igual "evento procesado sin crash" "$LAB_RC" "0"
  lab_run tool claude "$(adv_payload_edit_interno adversary '.saikit/findings/x.json')"
  _igual "sin violacion inventada" "$(lab_estado adv_violation)" ""
  _contiene "ruta textual permitida registrada" "$(lab_estado adv_paths)" 'x.json'
  # El Stop no se cae por el namespace roto: sin dir no hay rama de mtime
  # (fail-open declarado) y el turno sigue su curso normal de gate.
  lab_run stop claude "$(lab_payload_stop "$_ADV_RECIBO")"
  if [ "$LAB_RC" -eq 2 ]; then
    _no_contiene "bloquea por gate normal, no por adversary" "$LAB_ERR" 'adversary wrote outside'
  else
    _igual "exit code" "$LAB_RC" "0"
  fi
}
advlock_falla_infra_fail_open; fin_caso "advlock_falla_infra_fail_open"

if [ "$fail" -ne 0 ]; then
  echo "test_adversary_lock: FAIL (casos)" >&2
  exit 1
fi

# ------------------------------------------------------- mutation-test propio
# Cada mutacion rompe UNA condicion del candado con un sed de ancla unica (las
# funciones adv_* se escriben con la llave en la MISMA linea del nombre para
# que estos anclajes existan). Guardias: la mutacion cambia el archivo, el
# mutado parsea, y ALGUN caso se pone rojo — si no, esta suite no ata nada.
mut_advlock_gitignore_neutralizado() { sed 's/^adv_ensure_gitignore() {$/adv_ensure_gitignore() {\n  return 0/'; }
mut_advlock_violacion_ciega()        { sed 's/^adv_registrar_violacion() {$/adv_registrar_violacion() {\n  return 0/'; }
mut_advlock_secreto_ciego()          { sed 's/^adv_chequear_secretos() {$/adv_chequear_secretos() {\n  return 0/'; }
mut_advlock_epoca_no_se_inicializa() { sed 's/"\$adv_epoch_armado" "" "" ""$/"ADV-MUT" "" "" ""/'; }
mut_advlock_prefijo_roto()           { sed 's|"\$ADV_FINDINGS_DIR"/\*)|*)|'; }
mut_advlock_bash_ciego()             { sed 's/^adv_guard_bash() {$/adv_guard_bash() {\n  return 0/'; }

MUTS_ADVLOCK="gitignore_neutralizado|advlock_gitignore_idempotente_y_ajeno
violacion_ciega|advlock_bloquea_escritura_fuera
secreto_ciego|advlock_secreto_sesion_actual_bloquea_y_anterior_no
epoca_no_se_inicializa|advlock_armado_inicializa_estado_previo
prefijo_roto|advlock_traversal_y_ruta_absoluta
bash_ciego|advlock_bash_best_effort"

while IFS='|' read -r nombre caso_atrapa; do
  [ -n "$nombre" ] || continue
  mutado="$tmp/hook-$nombre.sh"
  "mut_advlock_$nombre" < "$vivo" > "$mutado"
  if cmp -s "$vivo" "$mutado"; then
    printf '    FAIL: %s no cambio nada — el sed quedo obsoleto\n' "$nombre" >&2
    fail=1
    continue
  fi
  if ! bash -n "$mutado" 2>/dev/null; then
    printf '    FAIL: %s no parsea; asi no prueba nada\n' "$nombre" >&2
    fail=1
    continue
  fi
  lab_hook_swap "$mutado"
  CASO_ROJO=0
  adv_reset
  "$caso_atrapa"
  if [ "$CASO_ROJO" -ne 0 ]; then
    printf '    mutacion %s atrapada por %s\n' "$nombre" "$caso_atrapa"
  else
    printf '    FAIL: ningun caso detecto la mutacion [%s]\n' "$nombre" >&2
    fail=1
  fi
  lab_hook_swap "$vivo"
done <<EOF
$MUTS_ADVLOCK
EOF

if [ "$fail" -ne 0 ]; then
  echo "test_adversary_lock: FAIL" >&2
  exit 1
fi
echo "test_adversary_lock: OK"
