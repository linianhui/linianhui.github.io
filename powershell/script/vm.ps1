################################
# powershell vm(hyper-v) functions
################################

function vm ([string] $name) {
    if ([String]::IsNullOrEmpty($name)) {
        Get-VM
    }
    else {
        Get-VM -Name $name
    }
}

# https://docs.microsoft.com/en-us/powershell/module/hyper-v/new-vhd?view=win10-ps
function vhd-create(
    [string] $Path,
    [uint64] $Size = 128GB
) {
    Log-Debug "New-VHD -Dynamic -Path $Path -SizeBytes $Size"
    New-VHD `
        -Dynamic `
        -Path $Path `
        -SizeBytes $Size
}

# https://www.altaro.com/hyper-v/customize-vm-powershell/
# https://docs.microsoft.com/en-us/powershell/module/hyper-v/new-vm?view=win10-ps
# https://docs.microsoft.com/en-us/powershell/module/hyper-v/set-vm?view=win10-ps
# https://docs.microsoft.com/en-us/powershell/module/hyper-v/set-vmdvddrive?view=win10-ps
# https://learn.microsoft.com/zh-cn/windows-server/virtualization/hyper-v/best-practices-for-running-linux-on-hyper-v
function Vm-From-Json(
    [string] $JsonFilePath
) {
    $NamePadding = 22
    if ((Test-Path -Path $JsonFilePath -PathType Leaf) -eq $False) {
        Log-NameValue -Name 'not_found' -NamePadding $NamePadding -Value "$JsonFilePath"
        Log-NameValue -Name 'help' -NamePadding $NamePadding -Value 'https://linianhui.github.io/powershell/hyper-v/#config'
        return
    }

    if ((Ui-Test-Administrator) -eq $False) {
        Log-NameValue -Name 'no_permission' -NamePadding $NamePadding -Value "need use administrator"
        return
    }

    $Json = Get-Content -Path $JsonFilePath | ConvertFrom-Json

    $VhdPath = ($Json.vhd.path + "\" + $Json.name + ".vhdx")
    if ((Test-Path -Path $VhdPath -PathType Leaf) -eq $False) {
        New-VHD `
            -Dynamic `
            -Path $VhdPath `
            -BlockSizeBytes $Json.vhd.blockSize `
            -SizeBytes $Json.vhd.size | Out-Null
    }

    $VM = Get-VM -Name $Json.name -ErrorAction Ignore
    if ($VM -eq $NULL) {
        New-VM `
            -Name $Json.name `
            -Generation $Json.generation `
            -Path $Json.path `
            -SwitchName $Json.net.switch `
            -VHDPath $VhdPath | Out-Null
    }

    if ($VM.Generation -eq 2) {
        # https://learn.microsoft.com/en-us/powershell/module/hyper-v/set-vmfirmware?view=windowsserver2019-ps
        Set-VMFirmware `
            -VMName $Json.name `
            -EnableSecureBoot $Json.boot.secure
    }

    # https://learn.microsoft.com/en-us/powershell/module/hyper-v/set-vm?view=windowsserver2019-ps
    Set-VM `
        -Name $Json.name `
        -AutomaticStartAction $Json.automatic.start `
        -AutomaticStopAction $Json.automatic.stop `
        -AutomaticCheckpointsEnabled $Json.automatic.checkpoint `
        -CheckpointType $Json.checkpoint.type

    Get-VMIntegrationService -VMName $Json.name | ForEach-Object {
        Enable-VMIntegrationService -VMName $Json.name -Name $_.Name
    }

    # print vm
    $VM = Get-VM -Name $Json.name
    Log-NameValue -Name 'name' -NamePadding $NamePadding -Value $VM.Name
    Log-NameValue -Name 'generation' -NamePadding $NamePadding -Value $VM.Generation
    Log-NameValue -Name 'path' -NamePadding $NamePadding -Value $VM.Path
    Log-NameValue -Name 'state' -NamePadding $NamePadding -Value $VM.State
    if ($VM.Generation -eq 2) {
        $VMFirmware = Get-VMFirmware -VMName $Json.name
        Log-NameValue -Name 'boot.secure' -NamePadding $NamePadding -Value $VMFirmware.SecureBoot.ToString()
    }
    else {
        Log-NameValue -Name 'boot.secure' -NamePadding $NamePadding -Value 'Off'
    }
    Log-NameValue -Name 'automatic.start' -NamePadding $NamePadding -Value $VM.AutomaticStartAction
    Log-NameValue -Name 'automatic.stop' -NamePadding $NamePadding -Value $VM.AutomaticStopAction
    Log-NameValue -Name 'automatic.checkpoint' -NamePadding $NamePadding -Value $VM.AutomaticCheckpointsEnabled
    Log-NameValue -Name 'checkpoint.type' -NamePadding $NamePadding -Value $VM.CheckpointType

    # https://learn.microsoft.com/en-us/powershell/module/hyper-v/set-vmprocessor?view=windowsserver2019-ps
    Set-VMProcessor `
        -VMName $Json.name `
        -Count $Json.cpu.count
    $CPU = Get-VMProcessor -VMName $Json.name
    # print cpu
    Log-NameValue -Name 'cpu.count' -NamePadding $NamePadding -Value $CPU.Count


    # https://learn.microsoft.com/en-us/powershell/module/hyper-v/set-vmmemory?view=windowsserver2019-ps
    Set-VMMemory `
        -VMName $Json.name `
        -DynamicMemoryEnabled $True `
        -StartupBytes $Json.mem.min `
        -MinimumBytes $Json.mem.min `
        -MaximumBytes $Json.mem.max
    $MEM = Get-VMMemory -VMName $Json.name
    # print mem
    Log-NameValue -Name 'mem.dynamic' -NamePadding $NamePadding -Value $MEM.DynamicMemoryEnabled
    Log-NameValue -Name 'mem.startup' -NamePadding $NamePadding -Value ($MEM.Startup | Byte-Format)
    Log-NameValue -Name 'mem.min' -NamePadding $NamePadding -Value ($MEM.Minimum | Byte-Format)
    Log-NameValue -Name 'mem.max' -NamePadding $NamePadding -Value ($MEM.Maximum | Byte-Format)


    if ($Json.net.mac) {
        Set-VMNetworkAdapter `
            -VMName $Json.name `
            -StaticMacAddress $Json.net.mac
    }
    $VM = Get-VM -Name $Json.name
    # print net
    Log-NameValue -Name 'net.switch' -NamePadding $NamePadding -Value $VM.NetworkAdapters[0].SwitchName
    Log-NameValue -Name 'net.connected' -NamePadding $NamePadding -Value $VM.NetworkAdapters[0].Connected
    Log-NameValue -Name 'net.mac' -NamePadding $NamePadding -Value ($VM.NetworkAdapters[0].MacAddress | Mac-Format)


    $VHD = Get-VHD -Path $VhdPath
    $HDD = Get-VMHardDiskDrive -VMName $Json.name
    # print hdd
    Log-NameValue -Name 'vhd.type' -NamePadding $NamePadding -Value $VHD.VhdType
    Log-NameValue -Name 'vhd.path' -NamePadding $NamePadding -Value $VHD.Path
    Log-NameValue -Name 'vhd.format' -NamePadding $NamePadding -Value $VHD.VhdFormat
    Log-NameValue -Name 'vhd.size' -NamePadding $NamePadding -Value ($VHD.Size | Byte-Format)
    Log-NameValue -Name 'vhd.blocksize' -NamePadding $NamePadding -Value ($VHD.BlockSize | Byte-Format)
    Log-NameValue -Name 'vhd.fileSize' -NamePadding $NamePadding -Value ($VHD.FileSize | Byte-Format)
    Log-NameValue -Name 'vhd.controllerType' -NamePadding $NamePadding -Value $HDD.ControllerType
    Log-NameValue -Name 'vhd.controllerNumber' -NamePadding $NamePadding -Value $HDD.ControllerNumber
    Log-NameValue -Name 'vhd.controllerLocation' -NamePadding $NamePadding -Value $HDD.ControllerLocation


    if ($Json.dvd.iso) {
        if (Test-Path -Path $Json.dvd.iso -PathType Leaf) {
            if ((Get-VMDvdDrive -VMName $Json.name) -eq $Null) {
                Add-VMDvdDrive `
                    -VMName $Json.name `
                    -Path $Json.dvd.iso`
                    -ErrorAction Ignore
            }
        }
        $DVD = Get-VMDvdDrive -VMName $Json.name
        if ($DVD.Path) {
            # print dvd
            Log-NameValue -Name 'dvd.type' -NamePadding $NamePadding -Value $DVD.DvdMediaType
            Log-NameValue -Name 'dvd.path' -NamePadding $NamePadding -Value $DVD.Path
            Log-NameValue -Name 'dvd.fileSize' -NamePadding $NamePadding -Value ((Get-Item $DVD.Path).Length | Byte-Format)
            Log-NameValue -Name 'dvd.controllerType' -NamePadding $NamePadding -Value $DVD.ControllerType
            Log-NameValue -Name 'dvd.controllerNumber' -NamePadding $NamePadding -Value $DVD.ControllerNumber
            Log-NameValue -Name 'dvd.controllerLocation' -NamePadding $NamePadding -Value $DVD.ControllerLocation
        }
    }
}


function Vm-To-Json() {
    param (
        [string] $VMName = $(throw "VMName is null!")
    )

    $NamePadding = 22

    if ((Ui-Test-Administrator) -eq $False) {
        Log-NameValue -Name 'no_permission' -NamePadding $NamePadding -Value 'need use administrator'
        return
    }

    $VM = Get-VM -Name $VMName -ErrorAction Ignore
    if ($VM -eq $NULL) {
        Log-NameValue -Name 'not_found' -NamePadding $NamePadding -Value $VMName
        return
    }

    $AutomaticJson = [ordered]@{
        'start'      = $VM.AutomaticStartAction.ToString()
        'stop'       = $VM.AutomaticStopAction.ToString()
        'checkpoint' = $VM.AutomaticCheckpointsEnabled
    }

    $CheckpointJson = [ordered]@{
        'type' = $VM.CheckpointType.ToString()
    }

    $BootJson = [ordered]@{
        'secure' = 'Off'
    }
    if ($VM.Generation -eq 2) {
        $Boot = Get-VMFirmware -VMName $VM.Name
        $BootJson.secure = $Boot.SecureBoot.ToString()
    }

    $Cpu = Get-VMProcessor -VMName $VM.Name
    $CpuJson = [ordered]@{
        'count' = $Cpu.Count
    }

    $Mem = Get-VMMemory -VMName $VM.Name
    $MemJson = [ordered]@{
        'min' = ($Mem.Minimum | Byte-Format)
        'max' = ($Mem.Maximum | Byte-Format)
    }

    $NetJson = [ordered]@{
        'switch' = $VM.NetworkAdapters[0].SwitchName
        'mac'    = ($VM.NetworkAdapters[0].MacAddress | Mac-Format)
    }

    $VhdPath = (Get-VMHardDiskDrive -VMName $VM.Name)[0].Path
    $Vhd = Get-VHD -Path $VhdPath
    $VhdJson = [ordered]@{
        'path'      = (Get-ChildItem -Path $Vhd.Path).DirectoryName.ToLower()
        'size'      = ($Vhd.Size | Byte-Format)
        'blockSize' = ($Vhd.BlockSize | Byte-Format)
    }

    $Dvd = Get-VMDvdDrive -VMName $VM.Name
    $DvdJson = [ordered]@{
        "iso" = $Dvd.Path?.ToLower()
    }

    $Json = [ordered]@{
        'name'       = $VM.Name
        'generation' = $VM.Generation
        'path'       = $VM.Path.ToLower()
        'automatic'  = $AutomaticJson
        'boot'       = $BootJson
        'checkpoint' = $CheckpointJson
        'cpu'        = $CpuJson
        'mem'        = $MemJson
        'net'        = $NetJson
        'vhd'        = $VhdJson
        'dvd'        = $DvdJson
    }

    $Json | ConvertTo-Json
}

function vm-run ([string] $name) {
    if ((Ui-Test-Administrator) -eq $False) {
        Log-NameValue -Name 'no_permission' -NamePadding 20 -Value 'use administrator run vm'
        return
    }
    Get-VM -Name $name | Start-VM
}

function vm-stop ([string] $name) {
    if ((Ui-Test-Administrator) -eq $False) {
        Log-NameValue -Name 'no_permission' -NamePadding 10 -Value 'use administrator stop vm'
        return
    }
    Get-VM -Name $name | Stop-VM
}

function vm-ssh (
    [string]$username,
    [string]$hostname,
    [string]$port = 22) {

    Log-Debug "run [$hostname] hyper-v vm"
    vm-run -name $hostname

    Log-Debug "ssh $username@$hostname -p $port"
    ssh "$username@$hostname" -p $port
}

function ubt1 () {
    vm-ssh -username root -hostname ubt1.lan
}

function ubt2 () {
    vm-ssh -username root -hostname ubt2.lan
}

function ubt3 () {
    vm-ssh -username root -hostname ubt3.lan
}

function ceos () {
    vm-ssh -username root -hostname ceos.lan
}

function deb1 () {
    vm-ssh -username root -hostname deb1.lan
}

function deb2 () {
    vm-ssh -username root -hostname deb2.lan
}

function deb3 () {
    vm-ssh -username root -hostname deb3.lan
}