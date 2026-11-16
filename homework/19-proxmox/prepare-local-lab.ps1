#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$vbox = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'
if (-not (Test-Path -LiteralPath $vbox)) {
    throw 'VirtualBox was not found in Program Files. Install VirtualBox first.'
}

$vmName = 'otus-proxmox-19'
$labRoot = Join-Path $PSScriptRoot '.local-lab'
$iso = Join-Path $labRoot 'proxmox-ve_9.2-1.iso'
$disk = Join-Path $labRoot 'otus-proxmox-19.vdi'
$isoUrl = 'https://download.proxmox.com/iso/proxmox-ve_9.2-1.iso'
$expectedSha256 = '4e88fe416df9b527624a175f24c9aa07c714d3332afb1ee3dbf3879573ef2c6c'

function Invoke-VBox {
    & $vbox @args
    if ($LASTEXITCODE -ne 0) {
        throw "VBoxManage exited with code $LASTEXITCODE (arguments: $($args -join ' '))"
    }
}

New-Item -ItemType Directory -Path $labRoot -Force | Out-Null

if (Test-Path -LiteralPath $iso) {
    $existingSha256 = (Get-FileHash -LiteralPath $iso -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($existingSha256 -ne $expectedSha256) {
        $unverified = "$iso.unverified-$([guid]::NewGuid().ToString('N'))"
        Move-Item -LiteralPath $iso -Destination $unverified
        Write-Warning "Existing ISO did not match the official checksum; moved to $unverified"
    }
}

if (-not (Test-Path -LiteralPath $iso)) {
    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
        throw 'curl.exe is required to download the ISO.'
    }

    $partial = "$iso.partial"
    if (Test-Path -LiteralPath $partial) {
        Remove-Item -LiteralPath $partial
    }

    Write-Host 'Downloading Proxmox VE 9.2 installer ISO (about 1.6 GiB)...'
    $curlArgs = @('--fail', '--location', '--show-error', '--silent', '--retry', '2', '--connect-timeout', '20', '--output', $partial, $isoUrl)
    & curl.exe @curlArgs
    $curlExit = $LASTEXITCODE
    if ($curlExit -eq 60) {
        Write-Warning 'Certificate validation failed. Retrying this ISO download without certificate validation; the pinned SHA-256 must still match.'
        if (Test-Path -LiteralPath $partial) {
            Remove-Item -LiteralPath $partial
        }
        & curl.exe --insecure @curlArgs
        $curlExit = $LASTEXITCODE
    }
    if ($curlExit -ne 0) {
        throw "ISO download failed. curl exit code: $curlExit"
    }
    if (-not (Test-Path -LiteralPath $partial)) {
        throw 'ISO download did not create a file.'
    }
    $downloadSha256 = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($downloadSha256 -ne $expectedSha256) {
        throw "Downloaded ISO did not match the official SHA-256 checksum. File: $partial"
    }
    Move-Item -LiteralPath $partial -Destination $iso
}

$existing = & $vbox list vms
if ($LASTEXITCODE -ne 0) { throw 'Could not list VirtualBox VMs.' }
if ($existing | Select-String -SimpleMatch ('"' + $vmName + '"')) {
    throw "VM $vmName already exists. This script does not change existing VMs."
}
if (Test-Path -LiteralPath $disk) {
    throw "Disk already exists: $disk. This script does not overwrite disks."
}

Write-Host 'Creating Proxmox VM: 2 vCPU, 7 GiB RAM, 64 GiB dynamically allocated disk.'
Invoke-VBox createvm --name $vmName --ostype Debian_64 --register --basefolder $labRoot
Invoke-VBox modifyvm $vmName --memory 7168 --cpus 2 --nested-hw-virt on --ioapic on --nic1 nat --nictype1 82540EM --nicpromisc1 allow-all --nat-pf1 'pve,tcp,127.0.0.1,8006,,8006' --boot1 dvd --boot2 disk
Invoke-VBox storagectl $vmName --name SATA --add sata --controller IntelAHCI
Invoke-VBox createmedium disk --filename $disk --size 65536 --format VDI
Invoke-VBox storageattach $vmName --storagectl SATA --port 0 --device 0 --type hdd --medium $disk
Invoke-VBox storageattach $vmName --storagectl SATA --port 1 --device 0 --type dvddrive --medium $iso

Write-Host 'VM created. Starting the installer in VirtualBox.'
Invoke-VBox startvm $vmName --type gui
Write-Host 'After installing Proxmox, open https://127.0.0.1:8006/ on this computer.'
