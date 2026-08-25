#!/usr/bin/env bash
# Task 12.4 — el router rol → tier → (modelo, effort) por host.
# Corre contra un sandbox propio: nunca toca el repo ni el perfil vivo.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/sandbox.sh"
sandbox_init

repo="$(cd "$here/.." && pwd)"
router="$repo/tools/model-routing.sh"

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

igual() {  # $1=esperado $2=obtenido $3=etiqueta
  [ "$1" = "$2" ] || malo "$3: esperaba [$1], obtuve [$2]"
}

caso "la tabla del host claude, valor por valor"
igual "claude-sonnet-5" "$(bash "$router" --host claude --role implementer --field model)" "implementer/model"
igual "medium"          "$(bash "$router" --host claude --role implementer --field effort)" "implementer/effort"
igual "claude-sonnet-5" "$(bash "$router" --host claude --role verifier --field model)"    "verifier/model"
igual "low"             "$(bash "$router" --host claude --role verifier --field effort)"   "verifier/effort"
igual "claude-opus-5"   "$(bash "$router" --host claude --role reviewer --field model)"    "reviewer/model"
igual "xhigh"           "$(bash "$router" --host claude --role reviewer --field effort)"   "reviewer/effort"
# Task 13.7: adversary rutea al tier review (D5 del diseno 13) -- mismos
# valores que reviewer, sin tier propio.
igual "claude-opus-5"   "$(bash "$router" --host claude --role adversary --field model)"   "adversary/model"
igual "xhigh"           "$(bash "$router" --host claude --role adversary --field effort)"  "adversary/effort"

caso "rol -> tier"
igual "standard" "$(bash "$router" --host claude --role implementer --field tier)" "implementer"
igual "verify"   "$(bash "$router" --host claude --role verifier --field tier)"    "verifier"
igual "review"   "$(bash "$router" --host claude --role reviewer --field tier)"    "reviewer"
igual "review"   "$(bash "$router" --host claude --role adversary --field tier)"   "adversary"

caso "la tabla del host grok, valor por valor (Task 12.2)"
igual "grok-4.6" "$(bash "$router" --host grok --role implementer --field model)" "implementer/model"
igual "medium"   "$(bash "$router" --host grok --role implementer --field effort)" "implementer/effort"
igual "grok-4.6" "$(bash "$router" --host grok --role verifier --field model)"    "verifier/model"
igual "low"      "$(bash "$router" --host grok --role verifier --field effort)"   "verifier/effort"
igual "grok-4.6" "$(bash "$router" --host grok --role reviewer --field model)"    "reviewer/model"
igual "xhigh"    "$(bash "$router" --host grok --role reviewer --field effort)"   "reviewer/effort"
# Task 13.7: adversary hereda la fila review de grok (grok-4.6/xhigh, 12.2).
igual "grok-4.6" "$(bash "$router" --host grok --role adversary --field model)"   "adversary/model"
igual "xhigh"    "$(bash "$router" --host grok --role adversary --field effort)"  "adversary/effort"

caso "una fila de host sin valor devuelve VACIO con exit 0, no un default"
# zcode: vacia A PROPOSITO -- la 12.1 midio que el catalogo real de la cuenta
# quedo NO OBSERVADO, asi que no hay valor confirmado que poner (Core Rule del
# diseno: sin medicion que cierre, la fila queda vacia y hereda del padre).
# kimi: vacia DEFINITIVA -- la 12.3 midio que el host no acepta model ni effort
# por agente, asi que esa fila no se llena nunca y este caso queda permanente.
for h in zcode kimi; do
  # Task 13.7: adversary tambien hereda la fila vacia de zcode y kimi (12.1/12.3).
  for rol in implementer adversary; do
    out="$(bash "$router" --host "$h" --role "$rol" --field model)"; rc=$?
    [ "$rc" -eq 0 ] || malo "$h/$rol: esperaba exit 0, obtuve $rc"
    [ -z "$out" ]   || malo "$h/$rol: esperaba stdout vacio, obtuve [$out]"
  done
done

caso "--format frontmatter"
igual "model: claude-opus-5
effort: xhigh" "$(bash "$router" --host claude --role reviewer --format frontmatter)" "claude/reviewer"
igual "model: grok-4.6
effort: xhigh" "$(bash "$router" --host grok --role reviewer --format frontmatter)" "grok/reviewer"
igual "" "$(bash "$router" --host zcode --role reviewer --format frontmatter)" "zcode sin medir"
# Task 13.7: adversary en frontmatter -- claude con model+effort del tier
# review, zcode vacio (fila sin medir).
igual "model: claude-opus-5
effort: xhigh" "$(bash "$router" --host claude --role adversary --format frontmatter)" "claude/adversary"
# El vacio de zcode tiene que venir con exit 0 (fila sin medir), no con un
# exit 2 por rol desconocido: sin el chequeo de rc el caso no discrimina.
out="$(bash "$router" --host zcode --role adversary --format frontmatter)"; rc=$?
[ "$rc" -eq 0 ] || malo "zcode/adversary frontmatter: esperaba exit 0, obtuve $rc"
igual "" "$out" "zcode/adversary sin medir"

caso "--field effort-key: el nombre de CLAVE del effort es por host, no siempre 'effort'"
# Medido en la Task 12.1 (docs/task-12.1-medicion.md): el parser de zcode
# NUNCA lee effort:, solo thoughtLevel:. Este campo tiene que estar disponible
# aunque la fila de zcode este vacia hoy (EFFORT=''), porque el DIA que se
# llene, agente_traducido() necesita saber que clave usar sin tocar el
# instalador -- si esto solo se supiera con la fila llena, el candado no
# podria correr hoy.
igual "effort"      "$(bash "$router" --host claude --role reviewer --field effort-key)" "claude"
igual "effort"      "$(bash "$router" --host grok --role reviewer --field effort-key)"   "grok"
igual "thoughtLevel" "$(bash "$router" --host zcode --role reviewer --field effort-key)"  "zcode"
# Task 13.7: adversary comparte el nombre de clave del tier review por host.
igual "effort"       "$(bash "$router" --host claude --role adversary --field effort-key)" "claude/adversary"
igual "thoughtLevel" "$(bash "$router" --host zcode --role adversary --field effort-key)"  "zcode/adversary"

caso "--format json"
esperado='{"host":"claude","role":"reviewer","tier":"review","model":"claude-opus-5","effort":"xhigh"}'
igual "$esperado" "$(bash "$router" --host claude --role reviewer --format json)" "json"
# Task 13.7: adversary acredita su rol real y el tier review en el json.
esperado='{"host":"claude","role":"adversary","tier":"review","model":"claude-opus-5","effort":"xhigh"}'
igual "$esperado" "$(bash "$router" --host claude --role adversary --format json)" "json/adversary"

caso "desconocido => exit 2, y NO imprime nada por stdout"
for args in "--host marte --role implementer" \
            "--host claude --role astronauta" \
            "--host claude --tier turbo"; do
  # shellcheck disable=SC2086
  out="$(bash "$router" $args 2>/dev/null)"; rc=$?
  [ "$rc" -eq 2 ] || malo "[$args]: esperaba exit 2, obtuve $rc"
  [ -z "$out" ]   || malo "[$args]: exit 2 no debe imprimir por stdout, obtuve [$out]"
done

caso "--role invalido NO se cuela por venir junto a un --tier valido"
out="$(bash "$router" --host claude --role astronauta --tier review 2>/dev/null)"; rc=$?
[ "$rc" -eq 2 ] || malo "un rol invalido debe salir 2 aunque el tier sea valido (obtuve $rc)"
printf '%s' "$out" | grep -q 'astronauta' && malo "no debe acreditar un rol inventado en la salida"

caso "una bandera sin valor NO cuelga el proceso (bucle infinito de shift 2)"
# Reproducido: `shift 2` con el valor ausente no shiftea y devuelve != 0; bajo
# `set -u` sin `-e` el while re-procesa la misma bandera para siempre.
for flag in --host --role --tier --field --format; do
  out="$(timeout 10 bash "$router" "$flag" 2>/dev/null)"; rc=$?
  [ "$rc" -eq 124 ] && malo "[$flag] sin valor colgo el proceso (bucle infinito)"
  [ "$rc" -eq 2 ]   || malo "[$flag] sin valor deberia salir 2, obtuve $rc"
done

caso "el rol desconocido NO se pierde adentro de una sustitucion (trampa de set -u)"
# Bajo `set -u` sin `-e`, X="$(f)" con `exit 2` adentro deja X vacio y sigue.
# El router tiene que salir 2 de verdad, no imprimir vacio y salir 0.
bash "$router" --host claude --role astronauta >/dev/null 2>&1
[ "$?" -eq 2 ] || malo "un rol desconocido tiene que salir 2 desde el proceso, no desde un subshell"

caso "candado: ningun ID de modelo vive fuera del router"
# Cubre tests/ ademas de tools/ y agents/: la primera version solo miraba esos
# dos y por ahi se colaba un `model: claude-opus-5` hardcodeado en
# test_install_hook.sh -- que es exactamente lo que la regla existe para evitar,
# porque obliga a editar dos archivos cada vez que cambia la tabla.
# hooks/ y docs/ quedan FUERA del escaneo por decision del diseno aprobado
# (docs/phase-12-model-routing-design.md): el candado audita configuracion
# ejecutable de ruteo (tools/, agents/, tests/), no documentacion narrativa ni
# el hook -- que esta fase declara explicitamente intocado.
# Se excluye ESTE archivo (es el que declara la tabla), los fixtures del vendor
# (son copias byte a byte de lo que el CLI del kit escribio: evidencia, no
# configuracion; editarlas invalidaria el manifiesto), y los payloads
# sinteticos de PostToolUse/hook_lab con un `resolvedModel` de ejemplo,
# preexistentes a esta fase y sin relacion con la tabla de ruteo -- tambien
# evidencia, no configuracion. La exclusion de escenarios se acota al naming
# real de esos fixtures (NN.tool.<host>.json / NN.stop.<host>.transcript.jsonl,
# verificado contra los 38 archivos que la motivan), no al directorio entero,
# para que un README o script futuro ahi SI quede cubierto por el candado.
otros="$(grep -rlE 'claude-(sonnet|opus|haiku|fable)-[0-9]|glm-[0-9]|grok-[0-9]|kimi-code/' \
           "$repo/tools" "$repo/agents" "$repo/tests" 2>/dev/null \
         | grep -vE 'model-routing\.sh|test_model_routing\.sh|tests/fixtures/vendor-agents/|tests/fixtures/escenarios/.*\.(tool\.[a-z]+\.json|stop\.[a-z]+\.transcript\.jsonl)$|tests/lib/hook_lab\.sh')"
[ -z "$otros" ] || malo "IDs de modelo fuera del router: $otros"

if [ "$fail" -ne 0 ]; then
  echo "test_model_routing: FAIL" >&2
  exit 1
fi
echo "test_model_routing: OK"
