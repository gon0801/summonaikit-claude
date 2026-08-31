#!/usr/bin/env bash
# Lado de la DoD de la Task 17.3 / D12 — el rastro de decisiones.
#
# Afirma, en verde cuando se cumple y rojo cuando no:
#
#   (a) El helper `redactar` (tools/lib/redactar.sh) redacta a [REDACTED] cada
#       forma de token conocida — ghp_, github_pat_, gho_, sk-, AKIA, xoxb-,
#       xoxp- — Y las formas preexistentes del hook (token=, password=,
#       ://user:pass@). Es la propiedad de seguridad central: un token pegado
#       en una explicacion del rastro NUNCA viaja en claro.
#   (b) `tools/saikit-decision.sh --append` crea el archivo con su encabezado y
#       agrega filas COMPLETAS (sin partir una fila).
#   (c) Dos appends CONCURRENTES no parten una fila: el candado mkdir los
#       serializa y el tsv queda con 2 filas intactas.
#   (d) Un tsv malformado (fila de 3 campos, o encabezado equivocado) se
#       REPORTA con exit 2 y NO se repara: el archivo queda byte-identico.
#   (e) Un token pegado en el rastro sale [REDACTED] en la fila escrita.
#   (f) El hook conoce las formas nuevas en su familia de escaneo
#       (SAIKIT_ADV_SECRET_RE) y en su redact_secrets.
#
# Core Rule 4: todo se escribe en un tmpdir, jamas en el arbol del repo.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
lib="$repo/tools/lib/redactar.sh"
tool="$repo/tools/saikit-decision.sh"
hook="$repo/hooks/summonaikit-harness.sh"

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/saikit-decid-XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT

if [ ! -f "$lib" ]; then
  malo "no existe la lib de redaccion: $lib"
  echo "test_saikit_decision: FAIL" >&2
  exit 1
fi

# ------------------------------------------------------------------- (a)
caso "redactar redacta cada forma de token a [REDACTED]"
. "$lib"
# Los tokens se ARMAN en runtime, jamas como literal contiguo en el archivo:
# el job `secrets` del CI corre gitleaks sobre el HISTORIAL COMPLETO, y un fake
# con forma realista queda en la historia para siempre (medido en este PR: el
# job se puso rojo con la version literal). Las colas son FAKE repetido — baja
# entropia a proposito — y conservan el largo que cada patron exige: AKIA pide
# [0-9A-Z]{16} EXACTOS, por eso su cola es de 16.
form_token() {
  local cola36='FAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKE'   # 36 alfanumericos
  local cola16='FAKEFAKEFAKEFAKE'                        # 16 mayusculas
  case "$1" in
    ghp_)        printf 'ghp_%s' "$cola36" ;;
    github_pat_) printf 'github_pat_%s' "$cola36" ;;
    gho_)        printf 'gho_%s' "$cola36" ;;
    sk-)         printf 'sk-proj-%s' "$cola36" ;;
    AKIA)        printf 'AKIA%s' "$cola16" ;;
    xoxb-)       printf 'xox%s' "b-1234567890-$cola16" ;;
    xoxp-)       printf 'xox%s' "p-1234567890-$cola16" ;;
    *)           printf '' ;;
  esac
}
for k in ghp_ github_pat_ gho_ sk- AKIA xoxb- xoxp-; do
  token="$(form_token "$k")"
  [ -n "$token" ] || continue
  out="$(redactar "pre $token post")"
  case "$out" in
    *"$token"*) malo "redactar dejo $k en claro: $out" ;;
  esac
  case "$out" in
    *'[REDACTED]'*) ;;
    *) malo "redactar no marco [REDACTED] para $k: $out" ;;
  esac
done

# Negativo de la frontera: un prefijo de tarea de este repo (letra antes de
# "-sk-") NO es un token y no debe redactarse. Sin la frontera, la regla
# manglea "task-17" a "ta[REDACTED]" y corrompe el log. La frontera es por
# LETRA: un `-` o `_` ANTES de "sk-" (flag=-sk-proj, a_sk) SI es separador.
caso "redactar deja intactos los prefijos embedded que no son token"
out="$(redactar "pytest task-17_3.py subtask-3 disk-image risk-9")"
case "$out" in
  *"[REDACTED]"*) malo "redactar redacto un prefijo que no es token: $out" ;;
esac
case "$out" in
  *"task-17_3.py"*) ;;
  *) malo "redactar mangleo task-17_3.py: $out" ;;
esac

# Positivo del mismo sk-: tras un separador que NO es letra (guion o guion_bajo)
# la frontera SI dispara — distingue "task-17" (letra antes) de "-sk-proj" (guion).
caso "redactar redacta un sk- tras guion o guion_bajo"
out="$(redactar "flag=-sk-proj-abc _sk-custom")"
case "$out" in
  *"-sk-proj-abc"*|*"_sk-custom"*) malo "no redacto el sk- tras guion/guion_bajo: $out" ;;
esac
case "$out" in
  *"[REDACTED]"*) ;;
  *) malo "no marco [REDACTED] para el sk- tras guion: $out" ;;
esac

caso "redactar redacta las formas preexistentes del hook"
out="$(redactar "token=abc123 password=supersecreto ://user:pass@host/db")"
case "$out" in
  *"token=abc123"*)  malo "token= no se redacto: $out" ;;
esac
case "$out" in
  *"password=supersecreto"*) malo "password= no se redacto: $out" ;;
esac
case "$out" in
  *"user:pass@") malo "://user:pass@ no se redacto: $out" ;;
esac
case "$out" in
  *'[REDACTED]'*) ;;
  *) malo "las formas preexistentes no dejaron [REDACTED]: $out" ;;
esac

# ------------------------------------------------------------------- (b)
caso "append crea el encabezado y agrega filas completas"
bash "$tool" --append --task prueba --dir "$tmp" --etapa Diseno \
  --decision "Usar sed en vez de awk" --por-que "ya hay sed en el hook" \
  --evidencia "caso_g2_verde" --resultado ok
[ $? -eq 0 ] || malo "el primer append no salio 0"
bash "$tool" --append --task prueba --dir "$tmp" --etapa Diseno \
  --decision "Segunda decision distinta" --por-que "otro por que" \
  --evidencia "otra evidencia" --resultado ok
[ $? -eq 0 ] || malo "el segundo append no salio 0"

nlineas="$(wc -l < "$tmp/prueba.tsv" 2>/dev/null | tr -d ' ')"
[ "$nlineas" -eq 3 ] || malo "se esperaban 3 lineas (encabezado + 2 filas), hay ${nlineas:-0}"
head -n 1 "$tmp/prueba.tsv" | grep -qx 'cuando|etapa|decision|por_que|evidencia|resultado' \
  || malo "el encabezado no es el contrato"
grep -qF "Usar sed en vez de awk" "$tmp/prueba.tsv" || malo "la primera decision no esta entera"
grep -qF "Segunda decision distinta" "$tmp/prueba.tsv" || malo "la segunda decision no esta entera"
bash "$tool" --check --task prueba --dir "$tmp" || malo "el tsv de prueba no valida"

# ------------------------------------------------------------------- (c)
caso "dos appends concurrentes no parten una fila"
bash "$tool" --append --task conc --dir "$tmp" --etapa X \
  --decision "Primera concurrente" --por-que "p" --evidencia "e" --resultado ok &
p1=$!
bash "$tool" --append --task conc --dir "$tmp" --etapa X \
  --decision "Segunda concurrente" --por-que "p" --evidencia "e" --resultado ok &
p2=$!
wait "$p1"; r1=$?
wait "$p2"; r2=$?
[ "$r1" -eq 0 ] || malo "append concurrente 1 fallo (rc=$r1)"
[ "$r2" -eq 0 ] || malo "append concurrente 2 fallo (rc=$r2)"
nlineas="$(wc -l < "$tmp/conc.tsv" 2>/dev/null | tr -d ' ')"
[ "$nlineas" -eq 3 ] || malo "el tsv concurrente se esperaba de 3 lineas, hay ${nlineas:-0}"
bash "$tool" --check --task conc --dir "$tmp" || malo "el tsv concurrente no valida"
while IFS= read -r linea; do
  case "$linea" in ''|\#*) continue ;; esac
  [ "$linea" = 'cuando|etapa|decision|por_que|evidencia|resultado' ] && continue
  nf="$(printf '%s' "$linea" | awk -F'|' '{print NF}')"
  [ "$nf" -eq 6 ] || malo "fila con $nf campos (fragmento?): $linea"
done < "$tmp/conc.tsv"

# ------------------------------------------------------------------- (d)
caso "un tsv con fila de 3 campos se reporta y NO se repara"
printf 'cuando|etapa|decision|por_que|evidencia|resultado\n' > "$tmp/mal1.tsv"
printf 'a|b|c\n' >> "$tmp/mal1.tsv"
cp "$tmp/mal1.tsv" "$tmp/mal1.bak"
bash "$tool" --append --task mal1 --dir "$tmp" --etapa X --decision D \
  --por-que P --evidencia E --resultado ok >/dev/null 2>"$tmp/mal1.err"
rc=$?
[ "$rc" -eq 2 ] || malo "con fila de 3 campos se esperaba exit 2, dio $rc"
grep -q 'TSV malformado: linea 2' "$tmp/mal1.err" \
  || malo "no nombra la linea malformada: $(cat "$tmp/mal1.err")"
cmp -s "$tmp/mal1.tsv" "$tmp/mal1.bak" || malo "el archivo malformado se modifico (se reparo)"

caso "un tsv con encabezado equivocado se reporta y NO se toca"
printf 'no|es|el|encabezado\n' > "$tmp/mal2.tsv"
printf 'a|b|c|d|e|f\n' >> "$tmp/mal2.tsv"
cp "$tmp/mal2.tsv" "$tmp/mal2.bak"
bash "$tool" --check --task mal2 --dir "$tmp" >/dev/null 2>"$tmp/mal2.err"
rc=$?
[ "$rc" -eq 2 ] || malo "con encabezado malo se esperaba exit 2, dio $rc"
grep -q 'encabezado' "$tmp/mal2.err" || malo "no nombra el encabezado: $(cat "$tmp/mal2.err")"
cmp -s "$tmp/mal2.tsv" "$tmp/mal2.bak" || malo "el tsv con encabezado malo se modifico"

# ------------------------------------------------------------------- (e)
caso "un token pegado en el rastro sale [REDACTED]"
bash "$tool" --append --task rastro --dir "$tmp" --etapa Diseno \
  --decision "usar el token $(form_token ghp_)" \
  --por-que "el por que trae $(form_token ghp_)" \
  --evidencia "la evidencia trae $(form_token ghp_)" \
  --resultado ok
[ $? -eq 0 ] || malo "el append del rastro no salio 0"
# El needle va por VARIABLE con comillas dobles. La version anterior ponia
# $(form_token ghp_) entre comillas SIMPLES: buscaba esa cadena literal, que
# jamas aparece, y el caso pasaba en vacio (cross-review grok+codex, error del
# lead al des-literalizar los fixtures).
tok_e="$(form_token ghp_)"
grep -qF "$tok_e" "$tmp/rastro.tsv" \
  && malo "el token quedo en claro en el rastro"
# Y no basta con que el token completo desaparezca: una redaccion que tapara
# solo el prefijo dejaria casi toda la clave (codex 9). La cola tampoco puede
# quedar.
grep -qF 'FAKEFAKEFAKE' "$tmp/rastro.tsv" \
  && malo "la cola del token quedo en claro en el rastro"
grep -qF '[REDACTED]' "$tmp/rastro.tsv" || malo "el rastro no trae [REDACTED]"

# ------------------------------------------------------------------- (f)
caso "la familia de escaneo y las reglas de redaccion son identicas en lib y hook"
if [ -f "$hook" ]; then
  # Esta es la afirmacion central de la tarea (D12): la fuente unica
  # (tools/lib/redactar.sh) y la copia INLINE del hook tienen que usar la MISMA
  # familia, o un secreto pasaria por la rendija entre las dos superficies. No
  # alcanza con que el hook "contenga" los literales — hay que comparar las dos.
  lib_re="$SAIKIT_SECRET_SCAN_RE"
  hook_re="$(grep -m1 '^SAIKIT_ADV_SECRET_RE=' "$hook" | sed -e 's/^SAIKIT_ADV_SECRET_RE=.//' -e 's/.$//')"
  [ -n "$lib_re" ] || malo "la lib no expone SAIKIT_SECRET_SCAN_RE"
  [ -n "$hook_re" ] || malo "el hook no declara SAIKIT_ADV_SECRET_RE"
  [ "$lib_re" = "$hook_re" ] || malo "la familia de escaneo no es identica (lib <-> hook)"
  # Cada forma: el RE de escaneo la conoce en el hook, y la regla sed aparece
  # en las DOS superficies (hook y lib). El patron de sk- en la regla sed es el
  # anclado a frontera de palabra (^|[^A-Za-z0-9_-])sk-, que es lo que evita
  # manglear un prefijo de tarea — se verifica su presencia en ambas.
  for p in 'ghp_[A-Za-z0-9]' 'github_pat_[A-Za-z0-9]' 'gho_[A-Za-z0-9]' \
           'sk-[A-Za-z0-9]' 'AKIA[0-9A-Z]' 'xox[bp]-[A-Za-z0-9]'; do
    grep -qF "$p" "$hook" || malo "el RE de escaneo del hook no conoce $p"
  done
  for p in 's/ghp_' 's/github_pat_' 's/gho_' '(^|[^A-Za-z0-9])sk-' 's/AKIA' 's/xox[bp]-'; do
    grep -qF "$p" "$hook" || malo "redact_secrets del hook no contiene $p"
    grep -qF "$p" "$lib" || malo "redactar de la lib no contiene $p"
  done
else
  malo "no existe el hook: $hook"
fi

# ------------------------------------------------------------------- (g)
caso "un candado huerfano (pid muerto) se limpia y el append vuelve a funcionar"
# Simula un proceso que murio dejando el dir de candado con su pid adentro (el
# caso que el adversary encontro: un rmdir pelado sobre el dir NO vacio fallaba
# y cada corrida siguiente salia exit 3 para siempre). El fix saca el pid antes
# de rmdir. Sin el fix, este append falla.
mkdir -p "$tmp/.saikit-decision-stale.lock" || malo "no se pudo crear el candado huerfano"
printf '999999\n' > "$tmp/.saikit-decision-stale.lock/pid"   # pid que no existe (muerto)
bash "$tool" --append --task stale --dir "$tmp" --etapa X --decision D --por-que P --evidencia E --resultado ok
[ $? -eq 0 ] || malo "un candado huerfano no se limpio y el append fallo"
grep -qF '|D|' "$tmp/stale.tsv" || malo "la fila no se escribio tras limpiar el candado"
[ -d "$tmp/.saikit-decision-stale.lock" ] && malo "el candado huerfano quedo clavado (no se limpiaron pid y dir)"

caso "un --resultado vacio se rechaza (fila incompleta, no se escribe)"
bash "$tool" --append --task vacio --dir "$tmp" --etapa X --decision D --por-que P --evidencia E --resultado "" >/dev/null 2>"$tmp/vacio.err"
[ $? -eq 2 ] || malo "con --resultado vacio se esperaba exit 2"
[ -f "$tmp/vacio.tsv" ] && malo "no se debio crear la fila con resultado vacio"
grep -q 'resultado no puede quedar vacio' "$tmp/vacio.err" || malo "no se explico el resultado vacio: $(cat "$tmp/vacio.err")"

caso "un campo con salto de linea se rechaza (no divide la fila)"
# La guardia de campo vetaba el `|` pero NO un \n o \r: un valor con salto
# partia la fila en dos lineas fisicas (violaba "sin partir una fila"). Sin la
# guardia nueva, este append escribe una fila rota y el propio --check la
# rechaza despues.
bash "$tool" --append --task nl --dir "$tmp" --etapa X --decision $'a\nb' --por-que P --evidencia E --resultado ok >/dev/null 2>"$tmp/nl.err"
[ $? -eq 2 ] || malo "con salto de linea en --decision se esperaba exit 2"
[ -f "$tmp/nl.tsv" ] && malo "no se debio crear la fila con salto de linea"
grep -q 'salto de linea' "$tmp/nl.err" || malo "no se explico el salto de linea: $(cat "$tmp/nl.err")"

caso "un candado sin pid pero viejo (huerfano) se reclama y el append funciona"
# El caso del huerfano SIN pid: un writer muerto entre el mkdir y la escritura
# del pid deja el dir vacio, que la logica anterior (y el trap, que no corre en
# SIGKILL) nunca reclamaba. El fix lo distingue por la EDAD del dir: uno viejo
# (>2s) y sin pid es un huerfano. Se fuerza el mtime hacia atras con touch.
mkdir -p "$tmp/.saikit-decision-vieja.lock" || malo "no se pudo crear el candado sin pid"
touch -d "2020-01-01 00:00:00" "$tmp/.saikit-decision-vieja.lock" 2>/dev/null || touch -t 202001010000 "$tmp/.saikit-decision-vieja.lock"
bash "$tool" --append --task vieja --dir "$tmp" --etapa X --decision D --por-que P --evidencia E --resultado ok
[ $? -eq 0 ] || malo "un candado sin pid pero viejo no se reclamo y el append fallo"
[ -d "$tmp/.saikit-decision-vieja.lock" ] && malo "el candado huerfano viejo quedo clavado"
grep -qF '|D|' "$tmp/vieja.tsv" || malo "la fila no se escribio tras reclamar el huerfano"

caso "una escritura que falla se reporta y NO se da por registrada"
# El tool tenia el `printf >>` sin verificar: ante un fallo de I/O (disco lleno,
# permisos, ruta que es un directorio) seguia y reportaba "registrado" con exit 0
# para una fila que nunca llego al disco. Se fuerza el fallo haciendo que el
# "archivo" sea un directorio: la escritura del encabezado falla y debe salir 2.
mkdir -p "$tmp/dirdir.tsv" || malo "no se pudo crear el directorio-trampa"
bash "$tool" --append --task dirdir --dir "$tmp" --etapa X --decision D --por-que P --evidencia E --resultado ok >/dev/null 2>"$tmp/dirdir.err"
[ $? -eq 2 ] || malo "escribir a un directorio se esperaba exit 2, no un 'registrado' mentiroso"
grep -q 'no se pudo' "$tmp/dirdir.err" || malo "no se explico el fallo de escritura: $(cat "$tmp/dirdir.err")"

# ------------------------------------------------- hallazgos cross-review 17.3
caso "todos los campos se redactan, no solo los de texto libre (codex 2)"
bash "$tool" --append --task todos --dir "$tmp" \
  --etapa "etapa con $(form_token gho_)" \
  --decision d --por-que p --evidencia e \
  --resultado "ok pero $(form_token AKIA)" \
  --cuando "2026-08-31T00:00:00Z" >/dev/null 2>&1 \
  || malo "append con secretos en etapa/resultado no salio 0"
[ -s "$tmp/todos.tsv" ] || malo "todos.tsv no existe: los greps de abajo no medirian nada (kimi 10)"
tok_g="$(form_token gho_)"; tok_a="$(form_token AKIA)"
grep -qF "$tok_g" "$tmp/todos.tsv" && malo "gho_ quedo en claro en la ETAPA"
grep -qF "$tok_a" "$tmp/todos.tsv" && malo "AKIA quedo en claro en el RESULTADO"
# kimi 12: no basta con que el token desaparezca — el marcador tiene que
# APARECER donde se redacto, si no una "redaccion" que borre el campo pasa.
n_red="$(grep -oF '[REDACTED]' "$tmp/todos.tsv" | wc -l | tr -d ' ')"
[ "$n_red" -ge 2 ] || malo "esperaba [REDACTED] en etapa Y resultado, hay $n_red"

caso "un campo con '|' se rechaza sin escribir (inyecta columnas)"
antes="$(wc -l < "$tmp/todos.tsv")"
bash "$tool" --append --task todos --dir "$tmp" --etapa "a|b" \
  --decision d --por-que p --evidencia e --resultado ok >/dev/null 2>&1
[ $? -eq 2 ] || malo "campo con | debio salir 2"
[ "$(wc -l < "$tmp/todos.tsv")" = "$antes" ] || malo "campo con | escribio igual"

caso "un campo con salto de linea se rechaza sin escribir"
bash "$tool" --append --task todos --dir "$tmp" --etapa "a
b" --decision d --por-que p --evidencia e --resultado ok >/dev/null 2>&1
[ $? -eq 2 ] || malo "campo con NL debio salir 2"
[ "$(wc -l < "$tmp/todos.tsv")" = "$antes" ] || malo "campo con NL escribio igual"

caso "--task con '/' o '..' se rechaza: es nombre de archivo, no ruta (lead)"
bash "$tool" --append --task "../fuera" --dir "$tmp" --etapa E \
  --decision d --por-que p --evidencia e --resultado ok >/dev/null 2>&1
[ $? -eq 2 ] || malo "--task ../fuera debio salir 2"
[ ! -e "$tmp/../fuera.tsv" ] || malo "--task ../fuera ESCRIBIO fuera del dir"

caso "--task con backslash se rechaza (kimi 4: la mitad Windows del veto no tenia caso)"
bash "$tool" --append --task "..\\fuera" --dir "$tmp" --etapa E \
  --decision d --por-que p --evidencia e --resultado ok >/dev/null 2>&1
[ $? -eq 2 ] || malo "--task con backslash debio salir 2"

caso "--task con forma de secreto se rechaza: el nombre se commitea (qwen 1)"
bash "$tool" --append --task "ghp_abc123" --dir "$tmp" --etapa E \
  --decision d --por-que p --evidencia e --resultado ok >/dev/null 2>&1
[ $? -eq 2 ] || malo "--task ghp_abc123 debio salir 2"
[ ! -e "$tmp/ghp_abc123.tsv" ] || malo "el secreto quedo como NOMBRE de archivo"

caso "--task vacio se rechaza (qwen 11)"
bash "$tool" --append --task "" --dir "$tmp" --etapa E \
  --decision d --por-que p --evidencia e --resultado ok >/dev/null 2>&1
[ $? -eq 2 ] || malo "--task vacio debio salir 2"

caso "un flag conocido como VALOR de otro flag se rechaza (kimi 11)"
bash "$tool" --append --task tipeo --dir "$tmp" --etapa --decision \
  --por-que p --evidencia e --resultado ok >/dev/null 2>&1
[ $? -eq 2 ] || malo "--etapa --decision debio salir 2, no tragar el flag como valor"

# La dependencia de `timeout` se DECLARA (qwen 13): existe en el CI Linux y en
# MSYS2/coreutils; en un macOS pelado daria rc=127 — un rojo RUIDOSO, no un
# pase en vacio, que es el lado seguro del que fallar.
caso "flag sin valor => exit 2 rapido, no un bucle infinito (codex 13, bug de la 0.4)"
out="$(timeout 5 bash "$tool" --append --dir "$tmp" --task 2>&1)"; rc=$?
[ "$rc" -ne 124 ] || malo "flag sin valor COLGO el parser (timeout): el bug de la Task 0.4"
[ "$rc" -eq 2 ] || malo "flag sin valor debio salir 2, dio $rc: $out"

caso "una fila con retorno de carro se reporta malformada (codex 7)"
cp "$tmp/todos.tsv" "$tmp/concr.tsv"
printf '2026-08-31T00:00:01Z|E|d|p|e|ok\r\n' >> "$tmp/concr.tsv"
bash "$tool" --check --task concr --dir "$tmp" >/dev/null 2>&1
[ $? -eq 2 ] || malo "una fila con CR debio reportarse malformada"

caso "una fila de 7 columnas se reporta malformada (codex 14)"
cp "$tmp/todos.tsv" "$tmp/siete.tsv"
printf '2026-08-31T00:00:01Z|E|d|p|e|ok|extra\n' >> "$tmp/siete.tsv"
bash "$tool" --check --task siete --dir "$tmp" >/dev/null 2>&1
[ $? -eq 2 ] || malo "una fila de 7 columnas debio reportarse malformada"

caso "una linea '#comentario' inyectada ya no se oculta (grok 8 / codex 6)"
cp "$tmp/todos.tsv" "$tmp/coment.tsv"
printf '#fila oculta que el check ignoraba\n' >> "$tmp/coment.tsv"
bash "$tool" --check --task coment --dir "$tmp" >/dev/null 2>&1
[ $? -eq 2 ] || malo "una linea # inyectada debio reportarse, no ignorarse"

if [ "$fail" -ne 0 ]; then
  echo "test_saikit_decision: FAIL" >&2
  exit 1
fi
echo "test_saikit_decision: OK"
