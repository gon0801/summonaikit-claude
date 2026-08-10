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
    [switch]$RootOnly
)

$ErrorActionPreference = 'Stop'

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
            $huerfano = if ($_.Group[0].Resolvable) { '' } else { '  [SID huerfano]' }
            Write-Output ("  {0}  {1,-50} {2,6} objeto(s){3}" -f $etiqueta, $_.Name, $_.Count, $huerfano)
        }
    }
}

# Core Rule 2: `not_observed != absent`. Cuando el alcance se acota, decir "limpio"
# a secas seria afirmar ausencia sobre lo que ni se miro. El exito se sigue
# reportando con exit 0, pero nombrando lo que quedo sin observar.
function Get-ScopeCaveat {
    $partes = @()
    if ($script:RootOnly) {
        $partes += "solo se observo la raiz; los descendientes quedan 'unknown', NO 'limpios'"
    }
    if ($script:OrphansOnly) {
        $partes += "solo se evaluaron SID no resolubles; un principal vivo con escritura NO se reporta"
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
        $kind = if ($f.Resolvable) { 'principal' } else { 'SID huerfano' }
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

$before = @(Invoke-Audit -RootPath $Path)

Write-Output "Arbol auditado: $Path"
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

# Se respalda exactamente lo que `Repair-HookAcl` va a tocar: la raiz (se le
# corta la herencia) mas cualquier hijo con ACE explicito propio.
$aTocar = @(@($Path) + @($before | Where-Object { -not $_.IsInherited } |
                         Select-Object -ExpandProperty Path) | Select-Object -Unique)

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $BackupRoot $stamp
Write-Output ""
Write-Output "Backup en: $backupDir ($($aTocar.Count) objeto(s) a modificar)"
$backupJson = Save-AclBackup -RootPath $Path -Destination $backupDir -Target $aTocar

Write-Output "Corrigiendo:"
Repair-HookAcl -RootPath $Path

$after = @(Invoke-Audit -RootPath $Path)

# Lo que sobrevive a la correccion del origen son los ACE heredados obsoletos que
# entraron por `move`. Se atacan solo si quedaron: cuesta una auditoria extra.
if ($after.Count -gt 0 -and -not $RootOnly) {
    Write-Output ""
    Write-Output "Sobrevivieron ACE que el padre ya no otorga (llegaron por move):"
    Repair-StaleInherited -Findings $after
    $after = @(Invoke-Audit -RootPath $Path)
}

Write-Output ""
if ($after.Count -eq 0) {
    Write-CleanResult "ya no otorga escritura fuera de la keep-list."
    Write-Output "Revertir con: -Restore `"$backupJson`""
    exit 0
}

Write-Output "FALLO: quedaron ACE con escritura."
Write-FindingSummary -Findings $after
Write-Output "Revertir con: -Restore `"$backupJson`""
exit 1
