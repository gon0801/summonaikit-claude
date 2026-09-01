#!/usr/bin/env bash
# Task 0.5 — la CLASIFICACION de `tools/hook-acl.ps1`, que es el unico codigo
# destructivo del repo.
#
# Que se prueba y que no. Escribir ACL de verdad no es unit-testable (mismo
# motivo declarado en las Tasks 0.1 y 0.2), pero la parte que decide QUE se
# borra si lo es: es logica pura sobre un SID. Ahi es donde estaban los tres
# defectos que rindio la revision cruzada, asi que ahi van los casos. Lo que
# queda del lado no testeable se afirma con la auditoria sin `-Fix`, que
# muestra que tocaria sin tocar nada.
#
# El script termina en `exit`, asi que no se puede dot-sourcear tal cual: con
# SAIKIT_HOOKACL_LIB_ONLY=1 devuelve el control despues de definir sus
# funciones y antes de ejecutar nada.
#
# Core Rule 4: jamas se corre contra `~/.claude`. Todo va contra un tmpdir.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tool="$here/../tools/hook-acl.ps1"

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

pwsh_bin=''
for c in powershell.exe powershell pwsh; do
  if command -v "$c" >/dev/null 2>&1; then pwsh_bin="$c"; break; fi
done
if [ -z "$pwsh_bin" ]; then
  echo "  SKIP: no hay powershell en esta maquina."
  echo "test_hook_acl: OK (skip declarado)"
  exit 0
fi

tmp="$(mktemp -d)" || { echo "test_hook_acl: FAIL (mktemp)" >&2; exit 1; }
trap 'rm -rf "$tmp"' EXIT

if command -v cygpath >/dev/null 2>&1; then
  tool_win="$(cygpath -w "$tool")"
else
  tool_win="$tool"
fi

# Corre un fragmento de PowerShell con las funciones del script ya cargadas.
con_lib() {
  SAIKIT_HOOKACL_LIB_ONLY=1 "$pwsh_bin" -NoProfile -ExecutionPolicy Bypass -Command "
    \$ErrorActionPreference = 'Stop'
    . '$tool_win'
    $1
  " 2>&1
}

# ------------------------------------------------- 1) el modo biblioteca existe
caso "el script se puede cargar sin ejecutar nada"
out="$(con_lib "Write-Output 'cargado'")"
printf '%s' "$out" | grep -q 'cargado' \
  || malo "no se pudo cargar solo las funciones: $out"

# --------------------------------- 2) resoluble / no resoluble / NO SE PUDO SABER
# El defecto: `Test-SidResolvable` devolvia \$false ante CUALQUIER excepcion, y
# ese \$false BORRA el ACE. Un fallo transitorio de resolucion (un controlador de
# dominio que no contesta) alcanzaba para borrarle el acceso a una cuenta viva.
caso "un SID vivo se clasifica resoluble"
out="$(con_lib "Write-Output ([string](Test-SidResolvable 'S-1-5-18'))")"
printf '%s' "$out" | grep -qi 'true' \
  || malo "SYSTEM (S-1-5-18) tiene que ser resoluble: $out"

caso "un SID bien formado que NO existe se clasifica no resoluble"
out="$(con_lib "Write-Output ([string](Test-SidResolvable 'S-1-5-21-1111111111-2222222222-3333333333-4444'))")"
printf '%s' "$out" | grep -qi 'false' \
  || malo "una cuenta borrada tiene que dar False: $out"

caso "lo que NO se pudo determinar no es 'no resoluble' (Core Rule 2)"
# Se distingue por TIPO: IdentityNotMappedException es haber mirado y no
# encontrar; cualquier otra excepcion es no haber podido mirar. El segundo caso
# tiene que devolver \$null (unknown), no \$false.
out="$(con_lib "
  \$r = Test-SidResolvable 'esto-no-es-un-sid'
  if (\$null -eq \$r) { Write-Output 'UNKNOWN' } else { Write-Output ('VALOR:' + [string]\$r) }
")"
printf '%s' "$out" | grep -q 'UNKNOWN' \
  || malo "un SID que no se pudo evaluar debe dar unknown, no False: $out"

# ------------------------------------- 3) la politica de reparacion es una sola
# El defecto: en la raiz un principal resoluble se DEGRADABA a ReadAndExecute y
# en los hijos se ELIMINABA entero. Y `-OrphansOnly` filtraba la raiz pero no
# los descendientes, asi que borraba ACE de cuentas VIVAS.
caso "la decision por hallazgo es unica: degradar / eliminar / no tocar"
out="$(con_lib "
  foreach (\$c in @(
      @{ n='resoluble';  r=\$true  },
      @{ n='huerfano';   r=\$false },
      @{ n='unknown';    r=\$null  })) {
    \$f = [pscustomobject]@{ Resolvable = \$c.r }
    Write-Output (\$c.n + '=' + (Get-AclRepairAction -Finding \$f))
  }
")"
printf '%s' "$out" | grep -q 'resoluble=degradar' || malo "un principal vivo se degrada, no se elimina: $out"
printf '%s' "$out" | grep -q 'huerfano=eliminar'  || malo "una cuenta borrada se elimina: $out"
printf '%s' "$out" | grep -q 'unknown=no-tocar'   || malo "ante lo que no se pudo determinar NO se toca: $out"

caso "-OrphansOnly usa el MISMO criterio en la raiz y en los descendientes"
out="$(con_lib "
  \$vivo     = [pscustomobject]@{ Resolvable = \$true;  IsInherited = \$false }
  \$huerfano = [pscustomobject]@{ Resolvable = \$false; IsInherited = \$false }
  \$unknown  = [pscustomobject]@{ Resolvable = \$null;  IsInherited = \$false }
  \$sel = @(Select-RepairableFinding -Findings @(\$vivo, \$huerfano, \$unknown) -OrphansOnlyMode)
  Write-Output ('seleccionados=' + \$sel.Count)
  foreach (\$s in \$sel) { Write-Output ('resolvable=' + [string]\$s.Resolvable) }
")"
printf '%s' "$out" | grep -q 'seleccionados=1' \
  || malo "con -OrphansOnly solo entra el huerfano, ni el vivo ni el unknown: $out"
printf '%s' "$out" | grep -qi 'resolvable=False' \
  || malo "el unico seleccionado tiene que ser el no resoluble: $out"

# ------------------------------- 3-bis) el REPORTE tambien distingue los tres
# La Task 0.5 declara la auditoria sin `-Fix` como LA evidencia de la mitad que
# no es unit-testable. Si esa salida llama "SID huerfano" a un principal que no
# se pudo evaluar, la superficie que el operador lee para decidir confunde
# exactamente lo que la tarea vino a arreglar. Decidir bien no alcanza: hay que
# decirlo bien.
caso "un finding que no se pudo evaluar NO se imprime como huerfano"
out="$(con_lib "
  \$unknown = [pscustomobject]@{
    Path = 'C:\\x'; Identity = 'S-1-5-21-9-9-9-9'; Sid = 'S-1-5-21-9-9-9-9'
    Rights = 'Modify'; IsInherited = \$false; Resolvable = \$null; Rule = \$null }
  Write-FindingSummary -Findings @(\$unknown)
")"
printf '%s' "$out" | grep -qi 'huerfano' \
  && malo "un SID que no se pudo evaluar se reporta como cuenta borrada: $out"
printf '%s' "$out" | grep -qi 'no se pudo' \
  || malo "el reporte no dice que no se pudo determinar: $out"

caso "el reporte sigue nombrando huerfano al que SI se midio ausente"
out="$(con_lib "
  \$huerfano = [pscustomobject]@{
    Path = 'C:\\x'; Identity = 'S-1-5-21-9-9-9-9'; Sid = 'S-1-5-21-9-9-9-9'
    Rights = 'Modify'; IsInherited = \$false; Resolvable = \$false; Rule = \$null }
  Write-FindingSummary -Findings @(\$huerfano)
")"
printf '%s' "$out" | grep -qi 'huerfano' \
  || malo "una cuenta borrada SI se nombra huerfana: $out"

# --------------------------- 3-ter) el caveat de alcance nombra lo no observado
# Punto 4 (ciclo 16.12): una raiz extra ausente o saltada por el guard de
# reparse point es TAMBIEN alcance acotado (Core Rule 2) -- antes
# `Get-ScopeCaveat` solo sabia de `-RootOnly`/`-OrphansOnly`, asi que una
# skills-root sin observar podia colarse detras de un "OK:" pelado en vez de
# "OK (ALCANCE ACOTADO)". Se prueba la logica pura via el modo biblioteca,
# sin depender de que ESTE host tenga la raiz principal perfectamente limpia
# (bajo %TEMP% casi nunca lo esta).
caso "una raiz no observada aparece NOMBRADA en el veredicto, nunca un OK pelado"
out="$(con_lib "
  \$script:RaicesNoObservadas = @('C:\\ruta\\ausente (ausente)')
  Write-CleanResult 'ningun principal fuera de la keep-list tiene escritura.'
")"
printf '%s' "$out" | grep -qi 'OK (ALCANCE ACOTADO)' \
  || malo "una raiz no observada no dispara el veredicto acotado: $out"
printf '%s' "$out" | grep -qF 'C:\ruta\ausente' \
  || malo "el caveat no nombra la raiz que quedo sin observar: $out"

# Gap 4 (segundo ciclo, 16.12): el caso de arriba asigna `RaicesNoObservadas`
# A MANO -- no ejercita el codigo real que la alimenta. Borrar las lineas
# `$script:RaicesNoObservadas += ...` en `Resolve-AuditRoots` (raiz ausente,
# ~linea 306) NO ponia rojo ningun caso de la bateria. Aca se llama a
# `Resolve-AuditRoots` de verdad, con una raiz ausente, y DESPUES a
# `Write-CleanResult`: el veredicto tiene que nombrar esa raiz. Ejercita la via
# real sin tocar una sola ACL (modo biblioteca).
caso "Resolve-AuditRoots alimenta RaicesNoObservadas de verdad (no a mano) y el veredicto la nombra"
if command -v cygpath >/dev/null 2>&1; then
  gap4_ausente_w="$(cygpath -w "$tmp/gap4-nunca-existe")"
else
  gap4_ausente_w="$tmp/gap4-nunca-existe"
fi
out="$(con_lib "
  \$script:RaicesNoObservadas = @()
  \$r = Resolve-AuditRoots -Roots @('$gap4_ausente_w') -PrimaryPath '$gap4_ausente_w' -RutasExtraEsDefault \$false
  Write-CleanResult 'prueba gap 4'
")"
printf '%s' "$out" | grep -qi 'OK (ALCANCE ACOTADO)' \
  || malo "Resolve-AuditRoots con una raiz ausente no dispara el veredicto acotado: $out"
printf '%s' "$out" | grep -qF "$gap4_ausente_w" \
  || malo "el veredicto no nombra la raiz ausente que Resolve-AuditRoots proceso de verdad: $out"

# Punto 7 del reviewer (segundo ciclo, 16.12): `GetFullPath` LANZA con
# comodines (`*`, `?`), `|`, chars de control o vacio, y la excepcion escapaba
# del `Where-Object` y mataba el proceso con exit 1 (el codigo de "hay
# hallazgo") -- la misma falla dura del gap 5, por la puerta de al lado;
# alcanzable con `-RutasExtra ...\skills\*` -Fix. El try/catch devuelve $false
# (fail-closed: lo que no se normaliza no cuelga => no se muta). La raiz MALA
# va PRIMERO en la lista a proposito: si el catch se quitara, la excepcion
# revienta antes de evaluar la raiz buena y el caso se pone rojo solo.
caso "Test-PathUnderAnyRoot con una raiz con comodin devuelve False sin excepcion (fail-closed)"
out="$(con_lib "
  \$r1 = Test-PathUnderAnyRoot -ChildPath 'C:\\perfil\\.claude\\skills\\x.txt' -Roots @('C:\\perfil\\.claude\\skills\\*', 'C:\\otro')
  \$r2 = Test-PathUnderAnyRoot -ChildPath 'C:\\perfil\\.claude\\skills\\x.txt' -Roots @('C:\\perfil\\.claude\\skills\\*', 'C:\\perfil\\.claude\\skills')
  Write-Output \"R1=\$r1 R2=\$r2\"
")"
printf '%s' "$out" | grep -qF 'R1=False' \
  || malo "una raiz con comodin debio dar False (fail-closed), no reventar ni True: $out"
printf '%s' "$out" | grep -qF 'R2=True' \
  || malo "la raiz BUENA despues de la mala debio seguir evaluandose (True): $out"

# ------------------------------------------------ 4) la auditoria no escribe
caso "la auditoria sin -Fix sobre un arbol de prueba no toca nada"
mkdir -p "$tmp/arbol/sub"
printf 'x\n' > "$tmp/arbol/sub/archivo.txt"
if command -v cygpath >/dev/null 2>&1; then
  arbol_win="$(cygpath -w "$tmp/arbol")"
else
  arbol_win="$tmp/arbol"
fi
antes="$(cd "$tmp/arbol" && find . -type f | sort | xargs cksum 2>/dev/null)"
"$pwsh_bin" -NoProfile -ExecutionPolicy Bypass -File "$tool_win" -Path "$arbol_win" >/dev/null 2>&1
despues="$(cd "$tmp/arbol" && find . -type f | sort | xargs cksum 2>/dev/null)"
[ "$antes" = "$despues" ] || malo "la auditoria modifico el arbol"

# ============================================ Task 16.5 — -RutasExtra en el ACL
# Premisa corregida en 16.12 (coherente con el bloque de mas abajo): el
# recetario (`hooks/recetas`) vive DENTRO del arbol de hooks y la recursion ya
# lo cubre; lo que vive fuera es `~/.claude/skills/*`. -RutasExtra suma raices
# al arbol auditado; una que aun no existe se reporta `ausente` y NO es error.
caso "RutasExtra: rutas aceptadas; la ausente se reporta ausente, no error"
mkdir -p "$tmp/acl-extra-existe"
printf 'x\n' > "$tmp/acl-extra-existe/archivo.txt"
if command -v cygpath >/dev/null 2>&1; then
  arbol_w="$(cygpath -w "$tmp/arbol")"
  extra_w="$(cygpath -w "$tmp/acl-extra-existe")"
  ausente_w="$(cygpath -w "$tmp/acl-extra-no-existe")"
else
  arbol_w="$tmp/arbol"
  extra_w="$tmp/acl-extra-existe"
  ausente_w="$tmp/acl-extra-no-existe"
fi
"$pwsh_bin" -NoProfile -ExecutionPolicy Bypass -Command "& '$tool_win' -Path '$arbol_w' -RutasExtra '$extra_w','$ausente_w'" > "$tmp/acl-out.txt" 2>&1
rc=$?
# El arbol bajo %TEMP% hereda ACE con escritura (CodexSandboxUsers / SID huerfano),
# asi que la auditoria puede salir 1 por esos hallazgos. Lo que NO debe pasar es
# que la ruta extra AUSENTE sea un error (exit 2): se reporta y se salta.
[ "$rc" -ne 2 ] || malo "una ruta extra ausente NO debe ser un error (exit 2): $(cat "$tmp/acl-out.txt")"
grep -qi 'ausente' "$tmp/acl-out.txt" || malo "no reporta la ruta extra ausente: $(cat "$tmp/acl-out.txt")"
grep -qF "$ausente_w" "$tmp/acl-out.txt" || malo "no nombra la ruta ausente: $(cat "$tmp/acl-out.txt")"
grep -qi 'no se audita' "$tmp/acl-out.txt" || malo "no dice que la ruta ausente no se audita: $(cat "$tmp/acl-out.txt")"
# cross-review grok r4 #7: el caso solo aseveraba sobre la ruta AUSENTE. Si
# `-RutasExtra` se aceptara y se IGNORARA la ruta que SI existe — que es la
# mitad util del parametro — el caso pasaba igual.
#
# Se mide por EFECTO, no por texto: la salida NO nombra las rutas extra (se
# comprobo corriendo el ps1 a mano), asi que grepear el path daba un rojo falso.
# Lo observable es el conteo de objetos: auditar el arbol MAS la ruta extra
# tiene que cubrir mas objetos que auditar el arbol solo.
"$pwsh_bin" -NoProfile -ExecutionPolicy Bypass -Command "& '$tool_win' -Path '$arbol_w'" > "$tmp/acl-solo.txt" 2>&1
n_solo="$(grep -oE 'sobre [0-9]+ objeto' "$tmp/acl-solo.txt" | grep -oE '[0-9]+' | head -1)"
n_extra="$(grep -oE 'sobre [0-9]+ objeto' "$tmp/acl-out.txt" | grep -oE '[0-9]+' | head -1)"
sin_conteo=0
if [ -z "$n_solo" ] || [ -z "$n_extra" ]; then
  # Sin hallazgos no hay conteo que comparar. CodeRabbit (PR #108) atrapo que la
  # primera version solo imprimia el aviso y dejaba `fail` en 0: el archivo podia
  # cerrar con "test_hook_acl: OK" sin haber comprobado -RutasExtra ni una vez —
  # el mismo pase en vacio que esta ronda existe para cerrar. Un unknown NO es un
  # OK: se marca y el archivo sale 3, que tests/run.sh cuenta aparte.
  printf '    unknown: la auditoria no reporto conteo de objetos en este host; no se pudo medir si la ruta extra se audita\n' >&2
  sin_conteo=1
else
  [ "$n_extra" -gt "$n_solo" ] \
    || malo "la ruta extra EXISTENTE no se audito: mismo conteo con y sin -RutasExtra ($n_solo vs $n_extra)"
fi

# ============================================ Task 16.12 — default de -RutasExtra
# El recetario (hooks/recetas) YA vive DENTRO del arbol de hooks: lo recorre
# `Get-HookAclTarget` por defecto. Lo que de verdad queda fuera es
# `~/.claude/skills/*`. Estos casos miden que auditar SIN pasar ningun flag
# cubra igual las skills (derivadas del `-Path` recibido), que un
# `-RutasExtra` explicito siga mandando (de verdad, no solo por el mensaje),
# que una skills-root ausente no vuelva rojo al guardrail, y que el default
# SOLO se derive cuando `-Path` tiene la forma exacta `<perfil>\.claude\hooks`
# -- ciclo de revision 16.12: las fixtures viejas usaban `$tmp/perfil/hooks`
# (el padre de `-Path` era `perfil`, NO `.claude`), asi que nunca ejercitaban
# la derivacion real y no podian atrapar los hallazgos 3 ni 5 (excepcion no
# controlada con formas de `-Path` que no calzan el patron).
mkdir -p "$tmp/perfil/.claude/hooks/sub"
touch "$tmp/perfil/.claude/hooks/sub/archivo.txt"
mkdir -p "$tmp/perfil/.claude/skills/una-skill"
touch "$tmp/perfil/.claude/skills/una-skill/archivo.txt"
# Hallazgo 6d: se siembra un ACE con un principal SIEMPRE resoluble y ajeno a
# la keep-list (`Everyone`) en cada fixture de este bloque. Antes, sin ningun
# ACE de mas en la maquina que corre la suite, el bloque degradaba a
# "unknown" SIN ninguna asercion real (ni siquiera afectaba el exit code).
# Sembrando el ACE, el conteo de objetos existe SIEMPRE y las comparaciones
# de abajo son duras, no condicionales.
icacls "$tmp/perfil/.claude/hooks" //grant "Everyone:(OI)(CI)M" >/dev/null 2>&1
icacls "$tmp/perfil/.claude/skills" //grant "Everyone:(OI)(CI)M" >/dev/null 2>&1
if command -v cygpath >/dev/null 2>&1; then
  perfil_hooks_w="$(cygpath -w "$tmp/perfil/.claude/hooks")"
  perfil_skills_w="$(cygpath -w "$tmp/perfil/.claude/skills")"
else
  perfil_hooks_w="$tmp/perfil/.claude/hooks"
  perfil_skills_w="$tmp/perfil/.claude/skills"
fi

caso "sin pasar -RutasExtra, el default cubre las skills del perfil (mas objetos que solo -Path)"
"$pwsh_bin" -NoProfile -ExecutionPolicy Bypass -File "$tool_win" -Path "$perfil_hooks_w" > "$tmp/acl-default.txt" 2>&1
rc_default=$?
"$pwsh_bin" -NoProfile -ExecutionPolicy Bypass -File "$tool_win" -Path "$perfil_hooks_w" -RutasExtra '' > "$tmp/acl-solo-path.txt" 2>&1
# Contrato de exit codes (codex xrev #4): con el ACE sembrado HAY hallazgo, asi
# que el exit tiene que ser exactamente 1 -- una regresion que reporte hallazgos
# y salga 0 pasaba toda la suite (ningun caso fijaba el 1 exacto).
[ "$rc_default" -eq 1 ] \
  || malo "con hallazgo sembrado el exit debe ser 1 (contrato), fue $rc_default"
grep -qi 'RutasExtra por defecto' "$tmp/acl-default.txt" \
  || malo "sin flags no se anuncia el default de RutasExtra: $(cat "$tmp/acl-default.txt")"
# La RUTA derivada, no solo la palabra del mensaje fijo (codex xrev #3): si la
# derivacion devolviera $Path (duplicando la auditoria), el conteo tambien
# subia y el grep de 'skills' coincidia con la etiqueta del anuncio -- el caso
# pasaba sin auditar skills. La ruta literal ancla el hecho.
grep -qF "$perfil_skills_w" "$tmp/acl-default.txt" \
  || malo "el default no nombra la RUTA derivada real ($perfil_skills_w): $(cat "$tmp/acl-default.txt")"
grep -qi 'RutasExtra por defecto' "$tmp/acl-solo-path.txt" \
  && malo "-RutasExtra '' explicito (opt-out documentado, forma -File) no debe activar el default: $(cat "$tmp/acl-solo-path.txt")"
n_default="$(grep -oE 'sobre [0-9]+ objeto' "$tmp/acl-default.txt" | grep -oE '[0-9]+' | head -1)"
n_solo_path="$(grep -oE 'sobre [0-9]+ objeto' "$tmp/acl-solo-path.txt" | grep -oE '[0-9]+' | head -1)"
[ -n "$n_default" ] \
  || malo "el ACE sembrado deberia garantizar conteo con el default (nunca 'unknown'): $(cat "$tmp/acl-default.txt")"
[ -n "$n_solo_path" ] \
  || malo "el ACE sembrado deberia garantizar conteo con -Path solo (nunca 'unknown'): $(cat "$tmp/acl-solo-path.txt")"
if [ -n "$n_default" ] && [ -n "$n_solo_path" ]; then
  [ "$n_default" -gt "$n_solo_path" ] \
    || malo "el default de RutasExtra no cubrio mas objetos que -Path solo (skills no auditadas): $n_default vs $n_solo_path"
fi

# ------------------------------------- Punto 5 (filtrar entradas vacias)
caso "-RutasExtra \$null explicito no revienta el bucle de raices (opt-out valido)"
out_rutasnull="$("$pwsh_bin" -NoProfile -ExecutionPolicy Bypass -Command "& '$tool_win' -Path '$perfil_hooks_w' -RutasExtra "'$null' 2>&1)"
rc_rutasnull=$?
[ "$rc_rutasnull" -ne 2 ] || malo "-RutasExtra \$null no debe reventar (exit 2): $out_rutasnull"
printf '%s' "$out_rutasnull" | grep -qi 'Exception\|CategoryInfo\|FullyQualifiedErrorId' \
  && malo "-RutasExtra \$null termino en una excepcion de PowerShell no controlada: $out_rutasnull"
printf '%s' "$out_rutasnull" | grep -qi 'RutasExtra por defecto' \
  && malo "-RutasExtra \$null explicito no debe activar el default (tiene que reemplazarlo): $out_rutasnull"

caso "un -RutasExtra explicito sigue mandando: la skills-root default queda AUSENTE de -Detailed, la explicita SI aparece"
mkdir -p "$tmp/otra-extra"
touch "$tmp/otra-extra/archivo.txt"
icacls "$tmp/otra-extra" //grant "Everyone:(OI)(CI)M" >/dev/null 2>&1
if command -v cygpath >/dev/null 2>&1; then
  otra_w="$(cygpath -w "$tmp/otra-extra")"
else
  otra_w="$tmp/otra-extra"
fi
"$pwsh_bin" -NoProfile -ExecutionPolicy Bypass -File "$tool_win" -Path "$perfil_hooks_w" -RutasExtra "$otra_w" -Detailed > "$tmp/acl-explicit.txt" 2>&1
grep -qi 'RutasExtra por defecto' "$tmp/acl-explicit.txt" \
  && malo "un -RutasExtra explicito no debe disparar el mensaje de default: $(cat "$tmp/acl-explicit.txt")"
# El caso anterior (solo el mensaje) era VACUO: una implementacion que SUME
# la skills-root derivada a la lista explicita, en vez de reemplazarla,
# pasaba igual -- el mensaje de default solo se imprime en ESA rama, nunca
# en la del -RutasExtra explicito, sin importar que la raiz termine sumada
# o no. La asercion real es sobre la salida: la skills-root por defecto
# tiene que estar AUSENTE de -Detailed (no se audito), y la raiz explicita
# SI tiene que aparecer (se audito).
grep -qF "$perfil_skills_w" "$tmp/acl-explicit.txt" \
  && malo "un -RutasExtra explicito NO debe sumar la skills-root por defecto (tiene que reemplazarla): $(cat "$tmp/acl-explicit.txt")"
grep -qF "$otra_w" "$tmp/acl-explicit.txt" \
  || malo "la raiz explicita deberia auditarse y no aparece en -Detailed: $(cat "$tmp/acl-explicit.txt")"

caso "una skills-root ausente no vuelve rojo al guardrail (se reporta ausente, no error)"
mkdir -p "$tmp/perfil-sin-skills/.claude/hooks"
touch "$tmp/perfil-sin-skills/.claude/hooks/archivo.txt"
if command -v cygpath >/dev/null 2>&1; then
  sinskills_w="$(cygpath -w "$tmp/perfil-sin-skills/.claude/hooks")"
else
  sinskills_w="$tmp/perfil-sin-skills/.claude/hooks"
fi
"$pwsh_bin" -NoProfile -ExecutionPolicy Bypass -File "$tool_win" -Path "$sinskills_w" > "$tmp/acl-sinskills.txt" 2>&1
rc_sinskills=$?
[ "$rc_sinskills" -ne 2 ] || malo "una skills-root inexistente no debe ser un error (exit 2): $(cat "$tmp/acl-sinskills.txt")"
grep -qi 'ausente' "$tmp/acl-sinskills.txt" \
  || malo "la skills-root ausente por defecto no se reporta como ausente: $(cat "$tmp/acl-sinskills.txt")"

caso "-Path apuntando directo a <perfil>/.claude no deriva ningun default (nada FUERA de .claude)"
mkdir -p "$tmp/perfilB/.claude/hooks"
touch "$tmp/perfilB/.claude/hooks/archivo.txt"
mkdir -p "$tmp/perfilB/skills"
touch "$tmp/perfilB/skills/decoy.txt"
icacls "$tmp/perfilB/.claude" //grant "Everyone:(OI)(CI)M" >/dev/null 2>&1
if command -v cygpath >/dev/null 2>&1; then
  perfilB_claude_w="$(cygpath -w "$tmp/perfilB/.claude")"
  perfilB_skills_w="$(cygpath -w "$tmp/perfilB/skills")"
else
  perfilB_claude_w="$tmp/perfilB/.claude"
  perfilB_skills_w="$tmp/perfilB/skills"
fi
"$pwsh_bin" -NoProfile -ExecutionPolicy Bypass -File "$tool_win" -Path "$perfilB_claude_w" -Detailed > "$tmp/acl-pathclaude.txt" 2>&1
rc_pathclaude=$?
[ "$rc_pathclaude" -ne 2 ] || malo "-Path=<perfil>/.claude no debe reventar (exit 2): $(cat "$tmp/acl-pathclaude.txt")"
grep -qi 'RutasExtra por defecto' "$tmp/acl-pathclaude.txt" \
  && malo "-Path=<perfil>/.claude (hoja .claude, no hooks) no debe disparar ningun default: $(cat "$tmp/acl-pathclaude.txt")"
grep -qi 'sin rutasextra por defecto\|cobertura acotada' "$tmp/acl-pathclaude.txt" \
  || malo "-Path=<perfil>/.claude no avisa que la cobertura queda acotada a -Path: $(cat "$tmp/acl-pathclaude.txt")"
grep -qF "$perfilB_skills_w" "$tmp/acl-pathclaude.txt" \
  && malo "se audito una carpeta FUERA de .claude sin que nadie la pidiera: $(cat "$tmp/acl-pathclaude.txt")"

caso "-Path relativo no revienta con una excepcion no controlada (falla suave)"
mkdir -p "$tmp/perfilC/.claude/hooks"
touch "$tmp/perfilC/.claude/hooks/archivo.txt"
icacls "$tmp/perfilC/.claude/hooks" //grant "Everyone:(OI)(CI)M" >/dev/null 2>&1
if command -v cygpath >/dev/null 2>&1; then
  perfilC_claude_w="$(cygpath -w "$tmp/perfilC/.claude")"
else
  perfilC_claude_w="$tmp/perfilC/.claude"
fi
out_relpath="$("$pwsh_bin" -NoProfile -ExecutionPolicy Bypass -Command "Set-Location '$perfilC_claude_w'; & '$tool_win' -Path 'hooks'" 2>&1)"
rc_relpath=$?
[ "$rc_relpath" -ne 2 ] || malo "-Path relativo 'hooks' no debe reventar (exit 2): $out_relpath"
printf '%s' "$out_relpath" | grep -qi 'Exception\|CategoryInfo\|FullyQualifiedErrorId' \
  && malo "-Path relativo 'hooks' termino en una excepcion de PowerShell no controlada, no en la falla suave declarada: $out_relpath"
printf '%s' "$out_relpath" | grep -qi 'sin rutasextra por defecto\|cobertura acotada' \
  || malo "-Path relativo no avisa que la cobertura queda acotada a -Path: $out_relpath"

# ------------------------------- Gap 5 (segundo ciclo, 16.12): TOCTOU en Test-ReparsePoint
# El defecto: entre el `Test-Path` del llamador y el `Get-Item -LiteralPath` de
# `Test-ReparsePoint` hay una ventana (borrado, acceso denegado). Con
# `$ErrorActionPreference = 'Stop'` a nivel script, un error terminante en esa
# ventana mataba el proceso entero con una excepcion cruda -- la misma falla
# dura que el punto 1 del ciclo anterior ya habia cerrado para el resto del
# script. Se prueba la funcion DIRECTO (modo biblioteca): sobre una ruta
# inexistente, `Get-Item` lanza `ItemNotFoundException`; `Test-ReparsePoint`
# tiene que atraparla y devolver `$null` (no pudo determinarse), nunca dejar
# que la excepcion se propague sin control.
caso "Test-ReparsePoint no revienta con una excepcion cruda; devuelve null si no pudo determinar"
if command -v cygpath >/dev/null 2>&1; then
  gap5_ausente_w="$(cygpath -w "$tmp/gap5-jamas-existio")"
else
  gap5_ausente_w="$tmp/gap5-jamas-existio"
fi
out="$(con_lib "
  \$r = Test-ReparsePoint -TargetPath '$gap5_ausente_w'
  if (\$null -eq \$r) { Write-Output 'RESULTADO:NULL' } else { Write-Output ('RESULTADO:' + [string]\$r) }
")"
printf '%s' "$out" | grep -qi 'Exception\|CategoryInfo\|FullyQualifiedErrorId' \
  && malo "Test-ReparsePoint dejo escapar una excepcion no controlada en vez de devolver null: $out"
printf '%s' "$out" | grep -q 'RESULTADO:NULL' \
  || malo "Test-ReparsePoint sobre una ruta que no existe deberia devolver null (no pudo determinarse): $out"

# ------------------------------------- Punto 2 (guard de reparse point)
caso "una skills-root derivada que es reparse point (junction/symlink) NO se recorre ni se corrige"
mkdir -p "$tmp/perfilD/.claude/hooks"
touch "$tmp/perfilD/.claude/hooks/archivo.txt"
icacls "$tmp/perfilD/.claude/hooks" //grant "Everyone:(OI)(CI)M" >/dev/null 2>&1
mkdir -p "$tmp/perfilD-target"
touch "$tmp/perfilD-target/afuera.txt"
# Gap 3 (segundo ciclo, 16.12): `grep -qF "$perfilD_target_w"` NUNCA podia
# fallar -- `Get-ChildItem -Recurse` sobre un junction (mismo volumen) resuelve
# el bit ReparsePoint de forma transparente y reporta `FullName` bajo la ruta
# del JUNCTION, JAMAS bajo la ruta fisica del destino -- asi que ESA cadena no
# aparece en la salida sin importar si el guard funciona (verificado con el
# mutante de abajo: buscar la ruta del destino tampoco detecta la mutacion,
# el mismo punto ciego que describe el gap). El caso descansaba solo en el
# grep del AVISO de texto; una mutacion que imprima el aviso y aun asi haga
# `$kept += $raiz` (le falta el `continue`) pasaba en verde. Se sembra un ACE
# PROPIO en el archivo del otro lado del junction para que, si se traversa,
# deje un HALLAZGO real bajo la ruta DEL JUNCTION (`$perfilD_skills_w\afuera.txt`,
# no `$perfilD_target_w\afuera.txt`) -- y se asevera sobre el HECHO: ni ese
# hallazgo aparece en el detalle, ni "Arbol auditado:" lista la skills-root.
icacls "$tmp/perfilD-target/afuera.txt" //grant "Everyone:(M)" >/dev/null 2>&1
if command -v cygpath >/dev/null 2>&1; then
  perfilD_hooks_w="$(cygpath -w "$tmp/perfilD/.claude/hooks")"
  perfilD_skills_w="$(cygpath -w "$tmp/perfilD/.claude/skills")"
  perfilD_target_w="$(cygpath -w "$tmp/perfilD-target")"
else
  perfilD_hooks_w="$tmp/perfilD/.claude/hooks"
  perfilD_skills_w="$tmp/perfilD/.claude/skills"
  perfilD_target_w="$tmp/perfilD-target"
fi
perfilD_afuera_via_junction_w="$perfilD_skills_w\\afuera.txt"
"$pwsh_bin" -NoProfile -Command "cmd /c \"mklink /J \`\"$perfilD_skills_w\`\" \`\"$perfilD_target_w\`\"\"" >/dev/null 2>&1
"$pwsh_bin" -NoProfile -ExecutionPolicy Bypass -File "$tool_win" -Path "$perfilD_hooks_w" -Detailed > "$tmp/acl-reparse.txt" 2>&1
rc_reparse=$?
[ "$rc_reparse" -ne 2 ] || malo "una skills-root reparse point no debe reventar (exit 2): $(cat "$tmp/acl-reparse.txt")"
grep -qi 'reparse point' "$tmp/acl-reparse.txt" \
  || malo "no advierte que la skills-root derivada es un reparse point: $(cat "$tmp/acl-reparse.txt")"
grep -qF "$perfilD_afuera_via_junction_w" "$tmp/acl-reparse.txt" \
  && malo "atraveso el junction y reporto el hallazgo sembrado del otro lado (deberia saltarlo): $(cat "$tmp/acl-reparse.txt")"
grep -F "Arbol auditado:" "$tmp/acl-reparse.txt" | grep -qF "$perfilD_skills_w" \
  && malo "'Arbol auditado:' lista la skills-root reparse point (deberia excluirla): $(cat "$tmp/acl-reparse.txt")"

# ------------------------------------- Punto 3 (radio de -Fix sin flags)
caso "-Fix sin flags corrige -Path pero NO la skills-root derivada por defecto"
mkdir -p "$tmp/perfilFix/.claude/hooks"
touch "$tmp/perfilFix/.claude/hooks/archivo.txt"
mkdir -p "$tmp/perfilFix/.claude/skills"
touch "$tmp/perfilFix/.claude/skills/archivo.txt"
# Everyone: principal SIEMPRE resoluble y ajeno a la keep-list, para que la
# reparacion tenga algo deterministico que degradar en AMBAS raices.
icacls "$tmp/perfilFix/.claude/hooks" //grant "Everyone:(OI)(CI)M" >/dev/null 2>&1
icacls "$tmp/perfilFix/.claude/skills" //grant "Everyone:(OI)(CI)M" >/dev/null 2>&1
# La siembra se VERIFICA antes de correr -Fix (codex xrev #5): si el grant de
# hooks fallara, "Everyone ya no esta" seria verdad sin que la reparacion
# hiciera nada -- el caso aceptaba un no-op como correccion.
icacls "$tmp/perfilFix/.claude/hooks" 2>&1 | grep -qi 'Everyone:.*(M)' \
  || malo "precondicion: el grant de Everyone sobre hooks no tomo; el caso no mide la reparacion"
icacls "$tmp/perfilFix/.claude/skills" 2>&1 | grep -qi 'Everyone:.*(M)' \
  || malo "precondicion: el grant de Everyone sobre skills no tomo; el caso no mide el radio"
if command -v cygpath >/dev/null 2>&1; then
  perfilFix_hooks_w="$(cygpath -w "$tmp/perfilFix/.claude/hooks")"
  perfilFix_backup_w="$(cygpath -w "$tmp/perfilFix-backup")"
else
  perfilFix_hooks_w="$tmp/perfilFix/.claude/hooks"
  perfilFix_backup_w="$tmp/perfilFix-backup"
fi
"$pwsh_bin" -NoProfile -ExecutionPolicy Bypass -File "$tool_win" -Path "$perfilFix_hooks_w" \
  -BackupRoot "$perfilFix_backup_w" -Fix > "$tmp/acl-fix-default.txt" 2>&1
grep -qi 'RutasExtra por defecto NO se corrige' "$tmp/acl-fix-default.txt" \
  || malo "no avisa que la skills-root por defecto no se corrige: $(cat "$tmp/acl-fix-default.txt")"
hooks_despues="$(icacls "$tmp/perfilFix/.claude/hooks" 2>&1)"
skills_despues="$(icacls "$tmp/perfilFix/.claude/skills" 2>&1)"
printf '%s' "$hooks_despues" | grep -qi 'Everyone:.*(M)' \
  && malo "-Path SI deberia haberse corregido (Everyone sigue con Modify): $hooks_despues"
printf '%s' "$skills_despues" | grep -qi 'Everyone:.*(M)' \
  || malo "la skills-root por defecto se corrigio SIN -RutasExtra explicito (radio destructivo de mas): $skills_despues"

# ------------------------------------- Gap 1 (segundo ciclo, 16.12)
# Reproduccion del reviewer: `Repair-HookAcl` (linea ~708) SI respeta el radio
# (nunca toca la skills-root derivada), pero `Repair-StaleInherited` corria
# sobre `$after`, calculado sobre `$raicesAuditadas` -- QUE INCLUYE la
# skills-root -- y `icacls /reset` es una mutacion. Un hijo de la skills-root
# con un ACE heredado obsoleto (llegado por `move`, mismo vector que el resto
# del script ya maneja) desaparecia con `-Fix` sin flags, y como no esta en
# `$aTocar`/el backup, `-Restore` no lo revertia. La asercion es sobre un HIJO
# de la skills-root, no sobre el directorio -- esa es la granularidad que
# atrapo el bug (medir el directorio da PASS con el hijo roto).
caso "Gap 1: -Fix sin flags NO muta el ACE heredado obsoleto de un archivo bajo la skills-root derivada"
mkdir -p "$tmp/gap1/.claude/hooks"
touch "$tmp/gap1/.claude/hooks/archivo.txt"
mkdir -p "$tmp/gap1/.claude/skills"
mkdir -p "$tmp/gap1/donor"
icacls "$tmp/gap1/.claude/hooks" //grant "Everyone:(OI)(CI)M" >/dev/null 2>&1
icacls "$tmp/gap1/donor" //grant "Everyone:(OI)(CI)M" >/dev/null 2>&1
touch "$tmp/gap1/donor/movido.txt"
mv "$tmp/gap1/donor/movido.txt" "$tmp/gap1/.claude/skills/movido.txt"
if command -v cygpath >/dev/null 2>&1; then
  gap1_hooks_w="$(cygpath -w "$tmp/gap1/.claude/hooks")"
  gap1_backup_w="$(cygpath -w "$tmp/gap1-backup")"
else
  gap1_hooks_w="$tmp/gap1/.claude/hooks"
  gap1_backup_w="$tmp/gap1-backup"
fi
movido_antes="$(icacls "$tmp/gap1/.claude/skills/movido.txt" 2>&1)"
printf '%s' "$movido_antes" | grep -qi 'Everyone:.*(M)' \
  || malo "la fixture no quedo con el ACE heredado obsoleto esperado antes de -Fix: $movido_antes"
"$pwsh_bin" -NoProfile -ExecutionPolicy Bypass -File "$tool_win" -Path "$gap1_hooks_w" \
  -BackupRoot "$gap1_backup_w" -Fix > "$tmp/acl-gap1.txt" 2>&1
movido_despues="$(icacls "$tmp/gap1/.claude/skills/movido.txt" 2>&1)"
printf '%s' "$movido_despues" | grep -qi 'Everyone:.*(M)' \
  || malo "GAP 1: -Fix sin flags borro el ACE de un HIJO de la skills-root derivada (mutacion fuera del radio declarado): antes=[$movido_antes] despues=[$movido_despues] salida=$(cat "$tmp/acl-gap1.txt")"
# El texto final tiene que distinguir politica declarada (raiz solo auditada,
# no es fallo de la correccion) de un fallo real dentro del radio de -Fix.
grep -qi 'POLITICA' "$tmp/acl-gap1.txt" \
  || malo "el mensaje final no distingue la politica declarada (raiz solo auditada) de un fallo de la correccion: $(cat "$tmp/acl-gap1.txt")"

if [ "$fail" -ne 0 ]; then
  echo "test_hook_acl: FAIL" >&2
  exit 1
fi
# Un unknown NO es un OK (contrato de datos del repo: not_observed != absent).
# exit 3 es el codigo que tests/run.sh cuenta aparte como "no se pudo verificar";
# un fallo real (arriba) sigue mandando sobre un unknown.
if [ "${sin_conteo:-0}" -ne 0 ]; then
  echo "test_hook_acl: unknown — no se pudo medir si -RutasExtra audita la ruta existente" >&2
  exit 3
fi
echo "test_hook_acl: OK"
