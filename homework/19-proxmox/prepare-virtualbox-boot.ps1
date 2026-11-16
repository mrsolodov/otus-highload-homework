#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated Windows PowerShell session.'
}

$bitlocker = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
if ($bitlocker.ProtectionStatus -eq 'On') {
    throw 'BitLocker protection is active. Do not change boot configuration without a recovery plan and the recovery key.'
}

$vbox = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'
if (-not (Test-Path -LiteralPath $vbox)) {
    throw 'VirtualBox was not found in Program Files.'
}
$vmInfo = @(& $vbox showvminfo 'otus-proxmox-19' --machinereadable)
if ($LASTEXITCODE -ne 0) {
    throw 'Could not inspect the Proxmox VM in VirtualBox.'
}
if (-not ($vmInfo | Select-String '^VMState="poweroff"$')) {
    throw 'Shut down otus-proxmox-19 completely in Proxmox before changing boot settings.'
}

$labRoot = Join-Path $PSScriptRoot '.local-lab'
New-Item -ItemType Directory -Path $labRoot -Force | Out-Null
$idFile = Join-Path $labRoot 'virtualbox-boot-entry.txt'
$bootId = $null

if (Test-Path -LiteralPath $idFile) {
    $candidate = (Get-Content -LiteralPath $idFile -Raw).Trim()
    if ($candidate -match '^\{[0-9a-fA-F-]{36}\}$') {
        $existingEntry = @(& bcdedit.exe /enum $candidate 2>&1)
        if ($LASTEXITCODE -eq 0) {
            $bootId = $candidate
        }
    }
}

if (-not $bootId) {
    $copyOutput = @(& bcdedit.exe /copy '{current}' /d 'OTUS Proxmox lab (no hypervisor)' 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create a separate Windows boot entry: $($copyOutput -join ' ')"
    }
    $match = [regex]::Match(($copyOutput -join ' '), '\{[0-9a-fA-F-]{36}\}')
    if (-not $match.Success) {
        throw "Could not identify the new boot entry: $($copyOutput -join ' ')"
    }
    $bootId = $match.Value
    Set-Content -LiteralPath $idFile -Value $bootId -Encoding ascii
}

& bcdedit.exe /set $bootId hypervisorlaunchtype off
if ($LASTEXITCODE -ne 0) {
    throw "Could not disable hypervisor in the lab boot entry $bootId"
}
& bcdedit.exe /bootsequence $bootId
if ($LASTEXITCODE -ne 0) {
    throw "Could not select the lab boot entry for the next restart: $bootId"
}

Write-Host 'The lab boot entry will be used for the next restart only.'
Write-Host 'The normal Windows boot entry remains unchanged. WSL2 and virtualization-based security will not work in the lab boot session.'
Write-Host 'Restart Windows when ready, then start the existing VirtualBox VM otus-proxmox-19.'
