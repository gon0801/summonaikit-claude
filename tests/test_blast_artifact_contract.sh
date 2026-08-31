#!/usr/bin/env bash
# DoD de la Task 17.4 / D13 (blast radius, "el hecho único") y del lado 17.2
# (la app-real lane del verifier). El blast es un artefacto JSON
# `.saikit/findings/blast-<task>.json`; su CONTRATO vive en el PERFIL
# (agents/verifier.md), lo escribe un tool (`tools/saikit-blast.sh`) y lo
# ADJUDICA el reviewer (agents/reviewer.md). Este test ata que nada de eso se
# caiga en silencio:
#
#   (a) el verifier documenta la app-real lane (verify/) y la frase sentinela
#       "inconcluso o superficie equivocada no es PASS";
#   (b) el verifier documenta el blast: el hecho único, el schema exacto
#       hecho/comando/salida/nivel, salida recortada y redactada, la nota de
#       que el candado del adversary NO aplica al verifier (anotado, no
#       re-diagnosticado), y la semantica de nivel 1..5;
#   (c) el reviewer ADJUDICA el blast: juzga el hecho y no lo re-corre, y
#       declara blast malformado (nivel fuera de 1-5, o nivel >= 4 sin
#       comando, o campos equivocados);
#   (d) tools/saikit-blast.sh escribe el artefacto con el schema exacto y
#       valida: nivel >= 4 sin comando, nivel fuera de rango, task invalido;
#   (e) el escaneo de secretos de la sesion (13.4) NO dispara sobre un blast
#       redactado, y SÍ dispara sobre uno CRUDO — la redaccion es lo que
#       desactiva el candado (que no aplica al verifier).
#
# Core Rule 4: todo se escribe en el sandbox, jamas en el arbol del repo.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
tool="$repo/tools/saikit-blast.sh"
verifier="$repo/agents/verifier.md"
reviewer="$repo/agents/reviewer.md"
hook="$repo/hooks/summonaikit-harness.sh"

. "$here/lib/sandbox.sh"
sandbox_init

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

# Los tokens se ARMAN en runtime, jamas como literal contiguo en el archivo:
# el job `secrets` del CI corre gitleaks sobre el HISTORIAL COMPLETO, y un fake
# con forma realista queda en la historia para siempre. Las colas son FAKE
# repetido — baja entropia a proposito — y conservan el largo que cada patron
# exige: AKIA pide [0-9A-Z]{16} EXACTOS, por eso su cola es de 16.
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

# ------------------------------------------------ (a) 17.2 — app-real lane
caso "17.2: el verifier corre verify/ como evidencia cuando el repo lo tiene"
grep -Fq 'verify/' "$verifier" || malo "17.2: el perfil no nombra la app-lane verify/"
grep -Fq 'evidencia' "$verifier" || malo "17.2: el perfil no trata la salida del Drive como evidencia"
grep -Fq 'saikit-verificar-app' "$verifier" || malo "17.2: el perfil no nombra saikit-verificar-app"

caso "17.2: sin verify/, el verifier lo PROPONE y no lo inventa"
grep -Fq 'lo propone' "$verifier" || malo "17.2: el perfil no dice que lo propone"
grep -Fq 'no lo inventa' "$verifier" || malo "17.2: el perfil no dice que no lo inventa"

caso "17.2: la frase sentinela 'inconcluso o superficie equivocada no es PASS'"
grep -Fq 'inconcluso o superficie equivocada no es PASS' "$verifier" || malo "17.2: falta la frase sentinela"

# ------------------------------------------------ (b) 17.4 — blast en el verifier
caso "17.4: el verifier documenta el hecho unico y el comando del tool"
grep -Fq 'hecho único' "$verifier" || malo "17.4: el perfil no documenta el hecho unico"
grep -Fq 'bash tools/saikit-blast.sh --write' "$verifier" || malo "17.4: el perfil no ensena el comando del tool"

caso "17.4: el verifier documenta el esquema exacto del blast"
for k in '"hecho"' '"comando"' '"salida"' '"nivel"'; do
  grep -Fq "$k" "$verifier" || malo "17.4: el perfil no documenta la clave $k"
done

caso "17.4: el verifier documenta salida recortada y redactada + adversario no aplica"
grep -Fq 'recortada' "$verifier" || malo "17.4: el perfil no dice que salida se recorta"
grep -Fq 'redactada' "$verifier" || malo "17.4: el perfil no dice que salida se redacta"
grep -Fq 'no aplica al verifier' "$verifier" || malo "17.4: el perfil no anota que el candado del adversary no aplica al verifier"
grep -Fq 'tools/lib/redactar.sh' "$verifier" || malo "17.4: el perfil no nombra la fuente unica de redaccion"

caso "17.4: el verifier documenta la semantica de nivel (1 .. 5)"
grep -Fq 'afirmado' "$verifier" || malo "17.4: el perfil no documenta el nivel 1 (afirmado)"
grep -Fq 'superficie real' "$verifier" || malo "17.4: el perfil no documenta el nivel 5 (superficie real)"

# ------------------------------------------------ (c) reviewer adjudica el blast
caso "el reviewer adjudica el blast: juzga el hecho, no lo re-corre"
grep -Eiq 'juzga el hecho|no (lo |)repite|no re-corre' "$reviewer" || malo "el reviewer no juzga el hecho sin re-correrlo"
grep -Fq 'blast malformado' "$reviewer" || malo "el reviewer no declara blast malformado"
grep -Fq 'nivel ≥ 4' "$reviewer" || malo "el reviewer no documenta la regla nivel ≥ 4 sin comando"
grep -Fq 'comando' "$reviewer" || malo "el reviewer no nombra el comando como campo del blast"

# ------------------------------------------------ (d) tool: escribe y valida
caso "blast valido pasa: escribe el artefacto con el schema exacto"
bash "$tool" --write --dir "$SANDBOX" --task demo \
  --hecho "el cambio mantiene los registros" \
  --comando "npm test -- verify/drive.test.cjs" \
  --salida "ok" --nivel 4
[ $? -eq 0 ] || malo "el blast valido no salio 0"
file="$SANDBOX/blast-demo.json"
[ -f "$file" ] || malo "no se creo $file"
grep -Fq '"hecho":"el cambio mantiene los registros"' "$file" || malo "la clave hecho no esta o con otro valor"
grep -Fq '"comando":"npm test -- verify/drive.test.cjs"' "$file" || malo "la clave comando no esta o con otro valor"
grep -Fq '"salida":"ok"' "$file" || malo "la clave salida no esta o con otro valor"
grep -Fq '"nivel":4' "$file" || malo "la clave nivel no es 4"
grep -Fq '"role"' "$file" && malo "el blast lleva un campo ajeno (role)"
grep -Fq '"timestamp"' "$file" && malo "el blast lleva un campo ajeno (timestamp)"

# Snapshot del artefacto ya escrito: un write INVALIDO no debe tocarlo.
prev_demo="$(cat "$file")"

caso "nivel >= 4 sin comando => invalido (exit 2, no toca el artefacto)"
bash "$tool" --write --dir "$SANDBOX" --task demo \
  --hecho "hecho" --salida "ok" --nivel 4 >/dev/null 2>"$SANDBOX/niv.err"
[ $? -eq 2 ] || malo "nivel>=4 sin comando debio salir 2"
[ "$(cat "$file")" = "$prev_demo" ] || malo "el artefacto se modifico tras un write invalido"
grep -q 'comando' "$SANDBOX/niv.err" || malo "no se explico la falta de comando: $(cat "$SANDBOX/niv.err")"

caso "nivel >= 4 con comando de solo espacios => invalido (cross-review codex+glm)"
# Un `--comando "   "` es tan vacio como "": pasa el `-z` como no vacio y
# dejaria pasar un "corrido" sin comando util. El trim lo rechaza.
bash "$tool" --write --dir "$SANDBOX" --task demo --hecho "hecho" \
  --comando "   " --salida "ok" --nivel 4 >/dev/null 2>"$SANDBOX/ws.err"
[ $? -eq 2 ] || malo "nivel>=4 con comando de espacios debio salir 2"
[ "$(cat "$file")" = "$prev_demo" ] || malo "el artefacto se modifico con comando de espacios"
grep -q 'comando' "$SANDBOX/ws.err" || malo "no se explico el comando de espacios: $(cat "$SANDBOX/ws.err")"

caso "nivel fuera de 1-5 => invalido (exit 2, no crea el archivo)"
for n in 6 0; do
  bash "$tool" --write --dir "$SANDBOX" --task "demo$n" \
    --hecho "hecho" --comando "cmd" --salida "s" --nivel "$n" >/dev/null 2>&1
  [ $? -eq 2 ] || malo "nivel $n debio salir 2"
  [ -e "$SANDBOX/blast-demo$n.json" ] && malo "nivel $n NO debio crear el artefacto"
done

caso "--task con ruta se rechaza (nombre de archivo, no ruta)"
bash "$tool" --write --dir "$SANDBOX" --task "../fuera" \
  --hecho "h" --comando "c" --salida "s" --nivel 4 >/dev/null 2>&1
[ $? -eq 2 ] || malo "--task ../fuera debio salir 2"

# ------------------------------------------------ regresiones del adversary
# Hallazgos del adversary (2026-08-31) sobre la herramienta: se cierran con los
# casos de abajo, cada uno atado a UNA de las fallas medidas. Los fakes se
# arman en runtime (Core Rule 4 + job `secrets` sobre el historial).
cabeza_big() { printf '%*s' 990 '' | tr ' ' 'A'; }   # 990 'A' para empujar el corte

caso "adversary HIGH: una credencial user:pass con el corte encima queda sin el secreto"
u="FAKEUSER"; p="FAKEPASS"
sal_cred="$(cabeza_big)https://${u}:${p}@example.invalid/path"
bash "$tool" --write --dir "$SANDBOX" --task cred --hecho h \
  --comando "cmd" --salida "$sal_cred" --nivel 4 >/dev/null 2>&1
[ $? -eq 0 ] || malo "el blast con credencial grande no salio 0"
cf="$SANDBOX/blast-cred.json"
grep -Fq "$u" "$cf" && malo "el usuario quedo en claro tras el recorte"
grep -Fq "$p" "$cf" && malo "la clave quedo en claro tras el recorte"

caso "adversary HIGH: un AKIA en el corte no deja fragmento que dispare el escaneo"
ak="$(form_token AKIA)"
sal_ak="$(cabeza_big)${ak}"
bash "$tool" --write --dir "$SANDBOX" --task akia --hecho h \
  --comando "cmd" --salida "$sal_ak" --nivel 4 >/dev/null 2>&1
[ $? -eq 0 ] || malo "el blast con AKIA grande no salio 0"
akf="$SANDBOX/blast-akia.json"
grep -Fq 'AKIA' "$akf" && malo "quedo un fragmento AKIA en el artefacto"

caso "adversary MEDIO: un token partido por un salto no deja la continuacion en claro"
tok_nl="$(form_token ghp_)"
sal_nl="token=${tok_nl}"$'\n'"continuacion"
bash "$tool" --write --dir "$SANDBOX" --task nl --hecho h \
  --comando "cmd" --salida "$sal_nl" --nivel 4 >/dev/null 2>&1
[ $? -eq 0 ] || malo "el blast con salto no salio 0"
nlf="$SANDBOX/blast-nl.json"
grep -Fq "$tok_nl" "$nlf" && malo "el token partido por un salto quedo en claro"
grep -Fq '[REDACTED]' "$nlf" || malo "el token partido por un salto no quedo redactado"

caso "adversary MEDIO: una salida con tab produce JSON valido (sin tab crudo)"
sal_tab="resultado:"$'\t'"ok"
bash "$tool" --write --dir "$SANDBOX" --task tab --hecho h \
  --comando "cmd" --salida "$sal_tab" --nivel 4 >/dev/null 2>&1
[ $? -eq 0 ] || malo "el blast con tab no salio 0"
tbf="$SANDBOX/blast-tab.json"
if grep -q "$(printf '\t')" "$tbf"; then malo "el artefacto con tab quedo con un tab crudo (JSON invalido)"; fi

caso "adversary LOW: --nivel 04 / 05 con cero inicial se rechaza (JSON invalido)"
for nn in 04 05; do
  bash "$tool" --write --dir "$SANDBOX" --task "z$nn" --hecho h \
    --comando "cmd" --salida s --nivel "$nn" >/dev/null 2>&1
  [ $? -eq 2 ] || malo "--nivel $nn debio salir 2 (cero inicial)"
done

caso "re-redaccion: un marcador partido por el corte vuelve a [REDACTED] y no dispara el escaneo"
# El corte de RECORTE pudo partir `token=[REDACTED]` en `token=[REDACT`; sin la
# re-redaccion, el strip no descuenta esa forma parcial y el `=[^[:space:]]` del
# escaneo volveria a disparar (GATE falso). La re-redaccion restaura el marcador
# completo y el escaneo queda descontado.
tok_cut="$(form_token ghp_)"
pad="$(cabeza_big)"
sal_cut="${pad}token=${tok_cut}"
bash "$tool" --write --dir "$SANDBOX" --task cut --hecho h \
  --comando "cmd" --salida "$sal_cut" --nivel 4 >/dev/null 2>&1
[ $? -eq 0 ] || malo "el blast de re-redaccion no salio 0"
cutf="$SANDBOX/blast-cut.json"
grep -Fq "$tok_cut" "$cutf" && malo "el token quedo en claro en el blast recortado"
grep -Fq 'token=[REDACTED]' "$cutf" || malo "la re-redaccion no restauro el marcador completo tras el corte"
if [ -r "$hook" ]; then
  h_re="$(grep -m1 '^SAIKIT_ADV_SECRET_RE=' "$hook" | sed -e 's/^SAIKIT_ADV_SECRET_RE=.//' -e "s/.$//")"
  h_strip="$(grep -m1 '^SAIKIT_ADV_REDACTED_STRIP=' "$hook" | sed -e 's/^SAIKIT_ADV_REDACTED_STRIP=.//' -e "s/.$//")"
  n_cut="$(sed -E "$h_strip" "$cutf" | grep -En "$h_re" | head -n1 | cut -d: -f1)"
  [ -z "$n_cut" ] || malo "el escaneo dispara sobre el blast re-redactado (linea $n_cut)"
fi

caso "json_escape: una comilla y un backslash se escapan y el JSON parsea"
# La invariante "siempre JSON valido" (header del tool) debe quedar discriminada
# para comilla y backslash, no solo para tab: sin el escape, una comilla cruda
# rompe el string JSON y un backslash antes de `p` es un escape invalido. Si
# alguien quitara el escape de json_escape, este caso se pone rojo.
bash "$tool" --write --dir "$SANDBOX" --task q --hecho 'a"b' \
  --comando 'cmd' --salida 'C:\path "x"' --nivel 4 >/dev/null 2>&1
[ $? -eq 0 ] || malo "el blast con comilla/backslash no salio 0"
qf="$SANDBOX/blast-q.json"
grep -Fq 'a"b' "$qf" && malo "la comilla quedo cruda dentro del string JSON"
grep -Fq 'C:\path "x"' "$qf" && malo "el backslash o la comilla no se escaparon"
if command -v jq >/dev/null 2>&1; then
  jq -e . "$qf" >/dev/null 2>&1 || malo "el artefacto con comilla/backslash no parsea como JSON (jq)"
elif command -v node >/dev/null 2>&1; then
  node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$qf" 2>/dev/null \
    || malo "el artefacto con comilla/backslash no parsea como JSON (node)"
fi

# ------------------------------------------------ (e) gate secreto (13.4)
caso "el escaneo de la sesion NO dispara sobre un blast redactado"
tok="$(form_token ghp_)"
[ -n "$tok" ] || malo "form_token ghp_ devolvio vacio"
bash "$tool" --write --dir "$SANDBOX" --task gate \
  --hecho "hecho" --comando "npm test" --salida "ok token=$tok done" --nivel 4 \
  >/dev/null 2>&1
[ $? -eq 0 ] || malo "el blast del gate no salio 0"
gfile="$SANDBOX/blast-gate.json"
grep -Fq '[REDACTED]' "$gfile" || malo "el blast del gate no trae [REDACTED]"
grep -Fq "$tok" "$gfile" && malo "el token quedo en claro en el blast"

# Replica el escaneo de artefactos del hook sobre el archivo ESCRITO.
if [ -r "$hook" ]; then
  hook_re="$(grep -m1 '^SAIKIT_ADV_SECRET_RE=' "$hook" | sed -e 's/^SAIKIT_ADV_SECRET_RE=.//' -e "s/.$//")"
  hook_strip="$(grep -m1 '^SAIKIT_ADV_REDACTED_STRIP=' "$hook" | sed -e 's/^SAIKIT_ADV_REDACTED_STRIP=.//' -e "s/.$//")"
  [ -n "$hook_re" ] || malo "el hook no declara SAIKIT_ADV_SECRET_RE"
  [ -n "$hook_strip" ] || malo "el hook no declara SAIKIT_ADV_REDACTED_STRIP"
  n="$(sed -E "$hook_strip" "$gfile" | grep -En "$hook_re" | head -n1 | cut -d: -f1)"
  [ -z "$n" ] || malo "el escaneo SI dispara sobre el blast redactado (linea $n)"

  # Negativo / prueba de que la referencia es VIVA: el MISMO escaneo dispara
  # sobre un archivo CRUDO con el token sin redactar. El token va en runtime,
  # solo adentro del sandbox; jamas en el arbol del repo.
  printf 'ok token=%s done\n' "$tok" > "$SANDBOX/raw_gate.txt"
  n_raw="$(sed -E "$hook_strip" "$SANDBOX/raw_gate.txt" | grep -En "$hook_re" | head -n1 | cut -d: -f1)"
  [ -n "$n_raw" ] || malo "el escaneo de referencia NO disparo sobre el token crudo (referencia rota)"
else
  malo "no existe el hook: $hook"
fi

if [ "$fail" -eq 0 ]; then
  echo "test_blast_artifact_contract: OK"
else
  echo "test_blast_artifact_contract: FAIL" >&2
  exit 1
fi
