#Requires -RunAsAdministrator
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$vmName = 'otus-proxmox-19-hyperv'
$switchName = 'OTUS-Proxmox-19-NAT'
$natName = 'OTUS-Proxmox-19-NAT'
$subnet = '172.28.19.0/24'
$hostAddress = '172.28.19.1'
$labRoot = Join-Path $PSScriptRoot '.local-lab'
$vdi = Join-Path $labRoot 'otus-proxmox-19.vdi'
$vhd = Join-Path $labRoot 'otus-proxmox-19-hyperv.vhd'
$vmPath = Join-Path $labRoot 'hyperv'

Import-Module Hyper-V -ErrorAction Stop
if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) { throw "VM already exists: $vmName" }
if (-not (Test-Path -LiteralPath $vhd)) {
    if (-not (Test-Path -LiteralPath $vdi)) { throw "VirtualBox disk not found: $vdi" }
    $vbox = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'
    if (-not (Test-Path -LiteralPath $vbox)) { throw 'VirtualBox is not installed' }
    $info = @(& $vbox showvminfo 'otus-proxmox-19' --machinereadable)
    if ($LASTEXITCODE -ne 0 -or -not ($info | Select-String '^VMState="poweroff"$')) {
        throw 'Shut down the VirtualBox Proxmox VM before cloning its disk'
    }
    & $vbox clonemedium disk $vdi $vhd --format VHD --variant Standard
    if ($LASTEXITCODE -ne 0) { throw 'Could not clone the VirtualBox disk to VHD' }
}

$switch = Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue
if ($switch -and $switch.SwitchType -ne 'Internal') {
    throw "Switch $switchName exists but is not Internal"
}
$nat = Get-NetNat -Name $natName -ErrorAction SilentlyContinue
if ($nat -and $nat.InternalIPInterfaceAddressPrefix -ne $subnet) {
    throw "NAT $natName uses a different subnet"
}
if (-not $nat -and (Get-NetNat -ErrorAction SilentlyContinue)) {
    throw 'Another Windows NAT already exists. Inspect it before creating a second NAT.'
}
if (-not $switch -and (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -like '172.28.19.*' })) {
    throw 'The selected 172.28.19.0/24 subnet is already in use.'
}

if (-not $switch) { $switch = New-VMSwitch -Name $switchName -SwitchType Internal }
$alias = "vEthernet ($switchName)"
$address = Get-NetIPAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -eq $hostAddress }
if (-not $address) {
    New-NetIPAddress -InterfaceAlias $alias -IPAddress $hostAddress -PrefixLength 24 | Out-Null
}
if (-not $nat) { New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix $subnet | Out-Null }

New-Item -ItemType Directory -Path $vmPath -Force | Out-Null
New-VM -Name $vmName -Generation 1 -MemoryStartupBytes 5GB -VHDPath $vhd -Path $vmPath -SwitchName $switchName | Out-Null
Set-VMProcessor -VMName $vmName -Count 2 -ExposeVirtualizationExtensions $true
Set-VMMemory -VMName $vmName -DynamicMemoryEnabled $false
Set-VMNetworkAdapter -VMName $vmName -MacAddressSpoofing On
Start-VM -Name $vmName

Get-VM -Name $vmName | Select-Object Name,State,Generation,MemoryStartup
Get-VMProcessor -VMName $vmName | Select-Object Count,ExposeVirtualizationExtensions
Write-Host "VM prepared. Open its console, then update Proxmox vmbr0 to 172.28.19.2/24, gateway $hostAddress."
Write-Host 'For the two nested Ubuntu guests, use static addresses such as 172.28.19.10/24 and 172.28.19.11/24 with the same gateway.'
