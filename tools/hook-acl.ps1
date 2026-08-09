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
    [string]$Restore
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

function Test-SidResolvable {
    param([string]$SidValue)
    try {
        $sid = New-Object System.Security.Principal.SecurityIdentifier($SidValue)
        [void]$sid.Translate([System.Security.Principal.NTAccount])
        return $true
    } catch {
        return $false
    }
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
    $targets += (Get-ChildItem -LiteralPath $RootPath -Recurse -Force |
                 Select-Object -ExpandProperty FullName)
    return $targets
}

function Get-AclFinding {
    param(
        [string]$TargetPath,
        [System.Collections.Generic.HashSet[string]]$KeepSids
    )
    $findings = @()
    $acl = Get-Acl -LiteralPath $TargetPath
    foreach ($rule in $acl.Access) {
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
    return $all
}

function Save-AclBackup {
    param([string]$RootPath, [string]$Destination)

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    }
    $map = @{}
    foreach ($t in (Get-HookAclTarget -RootPath $RootPath)) {
        $map[$t] = (Get-Acl -LiteralPath $t).Sddl
    }
    $jsonPath = Join-Path $Destination 'acl-backup.json'
    ($map | ConvertTo-Json -Depth 3) | Out-File -FilePath $jsonPath -Encoding utf8

    # Volcado legible, para poder auditar el backup sin PowerShell.
    icacls $RootPath /T | Out-File -FilePath (Join-Path $Destination 'icacls-before.txt') -Encoding utf8
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
        $acl = Get-Acl -LiteralPath $target
        $acl.SetSecurityDescriptorSddlForm($prop.Value)
        Set-Acl -LiteralPath $target -AclObject $acl
        Write-Output "  restaurado: $target"
    }
}

function Repair-HookAcl {
    param([string]$RootPath)

    # 1) Cortar la herencia conservando copias explicitas. El otorgamiento vive en
    #    `~/.claude`; sin este corte, corregir aca adentro no dura.
    $acl = Get-Acl -LiteralPath $RootPath
    if (-not $acl.AreAccessRulesProtected) {
        $acl.SetAccessRuleProtection($true, $true)
        Set-Acl -LiteralPath $RootPath -AclObject $acl
        Write-Output "  herencia cortada en $RootPath (ACE heredados copiados a explicitos)"
    } else {
        Write-Output "  herencia ya estaba cortada en $RootPath"
    }

    $keep = Get-KeepListSid -RootPath $RootPath

    # 2) Corregir la raiz. Los hijos con herencia activa se actualizan solos.
    $acl = Get-Acl -LiteralPath $RootPath
    $rootFindings = Get-AclFinding -TargetPath $RootPath -KeepSids $keep
    foreach ($f in $rootFindings) {
        [void]$acl.RemoveAccessRuleSpecific($f.Rule)
        if ($f.Resolvable) {
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
        Set-Acl -LiteralPath $RootPath -AclObject $acl
    }

    # 3) Hijos con ACE EXPLICITOS de mas (los heredados ya quedaron corregidos).
    foreach ($t in (Get-HookAclTarget -RootPath $RootPath)) {
        if ($t -eq $RootPath) { continue }
        $childFindings = @(Get-AclFinding -TargetPath $t -KeepSids $keep | Where-Object { -not $_.IsInherited })
        if ($childFindings.Count -eq 0) { continue }
        $childAcl = Get-Acl -LiteralPath $t
        foreach ($f in $childFindings) {
            [void]$childAcl.RemoveAccessRuleSpecific($f.Rule)
            Write-Output "  explicito removido en $($t): $($f.Identity) ($($f.Rights))"
        }
        Set-Acl -LiteralPath $t -AclObject $childAcl
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
    Write-Output "OK: ningun principal fuera de la keep-list tiene escritura."
    exit 0
}

Write-Output "HALLAZGOS: $($before.Count) ACE con escritura fuera de la keep-list."
Write-Finding -Findings $before

if (-not $Fix) {
    Write-Output ""
    Write-Output "Modo auditoria (read-only). Correr con -Fix para corregir."
    exit 1
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $BackupRoot $stamp
Write-Output ""
Write-Output "Backup en: $backupDir"
$backupJson = Save-AclBackup -RootPath $Path -Destination $backupDir

Write-Output "Corrigiendo:"
Repair-HookAcl -RootPath $Path

$after = @(Invoke-Audit -RootPath $Path)
Write-Output ""
if ($after.Count -eq 0) {
    Write-Output "OK: el arbol de hooks ya no otorga escritura fuera de la keep-list."
    Write-Output "Revertir con: -Restore `"$backupJson`""
    exit 0
}

Write-Output "FALLO: quedaron $($after.Count) ACE con escritura."
Write-Finding -Findings $after
Write-Output "Revertir con: -Restore `"$backupJson`""
exit 1
