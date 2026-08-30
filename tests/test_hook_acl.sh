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
# El recetario y las skills viven FUERA del arbol de hooks
# (~/.claude/hooks/recetas, ~/.claude/skills/*). -RutasExtra los suma al arbol
# auditado; una ruta que aun no existe se reporta `ausente` y NO es un error.
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
