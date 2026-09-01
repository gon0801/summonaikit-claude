<#
.SYNOPSIS
  Audita y corrige las ACL del directorio de hooks de Claude Code (defecto A7).

.DESCRIPTION
  El hook `summonaikit-harness.sh` corre SIN sandbox en cada turno. Hoy hereda de
  `~/.claude` un permiso `Modify` para `CodexSandboxUsers` (identidad AISLADA) y
  para un SID huerfano sin resolver. Con eso, una identidad de sandbox puede
  reescribir el script que corre sin sandbox, o plantar
  `agents_seen=implementer,verifier,reviewer` en `hooks/state/` y anular el gate.

  Regla aplicada (independiente del idioma del SO y del nombre de la maquina):
  ningun principal fuera de la keep-list (usuario actual, duenio del directorio,
  SYSTEM, Administrators, CREATOR OWNER) puede tener derechos de ESCRITURA sobre
  el arbol de hooks.

    - principal resoluble  -> se baja a ReadAndExecute (no se le quita el leer).
    - SID no resoluble     -> se elimina el ACE entero (cuenta borrada, sin
                              consumidor legitimo, y su RID puede reciclarse).

  `-Fix` rompe la herencia en el directorio de hooks a proposito: el otorgamiento
  vive en `~/.claude`, y el instalador del sandbox de Codex puede volver a
  aplicarlo ahi. Con la herencia cortada, ese re-otorgamiento ya no se propaga
  hacia adentro de `hooks/`.

.PARAMETER Path
  Raiz del arbol de hooks. Por defecto `~/.claude/hooks`.

.PARAMETER Fix
  Sin este switch el script solo AUDITA (read-only) y sale 1 si hay hallazgos.
  Con el switch hace backup y luego corrige.

.PARAMETER BackupRoot
  Directorio donde se guarda el backup (SDDL por ruta + volcado `icacls`).

.PARAMETER OrphansOnly
  Acota la clase de hallazgo a SID no resolubles (cuentas borradas). No toca a
  ningun principal vivo y no corta la herencia. Es el modo para rutas donde
  alguien tiene escritura LEGITIMA que no se le puede quitar: en `%TEMP%` el
  sandbox de Codex si escribe, asi que ahi solo se barren los ACE muertos.
  Los ACE heredados no se remueven aca — se limpian corriendo la herramienta
  sobre el ancestro que los tiene explicitos, y la propagacion baja sola.

.PARAMETER RootOnly
  No recorre descendientes. Obligatorio en `%TEMP%` / `AppData`, que tienen
  cientos de miles de objetos volatiles. Lo que contamina a un archivo NUEVO es
  la ACL efectiva de la carpeta, no la de los temporales ya existentes.
  Con este switch el resultado limpio se reporta como ALCANCE ACOTADO: los
  descendientes quedan `unknown`, nunca "limpios" (Core Rule 2).

.PARAMETER Restore
  Ruta a un `acl-backup.json` generado por una corrida previa con `-Fix`.
  Devuelve las ACL exactamente al estado guardado.

.PARAMETER RutasExtra
  Raices adicionales a auditar junto con `-Path`. Si NO se pasa este flag, Y
  `-Path` tiene la forma exacta `<perfil>\.claude\hooks` (hoja `hooks`, cuyo
  padre tiene hoja `.claude`), deriva por defecto `<perfil>\.claude\skills`:
  esa carpeta vive FUERA del arbol de hooks y por eso nunca la alcanza la
  recursion por defecto. Si `-Path` NO tiene esa forma (perfil a secas,
  `%TEMP%`, `AppData`, ruta relativa, raiz de unidad, UNC que no calce el
  patron), NO hay default: se avisa que la cobertura queda acotada a `-Path`
  y se sigue -- nunca una excepcion. El recetario (`hooks/recetas`) NO
  necesita entrar aca -- ya es descendiente de `-Path` y ya se recorre solo.
  Pasar `-RutasExtra` a mano REEMPLAZA el default (no se suma); para auditar
  unicamente `-Path`, pasar `-RutasExtra ''` (funciona igual con `-File`; con
  esa forma `-RutasExtra @()` llega como la cadena literal `@()`, no como
  arreglo vacio).
  Una ruta extra que aun no existe se reporta `ausente` y se salta, nunca es
  un hallazgo. Si la raiz derivada por defecto resulta ser un reparse point
  (junction/symlink) tampoco se recorre -- se reporta fuerte y se salta.
  La raiz derivada por DEFECTO solo se AUDITA: `-Fix` nunca la corrige a
  menos que se pase `-RutasExtra` explicito (asi el radio destructivo de
  `-Fix` sin flags queda identico al de antes de este default). El TOCTOU
  entre comprobar una ruta extra EXPLICITA y corregirla queda diferido y
  declarado, con el mismo criterio que el limite TOCTOU de `Plans.md:47`
  (Task 16.5, `-L` vs borrado) y el residual de backup que declara
  `docs/plans-archivo.md:28` (Task 0.5): quien lo explota ya tiene escritura
  en el arbol auditado.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\hook-acl.ps1
  Audita. Exit 0 = limpio, exit 1 = hay escritura de mas.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\hook-acl.ps1 -Fix
  Backup + correccion + re-auditoria.

.NOTES
  Este script es un INSTALADOR/verificador, no el hook. La regla de fail-open del
  spec (Core Rule 1) aplica al hook; aca un hallazgo tiene que salir distinto de
  cero o no sirve de control.
#>
[CmdletBinding()]
param(
    [string]$Path = (Join-Path $env:USERPROFILE '.claude\hooks'),
    [switch]$Fix,
    [string]$BackupRoot = (Join-Path $env:USERPROFILE '.claude\hooks-acl-backup'),
    [string]$Restore,
    [switch]$Detailed,
    [switch]$OrphansOnly,
    [switch]$RootOnly,
    [string[]]$RutasExtra = @()
)

$ErrorActionPreference = 'Stop'

# Raices extra que se decidio NO observar (ausentes o reparse point saltado),
# con su motivo. Alimenta `Get-ScopeCaveat` (punto 4) y la linea "Arbol
# auditado". Se inicializa siempre, aunque el modo biblioteca no ejecute el
# flujo principal, para que un test que llame a `Get-ScopeCaveat` directo no
# pise una variable inexistente.
$script:RaicesNoObservadas = @()

# Derechos que permiten alterar el script o plantar estado. Cualquiera de estos
# bits en un principal fuera de la keep-list es un hallazgo.
$script:WriteMask =
    [int][System.Security.AccessControl.FileSystemRights]::WriteData -bor
    [int][System.Security.AccessControl.FileSystemRights]::AppendData -bor
    [int][System.Security.AccessControl.FileSystemRights]::WriteAttributes -bor
    [int][System.Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
    [int][System.Security.AccessControl.FileSystemRights]::Delete -bor
    [int][System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
    [int][System.Security.AccessControl.FileSystemRights]::ChangePermissions -bor
    [int][System.Security.AccessControl.FileSystemRights]::TakeOwnership

function ConvertTo-SidValue {
    param($IdentityReference)
    try {
        return $IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
    } catch {
        return $null
    }
}

# TRES estados, no dos (Task 0.5). Antes cualquier excepcion devolvia $false, y
# ese $false BORRA el ACE: un fallo transitorio de resolucion --un controlador de
# dominio que no contesta-- alcanzaba para quitarle el acceso a una cuenta VIVA.
# Es la Core Rule 2 aplicada donde mas caro sale, porque este es el unico codigo
# destructivo del repo.
#
#   $true   la cuenta existe
#   $false  se miro y NO existe (IdentityNotMappedException): cuenta borrada
#   $null   no se pudo determinar. No es lo mismo que no existir, y no se toca.
function Test-SidResolvable {
    param([string]$SidValue)
    try {
        $sid = New-Object System.Security.Principal.SecurityIdentifier($SidValue)
        [void]$sid.Translate([System.Security.Principal.NTAccount])
        return $true
    } catch [System.Security.Principal.IdentityNotMappedException] {
        return $false
    } catch {
        # Incluye el SID mal formado: si no se pudo ni construir, tampoco se
        # observo que la cuenta no exista.
        return $null
    }
}

# La politica de reparacion, en UN solo lugar. Antes vivia duplicada: la raiz
# degradaba a los principales vivos y los descendientes los eliminaban enteros
# (Task 0.5). Dos copias de una decision son dos oportunidades de que diverjan,
# y divergieron.
function Get-AclRepairAction {
    param($Finding)
    if ($Finding.Resolvable -eq $true)  { return 'degradar' }
    if ($Finding.Resolvable -eq $false) { return 'eliminar' }
    return 'no-tocar'
}

# El filtro que decide QUE hallazgos entran a la correccion, tambien en un solo
# lugar: `-OrphansOnly` acotaba la raiz pero NO los descendientes, asi que
# `-OrphansOnly -Fix` sin `-RootOnly` borraba ACE explicitos de cuentas vivas.
#
# Lo heredado se excluye siempre: no se puede remover de un objeto sin romperle
# la herencia. Se limpia corrigiendo el ancestro que lo tiene explicito.
function Select-RepairableFinding {
    param([object[]]$Findings, [switch]$OrphansOnlyMode, [switch]$IncludeInherited)
    $sel = @($Findings | Where-Object { (Get-AclRepairAction -Finding $_) -ne 'no-tocar' })
    if (-not $IncludeInherited) {
        $sel = @($sel | Where-Object { -not $_.IsInherited })
    }
    if ($OrphansOnlyMode) {
        $sel = @($sel | Where-Object { $_.Resolvable -eq $false })
    }
    return $sel
}

# `Get-Acl`/`Set-Acl` leen y persisten TODAS las secciones del descriptor, SACL
# incluida, y escribir la SACL exige `SeSecurityPrivilege` — que un usuario con
# Full Control igual no tiene. Medido: `Set-Acl` falla con PrivilegeNotHeldException
# aunque el cambio sea puramente de DACL. Pidiendo solo la seccion Access, el
# persist se limita a esa seccion y no toca auditoria ni duenio.
function Get-Dacl {
    param([string]$TargetPath)
    $item = Get-Item -LiteralPath $TargetPath -Force
    return $item.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
}

function Set-Dacl {
    param([string]$TargetPath, $Acl)
    $item = Get-Item -LiteralPath $TargetPath -Force
    $item.SetAccessControl($Acl)
}

function Get-KeepListSid {
    param([string]$RootPath)
    $keep = New-Object 'System.Collections.Generic.HashSet[string]'
    [void]$keep.Add('S-1-5-18')     # NT AUTHORITY\SYSTEM
    [void]$keep.Add('S-1-5-32-544') # BUILTIN\Administrators
    [void]$keep.Add('S-1-3-0')      # CREATOR OWNER
    [void]$keep.Add(([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value)

    # El duenio del arbol, aunque el script lo corra otra cuenta administrativa.
    try {
        $owner = (Get-Acl -Path $RootPath).GetOwner([System.Security.Principal.SecurityIdentifier])
        if ($owner) { [void]$keep.Add($owner.Value) }
    } catch {
        Write-Warning "No se pudo leer el duenio de $RootPath : $($_.Exception.Message)"
    }
    return $keep
}

function Get-DefaultSkillsRoot {
    param([string]$HooksPath)
    # `~/.claude/skills` es hermano de `~/.claude/hooks`, no descendiente: nunca
    # lo alcanza la recursion de `Get-HookAclTarget`. Se deriva del `$Path` que
    # de verdad se esta auditando (no de `$env:USERPROFILE` a ciegas) para que
    # auditar el perfil de OTRO usuario (via `-Path`) traiga las skills de ESE
    # perfil, no las del que corre el script.
    #
    # El default SOLO aplica cuando `-Path` tiene la forma exacta
    # `<perfil>\.claude\hooks`: hoja `hooks`, con padre de hoja `.claude`.
    # Cualquier otra forma -- `~/.claude` a secas, `%TEMP%`, `AppData`, una
    # relativa SIN esa forma (`hooks`, `.`), raiz de unidad (`C:\`), UNC que
    # no calce el patron -- devuelve `$null`: falla SUAVE, nunca excepcion.
    # OJO (grok xrev #5): una relativa que SI calza la forma
    # (`sub\.claude\hooks`) deriva su hermana relativa al cwd -- el criterio
    # es la FORMA, no que sea absoluta. Antes,
    # `Split-Path -Parent 'hooks'` da cadena vacia y `Join-Path ''` revienta
    # con `$ErrorActionPreference='Stop'` (exit 1), un codigo que el contrato
    # de este script reserva para "hay hallazgo", no para "me rompi".
    $hooksLeaf = Split-Path -Path $HooksPath -Leaf
    if ($hooksLeaf -ne 'hooks') { return $null }

    $claudeRoot = Split-Path -Path $HooksPath -Parent
    if ([string]::IsNullOrEmpty($claudeRoot)) { return $null }

    $claudeLeaf = Split-Path -Path $claudeRoot -Leaf
    if ($claudeLeaf -ne '.claude') { return $null }

    return Join-Path $claudeRoot 'skills'
}

# Guard del punto 2 (ciclo de revision 16.12): la raiz derivada por defecto
# nunca se eligio a mano, asi que si resulta ser un reparse point (junction o
# symlink) no se recorre ni se corrige -- solo se reporta. `.Attributes` no
# lanza excepcion sobre un item valido; el bit ReparsePoint es la misma señal
# que este repo ya usa en bash (`[ -L ]`, `tools/install-hook.sh` ~2123-2350),
# expresada con la API que existe en PowerShell.
#
# Gap 5 (segundo ciclo, 16.12): entre el `Test-Path` del llamador y este
# `Get-Item` hay una ventana TOCTOU (borrado, acceso denegado). Con
# `$ErrorActionPreference = 'Stop'` a nivel script, un error terminante aca
# mataba el proceso entero con una excepcion cruda -- exactamente la falla
# dura que el punto 1 (ciclo previo) ya habia cerrado para el resto del
# script. Tri-estado como `Test-SidResolvable`: `$true`/`$false` es haber
# podido mirar, `$null` es no haber podido mirar -- y ante `$null` el llamador
# trata la raiz como NO OBSERVADA (nunca como "limpia"), mismo criterio que un
# reparse point.
function Test-ReparsePoint {
    param([string]$TargetPath)
    try {
        $item = Get-Item -LiteralPath $TargetPath -Force
        return [bool]($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
    } catch {
        return $null
    }
}

# Filtra las raices (`$Path` + `$RutasExtra`) a las que de verdad hay que
# recorrer. Centraliza en UN lugar lo que antes se repetia tres veces
# (auditoria antes de -Fix, despues de -Fix, despues de Repair-StaleInherited)
# con criterios que podian divergir. Alimenta `$script:RaicesNoObservadas`
# para que el caveat de alcance (punto 4) y el reporte final nombren lo que
# no se miro.
#
# Devuelve un objeto { Kept; Messages }, NUNCA imprime con Write-Output desde
# adentro: en PowerShell cualquier `Write-Output` dentro de una funcion se
# suma al stream de SALIDA de esa funcion, asi que un `@(Resolve-AuditRoots
# ...)` mezclaria las rutas buenas con las lineas de aviso -- medido: el
# aviso "ADVERTENCIA: ... reparse point" terminaba adentro de
# `$raicesAuditadas` y `Get-HookAclTarget` lo tomaba como ruta, reventando
# con `Cannot find drive`. El caller imprime `.Messages` y usa `.Kept`.
#
# El guard de reparse point (punto 2) SOLO aplica a la raiz derivada por
# defecto -- `$RutasExtraEsDefault` -- porque esa raiz nunca la eligio el
# operador a mano; un `-RutasExtra` explicito es su responsabilidad y ya
# tenia esta disciplina fuera de alcance (ver nota TOCTOU del parametro).
function Resolve-AuditRoots {
    param(
        [string[]]$Roots,
        [string]$PrimaryPath,
        [bool]$RutasExtraEsDefault
    )
    $kept = @()
    $messages = @()
    foreach ($raiz in $Roots) {
        if (-not (Test-Path -LiteralPath $raiz)) {
            $messages += "Ruta extra ausente: $raiz (no se audita)"
            $script:RaicesNoObservadas += "$raiz (ausente)"
            continue
        }
        if ($RutasExtraEsDefault -and $raiz -ne $PrimaryPath) {
            $esReparse = Test-ReparsePoint -TargetPath $raiz
            if ($null -eq $esReparse) {
                # Gap 5: no se pudo determinar (TOCTOU / acceso denegado). Se trata
                # como no observada -- mismo camino que el reparse point -- nunca
                # como observada y limpia.
                $messages += "ADVERTENCIA: no se pudo determinar si $raiz es un reparse point; no se recorre ni se corrige."
                $script:RaicesNoObservadas += "$raiz (error al inspeccionar, no observada)"
                continue
            }
            if ($esReparse) {
                $messages += "ADVERTENCIA: $raiz es un reparse point (junction o symlink); no se recorre ni se corrige."
                $script:RaicesNoObservadas += "$raiz (reparse point, no observada)"
                continue
            }
        }
        $kept += $raiz
    }
    return [pscustomobject]@{ Kept = $kept; Messages = $messages }
}

# Gap 1 (segundo ciclo, 16.12): quien decide el radio de `-Fix` (linea ~692,
# `$rutasParaFix`) y quien filtra que mutar (`Repair-StaleInherited`, mas
# abajo) tienen que usar el MISMO criterio de pertenencia, no dos reglas que
# puedan divergir -- ese fue el defecto que ya cobro la Task 0.5 en este mismo
# archivo (politica de reparacion duplicada entre raiz e hijos). Comparacion
# por ruta NORMALIZADA: ni un `StartsWith` ingenuo (`C:\a\skills2` NO cuelga de
# `C:\a\skills`) ni sensible a mayusculas (NTFS no distingue).
function Test-PathUnderRoot {
    param([string]$ChildPath, [string]$RootPath)
    # `GetFullPath` LANZA con comodines (`*`, `?`), `|`, chars de control, vacio
    # o rutas >259 (medido en PS 5.1) -- y la excepcion escapa del `Where-Object`
    # y mata el proceso con exit 1, el codigo que el contrato reserva para "hay
    # hallazgo" (reviewer, segundo ciclo 16.12: la misma falla dura del gap 5,
    # por la puerta de al lado; alcanzable con `-RutasExtra ...\skills\*` -Fix).
    # Fail-closed: lo que no se puede normalizar NO cuelga de la raiz => no se
    # muta. Es la postura segura para un filtro que decide que ACL se tocan.
    try {
        $child = [System.IO.Path]::GetFullPath($ChildPath).TrimEnd('\', '/')
        $root  = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\', '/')
    } catch {
        return $false
    }
    if ($child.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $child.StartsWith("$root\", [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-PathUnderAnyRoot {
    param([string]$ChildPath, [string[]]$Roots)
    foreach ($r in $Roots) {
        if (Test-PathUnderRoot -ChildPath $ChildPath -RootPath $r) { return $true }
    }
    return $false
}

function Get-HookAclTarget {
    param([string]$RootPath)
    $targets = @($RootPath)
    # `%TEMP%` y `AppData` tienen cientos de miles de objetos volatiles: recorrerlos
    # es inviable y ademas inutil, porque lo que contamina a un archivo nuevo es la
    # ACL EFECTIVA de la carpeta, no la de los temporales que ya estaban ahi.
    if ($script:RootOnly) { return $targets }
    $targets += (Get-ChildItem -LiteralPath $RootPath -Recurse -Force |
                 Select-Object -ExpandProperty FullName)
    return $targets
}

function Get-AclFinding {
    param(
        [string]$TargetPath,
        [System.Collections.Generic.HashSet[string]]$KeepSids,
        $Acl
    )
    $findings = @()
    # Quien va a MUTAR el descriptor tiene que pasar el suyo: las reglas que se
    # remueven deben salir del mismo objeto que despues se persiste.
    if ($null -eq $Acl) { $Acl = Get-Dacl -TargetPath $TargetPath }
    foreach ($rule in $Acl.Access) {
        if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) { continue }

        $sid = ConvertTo-SidValue $rule.IdentityReference
        if ($null -eq $sid) { continue }
        if ($KeepSids.Contains($sid)) { continue }
        if (([int]$rule.FileSystemRights -band $script:WriteMask) -eq 0) { continue }

        $findings += [pscustomobject]@{
            Path        = $TargetPath
            Identity    = $rule.IdentityReference.Value
            Sid         = $sid
            Rights      = $rule.FileSystemRights
            IsInherited = $rule.IsInherited
            Resolvable  = (Test-SidResolvable $sid)
            Rule        = $rule
        }
    }
    return $findings
}

function Invoke-Audit {
    param([string]$RootPath)
    $keep = Get-KeepListSid -RootPath $RootPath
    $all = @()
    foreach ($t in (Get-HookAclTarget -RootPath $RootPath)) {
        $all += Get-AclFinding -TargetPath $t -KeepSids $keep
    }
    # `-OrphansOnly` acota la CLASE de hallazgo que cuenta: solo cuentas borradas.
    # Se usa donde un principal vivo tiene escritura legitima y quitarsela romperia
    # algo — `%TEMP%`, donde el sandbox de Codex si escribe.
    if ($script:OrphansOnly) {
        # `-eq $false` y no `-not`: con el tri-estado, `-not $null` daria $true y
        # un hallazgo que NO se pudo evaluar se contaria como cuenta borrada.
        $all = @($all | Where-Object { $_.Resolvable -eq $false })
    }
    return $all
}

function Save-AclBackup {
    param([string]$RootPath, [string]$Destination, [string[]]$Target)

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    }
    # Se respalda SOLO lo que se va a modificar. Respaldar el arbol entero es
    # inviable en `~/.claude` (>22k objetos) y ademas no aporta: lo heredado se
    # reconstruye solo cuando se restaura el ACE de su origen.
    $map = @{}
    foreach ($t in $Target) {
        $map[$t] = (Get-Acl -LiteralPath $t).Sddl
    }
    $jsonPath = Join-Path $Destination 'acl-backup.json'
    ($map | ConvertTo-Json -Depth 3) | Out-File -FilePath $jsonPath -Encoding utf8

    # Volcado legible del punto de partida. Sin `/T` por lo mismo de arriba.
    icacls $RootPath | Out-File -FilePath (Join-Path $Destination 'icacls-before.txt') -Encoding utf8
    return $jsonPath
}

function Restore-AclBackup {
    param([string]$BackupJson)

    if (-not (Test-Path -LiteralPath $BackupJson)) {
        throw "No existe el backup: $BackupJson"
    }
    $map = Get-Content -LiteralPath $BackupJson -Raw | ConvertFrom-Json
    foreach ($prop in $map.PSObject.Properties) {
        $target = $prop.Name
        if (-not (Test-Path -LiteralPath $target)) {
            Write-Warning "Ya no existe, se omite: $target"
            continue
        }
        # Solo la DACL: el backup guarda el SDDL completo, pero devolver duenio o
        # SACL exigiria privilegios que este script no necesita y no cambio nada.
        $acl = Get-Dacl -TargetPath $target
        $acl.SetSecurityDescriptorSddlForm($prop.Value,
            [System.Security.AccessControl.AccessControlSections]::Access)
        Set-Dacl -TargetPath $target -Acl $acl
        Write-Output "  restaurado: $target"
    }
}

function Repair-HookAcl {
    param([string]$RootPath)

    # 1) Cortar la herencia conservando copias explicitas. El otorgamiento vive en
    #    `~/.claude`; sin este corte, corregir aca adentro no dura.
    # Con `-OrphansOnly` NO se corta la herencia: los ACE a remover son explicitos
    # en cada nivel, y proteger `%TEMP%` o `AppData` los congelaria respecto de su
    # padre sin necesidad. Se toca lo minimo.
    if (-not $OrphansOnly) {
        $acl = Get-Dacl -TargetPath $RootPath
        if (-not $acl.AreAccessRulesProtected) {
            $acl.SetAccessRuleProtection($true, $true)
            Set-Dacl -TargetPath $RootPath -Acl $acl
            Write-Output "  herencia cortada en $RootPath (ACE heredados copiados a explicitos)"
        } else {
            Write-Output "  herencia ya estaba cortada en $RootPath"
        }
    }

    $keep = Get-KeepListSid -RootPath $RootPath

    # 2) Corregir la raiz. Los hijos con herencia activa se actualizan solos.
    $acl = Get-Dacl -TargetPath $RootPath
    $rootFindings = @(Get-AclFinding -TargetPath $RootPath -KeepSids $keep -Acl $acl)
    # En la raiz lo heredado SI puede entrar cuando no se pidio -OrphansOnly: es
    # el unico lugar donde cortar la herencia (mas arriba) ya lo volvio explicito.
    $rootFindings = @(Select-RepairableFinding -Findings $rootFindings `
                        -OrphansOnlyMode:$OrphansOnly -IncludeInherited:(-not $OrphansOnly))
    foreach ($f in $rootFindings) {
        [void]$acl.RemoveAccessRuleSpecific($f.Rule)
        if ((Get-AclRepairAction -Finding $f) -eq 'degradar') {
            $downgraded = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $f.Rule.IdentityReference,
                [System.Security.AccessControl.FileSystemRights]::ReadAndExecute,
                $f.Rule.InheritanceFlags,
                $f.Rule.PropagationFlags,
                [System.Security.AccessControl.AccessControlType]::Allow)
            $acl.AddAccessRule($downgraded)
            Write-Output "  $($f.Identity): $($f.Rights) -> ReadAndExecute"
        } else {
            Write-Output "  $($f.Sid): ACE eliminado (SID no resoluble, cuenta borrada)"
        }
    }
    if ($rootFindings.Count -gt 0) {
        Set-Dacl -TargetPath $RootPath -Acl $acl
    }

    # 3) Hijos con ACE EXPLICITOS de mas (los heredados ya quedaron corregidos).
    foreach ($t in (Get-HookAclTarget -RootPath $RootPath)) {
        if ($t -eq $RootPath) { continue }
        $childAcl = Get-Dacl -TargetPath $t
        # MISMO filtro y MISMA politica que la raiz: aca `-OrphansOnly` no se
        # aplicaba, asi que borraba ACE explicitos de cuentas vivas, y ademas
        # eliminaba entero lo que la raiz solo degradaba (Task 0.5).
        $childFindings = @(Select-RepairableFinding `
                             -Findings (Get-AclFinding -TargetPath $t -KeepSids $keep -Acl $childAcl) `
                             -OrphansOnlyMode:$OrphansOnly)
        if ($childFindings.Count -eq 0) { continue }
        foreach ($f in $childFindings) {
            [void]$childAcl.RemoveAccessRuleSpecific($f.Rule)
            if ((Get-AclRepairAction -Finding $f) -eq 'degradar') {
                $downgraded = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $f.Rule.IdentityReference,
                    [System.Security.AccessControl.FileSystemRights]::ReadAndExecute,
                    $f.Rule.InheritanceFlags,
                    $f.Rule.PropagationFlags,
                    [System.Security.AccessControl.AccessControlType]::Allow)
                $childAcl.AddAccessRule($downgraded)
                Write-Output "  explicito en $($t): $($f.Identity) $($f.Rights) -> ReadAndExecute"
            } else {
                Write-Output "  explicito removido en $($t): $($f.Sid) (SID no resoluble, cuenta borrada)"
            }
        }
        Set-Dacl -TargetPath $t -Acl $childAcl
    }
}

# En `~/.claude` hay ~45k ACE sobre ~22k objetos: listarlos uno por uno no es
# un reporte, es ruido. Lo unico accionable son los EXPLICITOS — normalmente uno
# solo, en la raiz — porque al corregir ese origen lo heredado cae con el.
function Write-FindingSummary {
    param([object[]]$Findings)

    $objetos = @($Findings | Select-Object -ExpandProperty Path -Unique).Count
    Write-Output "HALLAZGOS: $($Findings.Count) ACE con escritura fuera de la keep-list, sobre $objetos objeto(s)."
    Write-Output "Accionable = EXPLICITO; lo heredado cae solo al corregir su origen."

    foreach ($heredado in @($false, $true)) {
        $sel = @($Findings | Where-Object { $_.IsInherited -eq $heredado })
        if ($sel.Count -eq 0) { continue }
        $etiqueta = if ($heredado) { 'heredado ' } else { 'explicito' }
        $sel | Group-Object Identity | Sort-Object Count -Descending | ForEach-Object {
            # Tres estados tambien ACA, no solo en la decision: con truthiness,
            # un $null (no se pudo evaluar) caia en el else y se imprimia como
            # cuenta borrada. Esta salida es la evidencia que declara la Task
            # 0.5, asi que confundir ahi los dos casos es la misma Core Rule 2
            # rota un piso mas arriba.
            $huerfano = switch ($_.Group[0].Resolvable) {
                $true   { '' }
                $false  { '  [SID huerfano]' }
                default { '  [no se pudo determinar]' }
            }
            Write-Output ("  {0}  {1,-50} {2,6} objeto(s){3}" -f $etiqueta, $_.Name, $_.Count, $huerfano)
        }
    }
}

# Core Rule 2: `not_observed != absent`. Cuando el alcance se acota, decir "limpio"
# a secas seria afirmar ausencia sobre lo que ni se miro. El exito se sigue
# reportando con exit 0, pero nombrando lo que quedo sin observar.
#
# `$script:RaicesNoObservadas` (punto 4, ciclo 16.12): una raiz extra ausente
# o saltada por el guard de reparse point tambien es alcance acotado -- antes
# el caveat solo hablaba de -RootOnly/-OrphansOnly y una skills-root ausente
# quedaba fuera de "OK (ALCANCE ACOTADO)", como si se hubiera mirado.
function Get-ScopeCaveat {
    $partes = @()
    if ($script:RootOnly) {
        $partes += "solo se observo la raiz; los descendientes quedan 'unknown', NO 'limpios'"
    }
    if ($script:OrphansOnly) {
        $partes += "solo se evaluaron SID no resolubles; un principal vivo con escritura NO se reporta"
    }
    if ($script:RaicesNoObservadas.Count -gt 0) {
        $partes += "no se observaron: $($script:RaicesNoObservadas -join '; ')"
    }
    return $partes
}

function Write-CleanResult {
    param([string]$Mensaje)
    $caveats = @(Get-ScopeCaveat)
    if ($caveats.Count -eq 0) {
        Write-Output "OK: $Mensaje"
        return
    }
    Write-Output "OK (ALCANCE ACOTADO): $Mensaje"
    foreach ($c in $caveats) { Write-Output "  ! $c" }
}

# Contraparte del vector de `%TEMP%`: un archivo que llega por `move` trae ACE
# marcados como HEREDADOS que su padre nunca le dio. Como estan marcados
# heredados, `RemoveAccessRuleSpecific` no los toca; y como no vienen del padre,
# corregir el padre tampoco los limpia. La unica via es reinstalar la herencia
# del objeto, que es lo que hace `icacls /reset`.
function Repair-StaleInherited {
    param([object[]]$Findings)

    $reseteados = 0
    $omitidos = @()
    # Padres antes que hijos: resetear un directorio re-propaga a lo que cuelga.
    $porObjeto = $Findings | Group-Object Path | Sort-Object { $_.Name.Length }

    foreach ($g in $porObjeto) {
        $path = $g.Name
        # Si tiene algun hallazgo EXPLICITO, no es este caso: lo resuelve el paso normal.
        if (@($g.Group | Where-Object { -not $_.IsInherited }).Count -gt 0) { continue }

        # `/reset` descarta TODO ACE explicito del objeto. Solo es seguro cuando no
        # tiene ninguno: si lo tuviera, se estaria borrando un permiso legitimo.
        $acl = Get-Dacl -TargetPath $path
        if (@($acl.Access | Where-Object { -not $_.IsInherited }).Count -gt 0) {
            $omitidos += $path
            continue
        }

        icacls $path /reset /Q | Out-Null
        if ($LASTEXITCODE -eq 0) { $reseteados++ } else { $omitidos += $path }
    }

    Write-Output "  herencia reinstalada en $reseteados objeto(s) con ACE heredados obsoletos"
    if ($omitidos.Count -gt 0) {
        Write-Output "  $($omitidos.Count) objeto(s) OMITIDOS por tener ACE explicitos propios (no se borran a ciegas):"
        $omitidos | Select-Object -First 10 | ForEach-Object { Write-Output "    $_" }
    }
}

function Write-Finding {
    param([object[]]$Findings)
    foreach ($f in $Findings) {
        # Mismos tres estados que Write-FindingSummary, por el mismo motivo.
        $kind = switch ($f.Resolvable) {
            $true   { 'principal' }
            $false  { 'SID huerfano' }
            default { 'no se pudo determinar' }
        }
        $src  = if ($f.IsInherited) { 'heredado' } else { 'explicito' }
        Write-Output ("  [{0}] {1} -> {2} ({3}, {4})" -f $kind, $f.Identity, $f.Rights, $src, $f.Path)
    }
}

# ---------------------------------------------------------------------------

# Modo biblioteca: devuelve el control despues de definir las funciones y ANTES
# de ejecutar nada. Existe para que la bateria pueda probar la clasificacion
# --que es donde se decide que se borra-- sin tocar una sola ACL. Es un `return`
# de nivel superior, asi que el script queda dot-sourceado con sus funciones
# disponibles; el `exit` de mas abajo mataria la sesion que lo carga.
if ($env:SAIKIT_HOOKACL_LIB_ONLY -eq '1') { return }

if ($Restore) {
    Write-Output "Restaurando ACL desde: $Restore"
    Restore-AclBackup -BackupJson $Restore
    Write-Output "Restauracion completa."
    exit 0
}

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Error "No existe el directorio de hooks: $Path"
    exit 2
}

# Task 16.5/16.12: el recetario (`~/.claude/hooks/recetas`) SI vive dentro del
# arbol de hooks -- lo recorre `Get-HookAclTarget` por defecto, salvo
# `-RootOnly` -- asi que ya se audita sin pasar nada. Lo que de verdad queda
# FUERA del arbol es `~/.claude/skills/*`, y por eso -RutasExtra existia sin
# quien lo llamara (Hueco del PLAN, spec linea ~2253). Task 16.12 le pone un
# default: si el operador NO pasa `-RutasExtra` Y `-Path` tiene la forma
# `<perfil>\.claude\hooks`, se deriva la carpeta de skills de ESE `-Path`
# (hermana de `hooks`, no `$env:USERPROFILE` a ciegas) y se audita tambien.
# Si `-Path` NO tiene esa forma, `Get-DefaultSkillsRoot` devuelve `$null` --
# no hay default, y se avisa que la cobertura queda acotada a `-Path` (falla
# suave, nunca excepcion: ver la nota de la funcion).
#
# Un `-RutasExtra` explicito -- incluido `-RutasExtra ''` -- REEMPLAZA el
# default, nunca se le suma. Una ruta extra que aun no existe NO es un error
# -- se reporta `ausente` y se salta (Core Rule 2: no se acusa lo que no se
# pudo mirar); lo mismo si resulta un reparse point (guard del punto 2).
$RutasExtraEsDefault = $false
if (-not $PSBoundParameters.ContainsKey('RutasExtra')) {
    $skillsRoot = Get-DefaultSkillsRoot -HooksPath $Path
    if ($null -ne $skillsRoot) {
        $RutasExtra = @($skillsRoot)
        $RutasExtraEsDefault = $true
        Write-Output "RutasExtra por defecto (skills del perfil): $($RutasExtra -join ', ')"
        Write-Output "  (para auditar solo `$Path, pasar -RutasExtra '' -- con -File, -RutasExtra @() llega como la cadena literal '@()')"
        Write-Output "  (el default SOLO se audita: -Fix no la corrige salvo que se pase -RutasExtra explicito)"
    } else {
        $RutasExtra = @()
        Write-Output "No se deriva ninguna raiz extra (-Path no tiene la forma <perfil>\.claude\hooks). Cobertura acotada a -Path."
    }
} else {
    # Punto 5: `-RutasExtra $null` / `-RutasExtra ''` no deben reventar el bucle
    # de raices de mas abajo; ademas es la grafia de opt-out documentada arriba.
    $RutasExtra = @($RutasExtra | Where-Object { $_ })
}

$resuelto = Resolve-AuditRoots -Roots (@($Path) + @($RutasExtra)) `
              -PrimaryPath $Path -RutasExtraEsDefault $RutasExtraEsDefault
$resuelto.Messages | ForEach-Object { Write-Output $_ }
$raicesAuditadas = @($resuelto.Kept)

$before = @()
foreach ($raiz in $raicesAuditadas) {
    $before += @(Invoke-Audit -RootPath $raiz)
}

Write-Output "Arbol auditado: $($raicesAuditadas -join ', ')"
if ($before.Count -eq 0) {
    Write-CleanResult "ningun principal fuera de la keep-list tiene escritura."
    exit 0
}

Write-FindingSummary -Findings $before
if ($Detailed) {
    Write-Output ""
    Write-Finding -Findings $before
}

if (-not $Fix) {
    Write-Output ""
    Write-Output "Modo auditoria (read-only). Correr con -Fix para corregir, -Detailed para el listado completo."
    exit 1
}

# Punto 3 (ciclo 16.12): la raiz derivada por DEFECTO nunca entra a -Fix. Solo
# un -RutasExtra EXPLICITO habilita corregir fuera de -Path -- asi el radio
# destructivo de una corrida `-Fix` sin flags queda exactamente donde estaba
# antes de que existiera el default (hallazgo 1). El TOCTOU residual entre
# comprobar y corregir una raiz extra EXPLICITA sigue diferido y declarado
# (ver la nota del parametro `-RutasExtra`, mismo criterio que el limite
# TOCTOU de `Plans.md:47`, Task 16.5, y el residual de backup declarado en
# `docs/plans-archivo.md:28`, Task 0.5): no se cierra aca.
$rutasParaFix = if ($RutasExtraEsDefault) { @() } else { $RutasExtra }

# Gap 1 (segundo ciclo, 16.12): `$raicesMutables` es la MISMA lista que decide
# el radio de arriba (`$Path` + `$rutasParaFix`), reusada -- no una segunda
# regla que pueda divergir despues. Se AUDITA `$raicesAuditadas` entero (incluye
# la raiz derivada por defecto), pero solo se MUTA lo que cuelga de aca.
$raicesMutables = @($Path) + @($rutasParaFix)

# grok xrev #1 (PR #138): el no-op se decide por el RADIO MUTABLE, no por
# $before entero. $before incluye la raiz derivada (solo auditada); con
# `-Path` limpio y skills sucio, el guard viejo (`$before.Count -eq 0`, mas
# arriba) dejaba pasar y `Repair-HookAcl` le cortaba la herencia a un arbol
# SIN hallazgos -- una corrida que antes del default era no-op. Si nada de lo
# hallado cae dentro del radio, -Fix no toca un byte: ni backup ni reparacion.
$beforeMutables = @($before | Where-Object { Test-PathUnderAnyRoot -ChildPath $_.Path -Roots $raicesMutables })
if ($beforeMutables.Count -eq 0) {
    Write-Output ""
    Write-Output "POLITICA: todos los hallazgos quedan FUERA del radio que -Fix corrige (la raiz derivada por defecto solo se AUDITA). No se modifico nada; pasar -RutasExtra explicito para corregirla."
    exit 1
}

# Se respalda exactamente lo que `Repair-HookAcl` va a tocar: la raiz (se le
# corta la herencia), cada raiz extra EXPLICITA existente (nunca la derivada
# por defecto) y cualquier hijo con ACE explicito propio.
# grok xrev #2: los hijos con ACE explicito solo entran al backup si cuelgan
# del radio MUTABLE -- un hallazgo explicito bajo la raiz derivada jamas se
# muta, y meterlo inflaba el conteo de "objeto(s) a modificar" (reviewer r3).
$aTocar = @(@($Path) + @($rutasParaFix | Where-Object { Test-Path -LiteralPath $_ }) +
           @($beforeMutables | Where-Object { -not $_.IsInherited } |
             Select-Object -ExpandProperty Path) | Select-Object -Unique)

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $BackupRoot $stamp
Write-Output ""
Write-Output "Backup en: $backupDir ($($aTocar.Count) objeto(s) a modificar)"
$backupJson = Save-AclBackup -RootPath $Path -Destination $backupDir -Target $aTocar

Write-Output "Corrigiendo:"
Repair-HookAcl -RootPath $Path
if ($RutasExtraEsDefault) {
    Write-Output "  (RutasExtra por defecto NO se corrige; pasar -RutasExtra explicito para incluirla en -Fix)"
} else {
    foreach ($raiz in $rutasParaFix) {
        if (Test-Path -LiteralPath $raiz) { Repair-HookAcl -RootPath $raiz }
    }
}

# Se reusan las MISMAS raices ya resueltas (`$raicesAuditadas`) en vez de
# volver a llamar `Resolve-AuditRoots`: una ruta extra ausente o un reparse
# point no cambian entre la auditoria previa y esta, y recalcular repetiria
# los avisos y duplicaria las entradas de `$script:RaicesNoObservadas`.
$after = @()
foreach ($raiz in $raicesAuditadas) { $after += @(Invoke-Audit -RootPath $raiz) }

# Lo que sobrevive a la correccion del origen son los ACE heredados obsoletos que
# entraron por `move`. Se atacan solo si quedaron: cuesta una auditoria extra.
if ($after.Count -gt 0 -and -not $RootOnly) {
    # Gap 1: `Repair-StaleInherited` corre `icacls /reset`, que muta el objeto.
    # Solo entran los hallazgos que cuelgan de `$raicesMutables` -- un hallazgo
    # bajo la raiz derivada por defecto (auditada, no corregible sin
    # `-RutasExtra` explicito) NO esta en `$aTocar`/el backup, asi que mutarlo
    # aca lo dejaria sin como revertir con `-Restore`.
    # OJO: eso NO implica que lo de adentro del radio sea revertible entero --
    # los objetos que este `/reset` toca no llevan ACE explicito propio, asi que
    # tampoco estan en el backup: es el residual PREEXISTENTE y declarado de la
    # Task 0.5 (`docs/plans-archivo.md:28`), no lo introduce este filtro.
    $paraStale = @($after | Where-Object { Test-PathUnderAnyRoot -ChildPath $_.Path -Roots $raicesMutables })
    if ($paraStale.Count -gt 0) {
        Write-Output ""
        Write-Output "Sobrevivieron ACE que el padre ya no otorga (llegaron por move):"
        Repair-StaleInherited -Findings $paraStale
    }
    $after = @()
    foreach ($raiz in $raicesAuditadas) { $after += @(Invoke-Audit -RootPath $raiz) }
}

Write-Output ""
if ($after.Count -eq 0) {
    Write-CleanResult "ya no otorga escritura fuera de la keep-list."
    Write-Output "Revertir con: -Restore `"$backupJson`""
    exit 0
}

# Gap 1: distinguir hallazgos DENTRO del radio que -Fix corrige (fallo real de
# la correccion) de los que quedan FUERA (la raiz derivada por defecto, que es
# politica declarada -- se audita, no se corrige sin -RutasExtra explicito).
# El exit 1 es correcto en los dos casos (hay hallazgo, Core Rule 2), pero el
# texto no puede llamar "fallo de la correccion" a lo segundo.
$dentroDeAlcance = @($after | Where-Object { Test-PathUnderAnyRoot -ChildPath $_.Path -Roots $raicesMutables })
$fueraDeAlcance  = @($after | Where-Object { -not (Test-PathUnderAnyRoot -ChildPath $_.Path -Roots $raicesMutables) })

if ($dentroDeAlcance.Count -gt 0) {
    Write-Output "FALLO: quedaron ACE con escritura dentro del radio que -Fix corrige."
    Write-FindingSummary -Findings $dentroDeAlcance
}
if ($fueraDeAlcance.Count -gt 0) {
    # grok xrev #3: aca caen DOS clases -- la raiz derivada (solo auditada) y
    # cualquier ruta que GetFullPath no normaliza (fail-closed: no se muta lo
    # que no se puede comparar). El texto nombra ambas; atribuir todo a la
    # derivada mentia cuando lo excluido era una ruta rara dentro de -Path.
    Write-Output "POLITICA (no es fallo de la correccion): quedaron ACE con escritura fuera del radio que -Fix corrige -- la raiz derivada por defecto solo se AUDITA, y una ruta no normalizable (comodines, >259 chars) no se muta por postura fail-closed. Pasar -RutasExtra explicito para corregir la derivada."
    Write-FindingSummary -Findings $fueraDeAlcance
}
Write-Output "Revertir con: -Restore `"$backupJson`""
exit 1
