#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$vbox = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'
if (-not (Test-Path -LiteralPath $vbox)) {
    throw 'VirtualBox не найден в Program Files. Установите VirtualBox до запуска скрипта.'
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
        throw "VBoxManage завершился с кодом $LASTEXITCODE (аргументы: $($args -join ' '))"
    }
}

New-Item -ItemType Directory -Path $labRoot -Force | Out-Null

if (-not (Test-Path -LiteralPath $iso)) {
    Write-Host 'Скачиваю установочный ISO Proxmox VE 9.2 (около 1,6 ГБ)...'
    Invoke-WebRequest -Uri $isoUrl -OutFile $iso
}
$actualSha256 = (Get-FileHash -LiteralPath $iso -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSha256 -ne $expectedSha256) {
    throw "Хеш ISO не совпал с официальным. Файл: $iso"
}

$existing = & $vbox list vms
if ($LASTEXITCODE -ne 0) { throw 'Не удалось получить список ВМ VirtualBox.' }
if ($existing | Select-String -SimpleMatch ('"' + $vmName + '"')) {
    throw "ВМ $vmName уже существует. Скрипт не изменяет существующие ВМ."
}
if (Test-Path -LiteralPath $disk) {
    throw "Диск уже существует: $disk. Скрипт не перезаписывает диски."
}

Write-Host 'Создаю виртуальную машину Proxmox: 2 vCPU, 7 ГБ RAM, динамический диск 64 ГБ.'
Invoke-VBox createvm --name $vmName --ostype Debian_64 --register --basefolder $labRoot
Invoke-VBox modifyvm $vmName --memory 7168 --cpus 2 --nested-hw-virt on --ioapic on --nic1 nat --nictype1 82540EM --nicpromisc1 allow-all --nat-pf1 'pve,tcp,127.0.0.1,8006,,8006' --boot1 dvd --boot2 disk
Invoke-VBox storagectl $vmName --name SATA --add sata --controller IntelAHCI
Invoke-VBox createmedium disk --filename $disk --size 65536 --format VDI
Invoke-VBox storageattach $vmName --storagectl SATA --port 0 --device 0 --type hdd --medium $disk
Invoke-VBox storageattach $vmName --storagectl SATA --port 1 --device 0 --type dvddrive --medium $iso

Write-Host 'ВМ создана. Запускаю установщик в окне VirtualBox.'
Invoke-VBox startvm $vmName --type gui
Write-Host 'После установки Proxmox откройте https://127.0.0.1:8006/ на этом компьютере.'
