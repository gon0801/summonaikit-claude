# Task 3.6 — A6: `transcript_path` es una lectura de archivo arbitrario (plan para revisión)

`[Guardrail]` `[lane:fast]` `[tdd:required]`. Cierra el defecto **A6**: el hook lee
`transcript_path` del payload y le hace `tail -n 160` sin acotar. Es una primitiva
de **lectura de archivo arbitrario** controlada por payload: quien arma el payload
elige qué archivo lee el hook.

**DoD íntegra en `Plans.md:66`**:

> `transcript_path` fuera del directorio de transcripts del host ⇒ se ignora y se
> reporta `unknown` (fail-open, no bloquea).

Depende de la 3.1 (hecha). `lane:fast` — igual que A5: el arreglo **no cambia
ningún veredicto del gate**. Fail-open (Core Rule 1 + 2): lo que no se puede leer
seguro se trata como no observado, y el gate corre con el otro canal
(`last_assistant_message`), exactamente el desenlace que hoy tiene un transcript
ilegible.

---

## El defecto, con su huella exacta

`stop_gate` (`hooks/summonaikit-harness.sh:938`) es la única función que lee
`transcript_path`. Las cuatro líneas que son A6, `:943-947`:

```sh
transcript_path="$(json_string_field transcript_path)"
tail_text=""
if [ -n "$transcript_path" ] && [ -r "$transcript_path" ]; then
  tail_text="$(tail -n 160 "$transcript_path" 2>/dev/null || true)"
fi
```

El `[ -r "$transcript_path" ]` es **lo opuesto a un guardia de seguridad**: comprueba
que el archivo *pueda* leerse, no que *deba* leerse. Cualquier ruta legible del
filesystem se acepta: `/etc/passwd`, `~/.ssh/id_rsa`, el código del propio repo,
`%APPDATA%\...\credentials.json`. El valor sale del payload, o sea que quien
controla el payload controla qué archivo se lee.

**Qué hace el hook con lo que lee.** `$tail_text` se pasa al walker
`assistant_text_transcript` (`:956`, Task 3.2), que exige estructura de mensaje
`role:"assistant"` con `content[].type:"text"`. Esa exigencia **ya redujo** el
impacto de A6 (un archivo arbitrario sin esa estructura no produce texto) —
declarado en `docs/task-3.2-plan.md:276-280`. Lo que A6 cierra es el residuo: el
hook igual le hace `tail` a una ruta arbitraria, y un archivo *plantado* con la
estructura correcta sí produce texto que influye el veredicto.

**Reproducción del vector que mueve el veredicto.** Un operador (o un turno
comprometido) planta un transcript falso con un recibo completo en un archivo fuera
del perfil del host — p.ej. `/tmp/transcript-trampa.jsonl` — y manda un payload de
`Stop` con `transcript_path` apuntando ahí y un `last_assistant_message` neutro.
Sin el arreglo:

1. `[ -r /tmp/transcript-trampa.jsonl ]` ⇒ verdadero.
2. `tail` lee el archivo; el walker extrae el recibo completo.
3. `stop_gate` ve el recibo ⇒ `$missing` vacío ⇒ **cierre limpio (exit 0)**.

El asistente no escribió nada; el gate cerró igual. Es A2 (cerrado por la 3.2) por
otra vía: en vez de usar el resultado de una herramienta, se planta el archivo
entero.

**Por qué `[lane:fast]` y no `[lane:gate]`.** La etiqueta viene del renglón
(`Plans.md:66`), no la decide este plan. Lo que *implica* es el compromiso que se
verifica en el cierre: **ningún exit code ni veredicto se mueve** salvo el del
propio vector de A6. La línea base se queda quieta (todos sus transcripts son
in-bounds — ver §4), y los gates siguen decidiendo igual con transcripts legibles
dentro del perfil.

## El arreglo

**Decisión central, que es lo que esta sección viene a fijar.** La DoD habla del
“directorio de transcripts del host”. Ese directorio **no es derivable de forma
portátil**: Claude Code lo pone bajo `~/.claude/projects/<ruta-codificada>/`, pero
(a) la codificación de la ruta es interna del host, (b) zcode usa otro layout
(Phase 5) y (c) el laboratorio del banco escribe sus transcripts en `$LAB/entrada/`,
no en `~/.claude/projects/`. Anclar a esa ruta exacta rompe portabilidad y rompe el
banco.

En su lugar se ancla al **directorio de perfil del host**, derivado barato y
portátilmente como `dirname "$HOOK_DIR"`:

| contexto | `$HOOK_DIR` | perfil = `dirname` | transcripts reales | ¿adentro? |
|---|---|---|---|---|
| install global (producción) | `~/.claude/hooks` | `~/.claude` | `~/.claude/projects/…` | sí |
| banco (lab / golden) | `$sb/hooks` | `$sb` | `$sb/entrada/…` | sí |
| staging (override de repo) | `<repo>/.claude/hooks` | `<repo>/.claude` | `~/.claude/projects/…` | **no** |

El perfil es un **superset** del directorio de transcripts: contiene `projects/`
(donde viven los transcripts reales) y es lo único que el hook puede derivar sin
conocimiento específico del host. Cierra el primitive de lectura arbitraria: lo que
está fuera del perfil (`/etc/passwd`, `~/.ssh/id_rsa`, el repo, `%APPDATA%`) ya no
se lee. Lo que queda **adentro** se declara sin eufemismos en §Límites: el perfil
real de este host contiene `.credentials.json`, `settings.json`, `history.jsonl` y
los transcripts de **todos** los proyectos y sesiones. La contención acota la raíz;
no es un permiso de lectura por archivo.

### Medición: por qué `cd`+`pwd` y no comparar strings (esto es Windows)

**Es la premisa de la que depende todo el arreglo, y estaba supuesta.** Medida
2026-08-11 en el Git Bash de esta máquina:

| paso | valor |
|---|---|
| `transcript_path` en el JSON del payload | `"C:\\Users\\ehven\\.claude\\projects\\…"` |
| lo que devuelve `json_string_field` | `C:\\Users\\ehven\\.claude\\…` — **backslashes dobles literales** (no decodifica escapes JSON) |
| `[ -r ]` sobre eso | **verdadero** (el runtime de MSYS colapsa separadores repetidos) — o sea que hoy el hook sí lee ese archivo |
| `dirname` sobre eso | `C:\\Users\\ehven\\.claude` — trata `\` como separador |
| `cd "$(dirname …)" && pwd` | `/c/Users/ehven/.claude` |
| `HOOK_DIR` (`cd`+`pwd` sobre `$0`) | `/c/Users/ehven/.claude/hooks` ⇒ perfil `/c/Users/ehven/.claude` |

Las dos formas sólo se vuelven comparables **después** de `cd`+`pwd`. Una
contención escrita como comparación de prefijo sobre el string crudo
(`case "$transcript_path" in "$PROFILE_DIR"/*`) fallaría **siempre** en producción
Windows — `C:\\Users\…` nunca empieza con `/c/Users/…` — y apagaría el canal
transcript en **toda** la producción, no sólo en staging. Sería un fail-open
silencioso: el gate seguiría corriendo con `last_assistant_message` y nadie vería
la diferencia hasta que un recibo viajara sólo por el transcript.

**Y la línea base no lo atraparía**: `tools/golden-harness.sh:251` sustituye
`__TRANSCRIPT__` por una ruta POSIX del sandbox, así que ningún escenario ejercita
la forma Windows. De acá sale el caso B de §3 — no es un caso decorativo, es la red
del único modo de fallo que la baseline no puede ver.

**La función nueva** (va justo antes de `stop_gate`, su único caller — mismo
criterio que `redact_secrets` antes de `mark_evidence` en la 3.5). **El hook es
ASCII puro** (verificado: cero bytes no-ASCII en las 1000+ líneas), así que el
comentario y el mensaje van sin acentos ni em-dash:

```sh
# Decide si una ruta de transcript esta DENTRO del directorio de perfil del host.
# Cierra A6 (Task 3.6): transcript_path viene del payload, y hacerle tail sin
# acotar es una primitiva de lectura de archivo arbitrario. El perfil es
# dirname(HOOK_DIR): en install global ~/.claude, que contiene projects/ donde
# Claude Code guarda los transcripts reales. Una ruta fuera del perfil se rechaza.
#
# Por que el perfil y no "el dir de transcripts": ese dir no es derivable de forma
# portable (la codificacion de la ruta del proyecto es interna del host; zcode usa
# otro layout en la Phase 5; el banco escribe en $sb/entrada). El perfil es un
# superset derivable que igual cierra la lectura arbitraria de /etc/passwd,
# ~/.ssh/id_rsa, el repo, %APPDATA%, etc.
#
# POR QUE cd+pwd Y NO COMPARAR EL STRING (medido, no supuesto): json_string_field
# NO decodifica escapes, asi que en Windows transcript_path llega como
# C:\\Users\\...\\x.jsonl (backslashes DOBLES literales) mientras HOOK_DIR llega
# como /c/Users/... . Comparar prefijos crudos daria FUERA siempre y apagaria el
# canal transcript en toda la produccion. cd+pwd lleva las dos a la misma forma
# (/c/Users/ehven/.claude), y de paso normaliza .. y symlinks. El "/" separador del
# segundo patron evita que ~/.claude haga sombra sobre ~/.claude-otro.
#
# Fail-open (Core Rule 2): todo lo que no se puede afirmar como dentro devuelve
# falso, el transcript se trata como no observado y el gate corre con el otro canal
# — mismo desenlace que un archivo ilegible. El guardia de PROFILE_DIR vacio NO se
# puede colapsar: con la variable vacia el patron "$PROFILE_DIR"/* se vuelve /* y
# aceptaria CUALQUIER ruta absoluta, o sea la contencion entera abierta.
#
# Limites declarados: sigue symlinks (uno bajo el perfil que apunte afuera se
# resuelve a su destino real y podria quedar fuera); y el STAGING (hook en
# <repo>/.claude/hooks) deja su transcript en ~/.claude/projects, fuera de
# <repo>/.claude, asi que en staging el canal transcript queda desactivado y el gate
# corre solo con last_assistant_message. Es aceptable: el gate es advisory, el
# recibo en un payload real de Claude viaja por last_assistant_message (medido Task
# 1.4), y staging es diagnostico. El reporte por stderr se lo dice al operador.
transcript_en_perfil() {
  if [ -n "$PROFILE_DIR" ]; then
    _tp_dir="$(cd "$(dirname "$1")" 2>/dev/null && pwd)" || _tp_dir=""
    case "$_tp_dir" in
      "$PROFILE_DIR"|"$PROFILE_DIR"/*) return 0 ;;
    esac
  fi
  printf 'summonaikit-harness: transcript_path fuera del perfil del host (%s); se ignora, transcript=unknown (fail-open, no bloquea)\n' "$1" >&2
  return 1
}
```

Tres cosas de la forma, que no son estilo:

- **Un solo punto de reporte.** En el borrador el `printf` vivía adentro de la rama
  `*)` del `case`, así que las dos vías de fallo que la DoD también cubre —
  `PROFILE_DIR` sin resolver, `cd` que falla — se iban en silencio: el canal se
  apagaba y el operador no se enteraba. Ahora las tres reportan.
- **`transcript=unknown` es literal.** La DoD dice "se ignora y se reporta
  `unknown`"; el borrador no escribía esa palabra en ningún lado y el caso que
  decía verificarla afirmaba sobre otra cosa (ver §3).
- **`_tp_dir="$(…)" || _tp_dir=""`** funciona porque la asignación toma el exit
  status de la sustitución. No anteponerle `local`/`declare`: eso se lo come y el
  fallo pasaría inadvertido.

`PROFILE_DIR` se deriva junto a `HOOK_DIR` (`:25`), una línea:

```sh
PROFILE_DIR="$(cd "$HOOK_DIR/.." 2>/dev/null && pwd)"
```

Y en `stop_gate` (`:945`), la condición del `if` gana el guardia de contención.
**Se conserva `[ -r ]`** como fast-path (archivo no existente ⇒ se salta sin invocar
la función; comportamiento idéntico al de hoy para transcripts inexistentes):

```sh
# antes:
if [ -n "$transcript_path" ] && [ -r "$transcript_path" ]; then
# despues:
if [ -n "$transcript_path" ] && [ -r "$transcript_path" ] && transcript_en_perfil "$transcript_path"; then
```

**Sobre el “reporta `unknown`”.** La DoD pide que se reporte. Hay dos lecturas, y se
elige la que hace el arreglo observable:

- *Postura* (Core Rule 2): el hook no afirma haber observado el transcript; lo trata
  como no observado (`$tail_text=""`). Es el mismo desenlace que un transcript
  ilegible, y ya es fail-open.
- *Reporte literal*: una línea a **stderr** cuando se detecta y se ignora una ruta
  fuera del perfil.

Se opta por **las dos**, y la línea **dice `transcript=unknown` con esa palabra**.
No es cosmética: es lo que hace que la DoD se cierre por lectura literal y no por
interpretación, y lo que le da al caso de prueba algo honesto que afirmar. En
producción la línea **nunca** se emite (los transcripts reales siempre viven bajo
`~/.claude` — ver la medición de arriba, que es justamente lo que garantiza que no
se emita). En
staging se emite en cada `Stop` — y es justamente la pista que le dice al operador
*por qué* staging no ve el transcript (esperado, declarado). En el banco es lo que
el caso nuevo afirma (`LAB_ERR`). No afecta el contrato de salida del hook (stdout
y exit code van separados; stderr en un `Stop` de Claude es informativo, no decide).

**Alternativa considerada y descartada — contención union (`dirname $HOOK_DIR` ∪
`$HOME/.claude`).** Sumar `$HOME/.claude` como segunda raíz dejaría el transcript de
staging in-bounds y mantendría el canal vivo ahí. Se descarta: endurece la regla con
un literal de host (`.claude`) que la Phase 5 tendría que duplicar para zcode, y
ensucia el check por un beneficio en un modo de diagnóstico. Si la revisión concluye
que la pérdida del canal en staging no es aceptable, ésta es la alternativa a
reabrir.

**No se migra `transcript_path` a `json_top_level_string`.** Hoy se lee con
`json_string_field` (greedy — el defecto A1). Un eco de `transcript_path` dentro de
`tool_response` podría hacer que el lector greedy tome una ruta controlada por el
turno. **No hace falta migrarlo para cerrar A6**: la contención neutraliza cualquier
ruta que se lea, venga de donde venga. Migrar el lector es una mejora de
consistencia (con `session_id`, que sí se migró en la 3.4) pero tocar el lector
podría mover la línea base, y cada tarea cierra un defecto medido. Se declara fuera
de alcance.

## Cambios

### 1. `hooks/summonaikit-harness.sh`

**(a)** `PROFILE_DIR="$(cd "$HOOK_DIR/.." 2>/dev/null && pwd)"` justo después de la
derivación de `HOOK_DIR` (`:25`).

**(b)** Función `transcript_en_perfil` nueva, justo antes de `stop_gate` (`:938`),
con la cabecera de arriba.

**(c)** En `stop_gate` (`:945`), agregar `&& transcript_en_perfil "$transcript_path"`
a la condición del `if`. Nada más se toca en `stop_gate`. El `tail` y el comentario
de la 3.2 (que explica por qué se conserva `tail -n 160`) quedan intactos.

### 2. `tests/lib/hook_lab.sh` — un constructor nuevo

Necesita un payload de `Stop` cuyo `transcript_path` sea una ruta **literal** (no el
token `__TRANSCRIPT__`), porque `lab_run` sustituye `__TRANSCRIPT__` por la ruta
dentro del banco. Sin este constructor, no hay forma de apuntar el transcript afuera
del banco:

```sh
# Para el caso A6 (Task 3.6): un payload de Stop cuyo transcript_path es una ruta
# LITERAL (no el token __TRANSCRIPT__), asi lab_run no la reescribe. Sirve para
# apuntar el transcript a un archivo fuera del perfil del host y probar que el hook
# se niega a leerlo (fail-open). El argumento va antes para que el caso se lea como
# "stop con este mensaje y esta ruta".
lab_payload_stop_ruta_literal() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"%s","cwd":"/proyecto","prompt_id":"c1a70000-1111-4222-8333-777788889999","permission_mode":"auto","effort":{"level":"xhigh"},"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"%s","background_tasks":[],"session_crons":[]}' "$2" "$1"
}
```

Dos notas de uso, porque las dos son trampas medidas:

- **La ruta se inserta cruda en un JSON.** Con una ruta POSIX no pasa nada, pero el
  caso B usa forma Windows y ahí los `\` tienen que ir escapados (`\\`) o el
  payload deja de ser JSON válido y el walker de la 3.2 se queda mudo por la razón
  equivocada.
- `lab_run` no toca este payload (no trae `__TRANSCRIPT__`), así que **el archivo
  de transcript lo crea el caso**, no el banco.

### 3. `tests/lib/gate_cases.sh` — G4: **dos** casos nuevos (regla de hierro #2)

El borrador traía uno solo. Falta el segundo: el arreglo tiene **dos** modos de
fallo opuestos y sólo uno estaba cubierto. El caso A ata "no leer lo de afuera"
(el defecto). El caso B ata "seguir leyendo lo de adentro" (la regresión), que es
justamente lo que la línea base no puede ver porque no ejercita rutas Windows.

**Caso A — `caso_g4_transcript_fuera_de_perfil_se_ignora`**, el caso que habría
atrapado A6. Un transcript con un recibo completo se planta **fuera** del banco
(`mktemp` crea en el temporal del sistema, fuera de `$LAB` = perfil del hook del
banco). El recibo vive **únicamente** ahí; el `last_assistant_message` es neutro.
Con el arreglo el gate no lo ve y bloquea; sin el arreglo lo lee y cierra limpio.

```sh
# DEFECTO A6, el caso que lo habria atrapado. transcript_path sale del payload y el
# hook le hacia tail sin acotar: primitiva de lectura de archivo arbitrario. Un
# payload con transcript_path apuntando a un transcript falso plantado fuera del
# perfil del host (aqui, fuera del banco) entregaba un recibo que el asistente no
# escribio, y el gate cerraba limpio. El arreglo (Task 3.6) exige que la ruta
# resuelva DENTRO del perfil (dirname HOOK_DIR); fuera de ahi se ignora (fail-open)
# y el gate corre solo con last_assistant_message.
caso_g4_transcript_fuera_de_perfil_se_ignora() {
  _sembrar_turno_completo
  # Transcript con recibo valido, AFUERA de $LAB. mktemp crea bajo el temporal del
  # sistema (run.sh lo apunta a la caja del test), y $LAB es un subdirectorio de
  # ahi: el hermano queda fuera del perfil del hook del banco.
  _tr_externo="$(mktemp "${TMPDIR:-/tmp}/saikit-a6-XXXXXX.jsonl")" || { _mal "no se pudo crear transcript externo"; return; }
  printf '%s\n' "$(lab_transcript_asistente "$_RECIBO_VINETAS")" > "$_tr_externo"
  # Stop con transcript_path = ruta externa literal y mensaje neutro (sin recibo).
  lab_run stop claude "$(lab_payload_stop_ruta_literal 'Listo.' "$_tr_externo")"
  rm -f "$_tr_externo"
  _igual "exit code (el transcript externo se ignora, A6)" "$LAB_RC" "2"
  _contiene "motivo (el recibo externo no cuenta)" "$LAB_OUT" 'Missing SUMMONAIKIT HARNESS RECEIPT'
  _contiene "reporte por stderr (fail-open, A6)" "$LAB_ERR" 'transcript=unknown'
  if ! lab_hay_estado; then _mal "el turno sigue abierto: el estado no se borra mientras el gate reclama"; fi
}
```

Cuatro detalles que cambiaron respecto del borrador:

1. La aserción de stderr afirmaba `'fuera del perfil'` bajo una etiqueta que decía
   "reporte unknown". Ahora afirma **`transcript=unknown`**, que es lo que la DoD
   pide y lo que el mensaje ahora dice.
2. El `rm -f` se movió **antes** de las aserciones: `_mal` no corta el caso, pero un
   `return` temprano futuro sí dejaría basura en el temporal.
3. Se agregó la aserción de **estado** (`lab_hay_estado`), que todos los demás casos
   G4 que bloquean tienen y a éste le faltaba.
4. `mktemp` con las `X` **antes** del sufijo `.jsonl` es la forma que parece
   inválida y no lo es: GNU coreutils implica `--suffix` cuando el template no
   termina en `X`. Verificado en esta máquina.

**Caso B — `caso_g4_transcript_ruta_windows_y_traversal`**, la guardia de la
regresión. Dos mitades baratas en un solo caso:

```sh
# La otra mitad del arreglo de A6: la contencion NO puede apagar el canal legitimo.
# Dos vectores que una comparacion de strings crudos manejaria mal:
#   (a) forma WINDOWS: en produccion transcript_path llega como C:\\Users\\... y
#       HOOK_DIR como /c/Users/... . Solo cd+pwd las vuelve comparables; sin eso el
#       canal transcript se apaga en TODA la produccion y ningun escenario de la
#       linea base lo ve (todos usan rutas POSIX del sandbox).
#   (b) TRAVERSAL: una ruta que arranca adentro del perfil y sale con .. tiene el
#       prefijo correcto y el destino equivocado. cd+pwd la resuelve antes de mirar.
caso_g4_transcript_ruta_windows_y_traversal() {
  # (a) recibo en un transcript ADENTRO del perfil, apuntado en forma Windows.
  _sembrar_turno_completo
  _tr_dentro="$LAB/entrada/transcript-a6-win.jsonl"
  printf '%s\n' "$(lab_transcript_asistente "$_RECIBO_VINETAS")" > "$_tr_dentro"
  if command -v cygpath >/dev/null 2>&1; then
    # cygpath -w da C:\...\x.jsonl; el JSON necesita los backslashes escapados.
    _tr_win="$(cygpath -w "$_tr_dentro" | sed 's/\\/\\\\/g')"
    lab_run stop claude "$(lab_payload_stop_ruta_literal 'Listo.' "$_tr_win")"
    _igual "exit code (ruta Windows in-bounds SI se lee)" "$LAB_RC" "0"
    _vacio "stdout (cierre limpio con el recibo del transcript)" "$LAB_OUT"
  fi
  # (b) una ruta que ARRANCA adentro del perfil y sale con ..: el prefijo crudo
  # matchea, el destino real no. Se re-siembra porque si (a) corrio, cerro limpio
  # y borro el estado del turno.
  _sembrar_turno_completo
  _tr_externo="$(mktemp "${TMPDIR:-/tmp}/saikit-a6-XXXXXX.jsonl")" || { _mal "no se pudo crear transcript externo"; return; }
  printf '%s\n' "$(lab_transcript_asistente "$_RECIBO_VINETAS")" > "$_tr_externo"
  lab_run stop claude "$(lab_payload_stop_ruta_literal 'Listo.' "$LAB/entrada/../../$(basename "$_tr_externo")")"
  rm -f "$_tr_externo"
  _igual "exit code (traversal fuera del perfil se ignora)" "$LAB_RC" "2"
  _contiene "reporte por stderr (traversal)" "$LAB_ERR" 'transcript=unknown'
}
```

> **El re-sembrado del medio no es opcional**: la mitad (a) cierra limpio y eso
> borra el estado del turno, así que sin re-sembrar la (b) correría contra un
> `$STATE_PATH` inexistente y `stop_gate` saldría por `emit_allow` — verde por vacío,
> el modo de fallo que esta suite existe para evitar. `_sembrar_turno_completo` a
> secas sirve para los dos caminos (con y sin `cygpath`). Si al escribirlo queda
> enredado, partir el caso en dos: los dos vectores atrapan la misma mutación, así
> que partirlo no cuesta cobertura — cuesta ~2 s de corrida.

**Medido hoy sobre la función aislada** (banco sintético, las cuatro rutas):
`$LAB/entrada/t.jsonl` ⇒ DENTRO; `/tmp/saikit-a6-X.jsonl` ⇒ FUERA;
`$LAB/entrada/../../saikit-a6-X.jsonl` ⇒ FUERA; `${LAB}-otro/sub/t.jsonl` ⇒ FUERA
(el vecino con prefijo compartido, que es lo que el `/` del segundo patrón evita).

**La guarda in-bounds POSIX ya existe** y no se duplica:
`caso_g4_recibo_solo_en_transcript_pasa` pone el recibo en `$LAB/entrada/…` y exige
cierre limpio. Si la contención quedara estricta de más y rechazara todo, ese caso
se pondría rojo — pero sólo para rutas POSIX; la forma Windows es el hueco que el
caso B tapa.

**Orden en `CASOS_G4`**: los dos casos nuevos van **al final**, A antes que B
(`… caso_g4_recibo_solo_en_transcript_pasa caso_g4_transcript_fuera_de_perfil_se_ignora
caso_g4_transcript_ruta_windows_y_traversal`). Mismo criterio que la 3.2 y la 3.5:
la batería corta en el primer rojo. Verificado contra el catálogo actual:

- **A es verde bajo todas las mutaciones no-A6** (el recibo genuinamente falta y el
  transcript externo se ignora), así que no roba declaraciones.
- **B se pone rojo bajo `mut_canal_transcript_vacio`** — pero
  `caso_g4_recibo_corrido_solo_en_transcript_pasa` (posición 10) también, y va
  antes, así que el crédito de esa mutación no se mueve.
- **Bajo `containment_sin_resolver` A sigue verde** (`/tmp` no empieza con
  `$LAB/`), así que B es el único rojo y se lleva su mutación.

### 4. `tests/test_gate_mutations.sh` — 26 → **28** (G4: 7 → **9**)

Dos mutaciones, una por caso. El borrador traía una sola: sin la segunda, `cd`+`pwd`
—la única parte del arreglo que la producción Windows necesita— no estaría atada por
nada, y podría reemplazarse por una comparación cruda sin que un solo test se
inmutara.

```sh
# A6 (Task 3.6), primera mitad: se neutraliza la contencion, de modo que el hook
# vuelve a leer cualquier transcript_path. caso_g4_transcript_fuera_de_perfil_se_ignora
# planta un recibo en un transcript fuera del perfil; con la contencion anulada el
# hook lo lee y cierra limpio (exit 0), cuando el caso espera exit 2. La mutacion
# ademas FIJA LA UBICACION del arreglo: si la contencion se mudara a otro sitio, el
# sed no matchea y salta la guardia 2 del driver.
mut_transcript_sin_containment() { sed 's/transcript_en_perfil "$transcript_path"/true/'; }
# Segunda mitad: la contencion sigue ahi pero deja de RESOLVER la ruta, y compara el
# string crudo. Es el error que apagaria el canal en produccion Windows (C:\\Users\\
# nunca empieza con /c/Users/) y el que deja pasar un traversal con .. . Lo atrapa
# caso_g4_transcript_ruta_windows_y_traversal por cualquiera de sus dos mitades.
mut_containment_sin_resolver() { sed 's|_tp_dir="$(cd "$(dirname "$1")" 2>/dev/null \&\& pwd)" \|\| _tp_dir=""|_tp_dir="$(dirname "$1")"|'; }
```

```
G4|transcript_sin_containment|la contención de transcript_path se anula y se vuelve a leer cualquier ruta
G4|containment_sin_resolver|la contención compara la ruta cruda en vez de resolverla con cd+pwd
```

Sobre el `$`: el borrador escribía `"\$transcript_path"` y a la vez afirmaba "sin
escapar el `$`". Probadas las dos formas contra la línea real — **las dos funcionan**
(en BRE un `$` a mitad de patrón es literal, y GNU sed trata `\$` igual), pero se
deja **sin** backslash para no meter escapes en un `sed` de MSYS2, que es la trampa
documentada en `:128-131` y el criterio que ya sigue `mut_redaccion_quitada`.

`mut_containment_sin_resolver` usa `|` como delimitador (el patrón trae `/`) y
escapa `&&` y los `|` del `||`. Al implementar, **verificar la guardia 2** (`cmp -s`:
el archivo tiene que cambiar) antes de dar por buena la mutación: un `sed` de una
línea entera es el más fácil de dejar obsoleto. Ambas dejan el `if` con cuerpo y
`bash -n` pasa.

### 5. `tests/golden/baseline.txt` — sin re-grabar

**La línea base no cambia**: `0 escenarios divergentes en --check`. Esa es la
evidencia.

La razón medida: `tools/golden-harness.sh:244` escribe cada transcript del banco en
`$sb/entrada/transcript-$n.jsonl`, y el hook vive en `$sb/hooks/summonaikit-harness.sh`
(`:215`). Con `$HOOK_DIR=$sb/hooks`, el perfil es `dirname "$HOOK_DIR"` = `$sb`, y
`$sb/entrada/…` cae **adentro**. Así que en los 16 escenarios la contención devuelve
`0` (se lee igual que hoy), el `[ -r ]` se conserva, y la línea de stderr **no se
emite** (no hay nada out-of-bounds). Comportamiento byte-idéntico.

`--check` confirma que la identidad no decide: `tools/golden-harness.sh:311-319`
imprime el cambio de `hook_sha256` como `[nota]` informativa y compara
**comportamiento**, no bytes. Re-grabar es opcional y mueve sólo las 3 líneas de
identidad del encabezado (`hook_sha256`, `hook_bytes`, `hook_lineas`). Cualquier
movimiento de `=== escenario` en adelante es regresión. No se agrega escenario
nuevo: A6 es `lane:fast`, no cambia veredictos, y sus casos viven en la suite.

**Lo que la línea base NO puede declarar, y hay que decirlo al cerrar**: ningún
escenario usa una ruta Windows (todos sustituyen `__TRANSCRIPT__` por una ruta POSIX
del sandbox), así que "0 divergentes" **no** es evidencia de que el canal transcript
siga vivo en producción. Esa evidencia la da el caso B, no la baseline.

## Verificación

1. `pre-commit run --all-files` (sin `--no-verify`, regla de hierro #1).
2. `bash tests/run.sh` → 0 FAIL, 0 UNKNOWN.
3. **28 mutaciones, 28 atrapadas**, con las dos nuevas acreditadas a **su** caso en
   la declaración que emite la corrida (no a un caso anterior).
4. Declaración del diff de la línea base (esperado: 0 escenarios divergentes) **con
   la salvedad de arriba**: la baseline no cubre la forma Windows.
5. Cross-review con codex **sobre staged antes de commit** (lección de la 3.2), tope
   1 ronda — es el paso 5 del orden de abajo, no un paso aparte.
6. **El install del hook no es parte de la verificación**: va después del commit
   (orden TDD, paso 8).

## Orden (TDD)

1. Los dos casos G4 nuevos + las dos mutaciones, en **rojo** contra el hook sin tocar
   (`bash tests/run.sh`):
   - `caso_g4_transcript_fuera_de_perfil_se_ignora` ⇒ el transcript externo **sí** se
     lee y el gate cierra limpio (exit 0). El caso espera exit 2 ⇒ rojo.
   - `caso_g4_transcript_ruta_windows_y_traversal` ⇒ hoy **las dos mitades pasan** (el
     hook lee cualquier ruta), así que la mitad (a) queda verde y la (b) roja. Rojo
     igual, pero por una sola mitad: anotarlo, porque es la señal de que la mitad (a)
     no prueba nada hasta que el arreglo exista.
2. Arreglo en el hook (`PROFILE_DIR` + `transcript_en_perfil` + la cláusula del `if`).
3. `SAIKIT_HOOK_VIVO="$PWD/hooks/summonaikit-harness.sh" bash tests/run.sh` → verde.
   (Lección de la 3.5, CORRECCIÓN 4: el runner resuelve el hook vivo en
   `$HOME/.claude/hooks` y sólo `SAIKIT_HOOK_VIVO` lo redirige a la fuente del repo
   — `tests/run.sh:72`; sin esa variable la suite mediría el hook instalado, que
   todavía no tiene el arreglo.)
4. `--check` de la línea base y declaración del diff (esperado: 0 divergentes).
5. Cross-review con codex, 1 ronda **sobre staged**, antes de commitear.
6. `pre-commit run --all-files` (sin `--no-verify`).
7. Commit: `feat(3.6): A6 cerrado — contención de transcript_path al perfil del host`.
8. `tools/install-hook.sh` — **después** del commit, no antes.
9. Cierre en `Plans.md`, DoD punto por punto (`cc:TODO` → `cc:完了 [sha]`).

La cross-review del **documento** (este `.md`) es lo que corre ahora; la del código
es el paso 5.

## No entra en esta tarea (límites declarados)

- **El gate sigue `advisory`.** A6 cierra una primitiva de **lectura** arbitraria;
  no vuelve al gate un control de seguridad. Quien controla el payload sigue
  pudiendo influir el veredicto por otras vías (p.ej. el texto del propio recibo en
  `last_assistant_message`).
- **No se cierra el cross-host (staging).** En staging el transcript vive en
  `~/.claude/projects/` y el hook en `<repo>/.claude/hooks`, fuera del perfil
  derivado. Ahí el canal transcript queda desactivado (fail-open) y el gate corre
  solo con `last_assistant_message`. Declarado y aceptable: el recibo real de
  Claude viaja por el payload (medido Task 1.4), y staging es diagnóstico. El
  cross-host como defecto de *estado* es la Task 5.3.
- **No se migra `transcript_path` a `json_top_level_string`.** La contención
  neutraliza cualquier ruta leída, venga del lector greedy o del escáner. Migrar es
  consistencia con `session_id` (3.4), pero mueve la línea base y no cierra A6.
- **Symlinks.** `cd "$(dirname …)" && pwd` resuelve symlinks: uno plantado bajo el
  perfil que apunte afuera se resuelve a su destino y podría quedar fuera (seguro:
  fail-open); uno legítimo alcanzado vía symlink podría resolverse afuera y
  ignorarse. En transcripts reales de Windows no hay symlinks. Límite de la
  técnica, declarado.
- **Case-insensitivity de Windows.** `~/.Claude` vs `~/.claude`: el `case` de bash
  distingue. En la práctica el perfil viene del propio host con el casing canónico.
  Límite declarado, no perseguido.
- **No es un denylist, y adentro del perfil hay cosas sensibles.** La contención es
  por **raíz**, no por lista negra. Medido en el perfil real de esta máquina, quedan
  **in-bounds**: `~/.claude/.credentials.json` (761 B), `~/.claude/settings.json`,
  `~/.claude/history.jsonl` (1.7 MB) y los transcripts de **todos** los proyectos y
  **todas** las sesiones, no sólo la del turno. O sea que un payload puede seguir
  apuntando el `tail` a cualquiera de esos. Lo que se cierra es salir del perfil; lo
  que queda es un residuo acotado y **declarado**, no cubierto. Por qué se acepta:
  el walker de la 3.2 no produce texto de un archivo sin estructura de transcript,
  `$tail_text` no se persiste a ningún lado (sólo alimenta los `grep` de `$text`), y
  el contenido del perfil ya es legible por el proceso que corre el hook. Cerrarlo
  del todo pide anclar a `projects/` — que es exactamente lo que §El arreglo
  descarta por portabilidad. Si esto no se considera aceptable, la alternativa a
  reabrir es la misma que la de la unión: endurecer con un literal de host.
- **Un transcript de OTRA sesión sigue contando.** Es la variante de sesión del
  límite que la 3.2 ya declaró para los turnos ("un recibo de hace 5 turnos dentro
  de las últimas 160 líneas sigue contando"). No lo amplía esta tarea ni lo cierra.

---

## Revisión del plan — qué se corrigió y contra qué se verificó

Revisión del documento contra el código real (`hooks/summonaikit-harness.sh`,
`tests/lib/hook_lab.sh`, `tests/lib/gate_cases.sh`, `tests/test_gate_mutations.sh`,
`tests/run.sh`, `tools/golden-harness.sh`), 2026-08-11. **10 correcciones, 3
bloqueantes.**

| # | sev | qué estaba mal | dónde |
|---|---|---|---|
| 1 | **bloq** | La premisa de portabilidad estaba **supuesta**. `json_string_field` no decodifica escapes: en Windows `transcript_path` llega con backslashes dobles literales y `HOOK_DIR` en forma `/c/...`. Sin `cd`+`pwd` la contención apagaría el canal en **toda** la producción, y la línea base no lo vería | §El arreglo (medición nueva) |
| 2 | **bloq** | La DoD pide "se reporta `unknown`" y esa palabra no aparecía en ningún lado; el caso decía verificarla y afirmaba sobre `'fuera del perfil'` | §El arreglo, §3 |
| 3 | **bloq** | Faltaba el caso de la **regresión** (in-bounds en forma Windows + traversal) y su mutación: `cd`+`pwd` no quedaba atado por nada | §3, §4 |
| 4 | media | El reporte a stderr sólo se emitía en la rama `*)` del `case`; con `PROFILE_DIR` sin resolver o `cd` fallido el canal se apagaba en silencio | §El arreglo |
| 5 | media | El snippet del `sed` escribía `"\$transcript_path"` y el texto de al lado afirmaba "sin escapar el `$`". Probadas las dos formas: **las dos funcionan**; se deja sin backslash por el criterio MSYS2 ya vigente | §4 |
| 6 | media | El hook es **ASCII puro** (verificado, cero bytes no-ASCII) y el comentario y el `printf` propuestos traían em-dash, acentos y comillas tipográficas | §El arreglo |
| 7 | baja | El caso A no afirmaba sobre el estado (todos los demás casos G4 que bloquean sí) y hacía el `rm -f` después de las aserciones | §3 |
| 8 | baja | §Límites decía que lo de adentro del perfil "es propiedad del host que el hook ya gestiona" — suaviza que ahí vive `.credentials.json` (existe, 761 B) | §Límites |
| 9 | baja | §Verificación y §Orden se contradecían sobre cuándo corre la cross-review ("el paso 3-and-after del commit") | §Verificación, §Orden |
| 10 | baja | Referencias de línea: `docs/task-3.2-plan.md:278-280` → `:276-280`; se agregaron `tests/run.sh:72`, `tools/golden-harness.sh:251` y `:311-319` | varias |

**Lo que se verificó y quedó como estaba** (no son correcciones, son confirmaciones
de que el plan tenía razón):

- `stop_gate` (`:938`) es la **única** función que lee `transcript_path`; las líneas
  son `:943-946`, y `HOOK_DIR` está en `:25`. ✔
- El catálogo de mutaciones tiene hoy **26**, de las cuales **7 son G4**. ✔
- El perfil del banco es `$LAB` y sus transcripts van a `$LAB/entrada/` ⇒ in-bounds;
  el del arnés dorado es `$sb` con transcripts en `$sb/entrada/` ⇒ in-bounds. La
  línea base no se mueve por esta razón. ✔
- `--check` trata la identidad del hook como `[nota]` informativa y compara
  comportamiento. ✔
- Ningún caso existente afirma `_vacio "$LAB_ERR"` sobre un `Stop` con transcript,
  así que la línea nueva de stderr no rompe nada: los casos sin transcript apuntan a
  un archivo inexistente y el `[ -r ]` los saca antes de llegar a la función. ✔
- `mktemp` con `XXXXXX.jsonl` (X's no finales) **funciona**: GNU coreutils implica
  `--suffix`. ✔
- La función, probada aislada sobre un banco sintético, da DENTRO / FUERA / FUERA /
  FUERA para in-bounds, hermano externo, traversal con `..` y vecino con prefijo
  compartido. ✔
