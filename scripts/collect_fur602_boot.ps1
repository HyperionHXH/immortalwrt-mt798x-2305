[CmdletBinding()]
param(
    [string]$InterfaceAlias = "Ethernet",
    [ValidateRange(20, 180)]
    [int]$CaptureSeconds = 60,
    [string]$OutputDirectory = (Join-Path $PWD ("fur602-diagnostics-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss")))
)

$ErrorActionPreference = "Stop"

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Snapshot {
    param(
        [string]$Path,
        [string]$Stage
    )

    "===== $Stage $(Get-Date -Format o) =====" | Add-Content -LiteralPath $Path -Encoding UTF8
    Get-NetAdapter -Name $InterfaceAlias |
        Format-List Name, InterfaceDescription, Status, LinkSpeed, MacAddress, ifIndex |
        Out-String | Add-Content -LiteralPath $Path -Encoding UTF8
    Get-NetIPAddress -InterfaceAlias $InterfaceAlias -ErrorAction SilentlyContinue |
        Format-Table -AutoSize AddressFamily, IPAddress, PrefixLength, PrefixOrigin, AddressState |
        Out-String | Add-Content -LiteralPath $Path -Encoding UTF8
    Get-NetNeighbor -InterfaceAlias $InterfaceAlias -ErrorAction SilentlyContinue |
        Sort-Object AddressFamily, IPAddress |
        Format-Table -AutoSize AddressFamily, IPAddress, LinkLayerAddress, State |
        Out-String | Add-Content -LiteralPath $Path -Encoding UTF8
    arp.exe -a | Out-String | Add-Content -LiteralPath $Path -Encoding UTF8
}

function Test-TcpPort {
    param(
        [string]$Address,
        [int]$Port,
        [int]$TimeoutMilliseconds = 500
    )

    $client = [Net.Sockets.TcpClient]::new()
    try {
        $result = $client.BeginConnect($Address, $Port, $null, $null)
        if (-not $result.AsyncWaitHandle.WaitOne($TimeoutMilliseconds)) {
            return $false
        }
        $client.EndConnect($result)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}

if (-not (Test-Administrator)) {
    throw "Run this script from an elevated PowerShell window."
}

$adapter = Get-NetAdapter -Name $InterfaceAlias -ErrorAction Stop
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$summaryPath = Join-Path $OutputDirectory "summary.txt"
$etlPath = Join-Path $OutputDirectory "fur602-boot.etl"
$pcapPath = Join-Path $OutputDirectory "fur602-boot.pcapng"
$textPath = Join-Path $OutputDirectory "fur602-boot.txt"
$probeAddresses = @("192.168.1.1", "192.168.6.1")
$temporaryAddresses = [System.Collections.Generic.List[string]]::new()
$ipv4Interface = Get-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4
$originalDhcp = $ipv4Interface.Dhcp
$originalAutomaticMetric = $ipv4Interface.AutomaticMetric
$originalInterfaceMetric = $ipv4Interface.InterfaceMetric
$metricChanged = $false

"FUR602 boot capture" | Set-Content -LiteralPath $summaryPath -Encoding UTF8
"InterfaceAlias: $InterfaceAlias" | Add-Content -LiteralPath $summaryPath -Encoding UTF8
"InterfaceIndex: $($adapter.ifIndex)" | Add-Content -LiteralPath $summaryPath -Encoding UTF8
"AdapterMAC: $($adapter.MacAddress)" | Add-Content -LiteralPath $summaryPath -Encoding UTF8
"OriginalDhcp: $originalDhcp" | Add-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Snapshot -Path $summaryPath -Stage "BEFORE"

Write-Host "Capture directory: $OutputDirectory"
Write-Host "Connect the PC directly to one FUR602 port, turn the router off, then press Enter."
Read-Host | Out-Null

try {
    Set-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 `
        -AutomaticMetric Disabled -InterfaceMetric 500 -PolicyStore ActiveStore
    $metricChanged = $true
    "Ethernet interface metric temporarily changed from $originalInterfaceMetric to 500; Wi-Fi remains preferred." |
        Add-Content -LiteralPath $summaryPath -Encoding UTF8

    foreach ($probeAddress in "192.168.1.2", "192.168.6.2") {
        $hasProbeAddress = Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -eq $probeAddress }
        if (-not $hasProbeAddress) {
            New-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $probeAddress -PrefixLength 24 `
                -SkipAsSource $true -PolicyStore ActiveStore | Out-Null
            $temporaryAddresses.Add($probeAddress)
            "Temporary probe address added: $probeAddress/24" |
                Add-Content -LiteralPath $summaryPath -Encoding UTF8
        }
    }

    pktmon.exe start --capture --comp nics --pkt-size 0 --file-size 128 --file-name $etlPath | Out-Null
    Write-Host "Capture started. Power on the FUR602 now. Waiting $CaptureSeconds seconds..."

    $startedAt = Get-Date
    $deadline = $startedAt.AddSeconds($CaptureSeconds)
    $lastStateKey = ""
    while ((Get-Date) -lt $deadline) {
        $second = [int]((Get-Date) - $startedAt).TotalSeconds
        $current = Get-NetAdapter -Name $InterfaceAlias
        $stateKey = "{0}|{1}" -f $current.Status, $current.LinkSpeed
        if ($stateKey -ne $lastStateKey) {
            "{0,3}s status={1} link={2}" -f $second, $current.Status, $current.LinkSpeed |
                Add-Content -LiteralPath $summaryPath -Encoding UTF8
            $lastStateKey = $stateKey
        }

        foreach ($address in $probeAddresses) {
            $subnetPrefix = if ($address -eq "192.168.6.1") { "192.168.6." } else { "192.168.1." }
            $sourceAddress = Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress.StartsWith($subnetPrefix) } |
                Select-Object -First 1 -ExpandProperty IPAddress
            if (-not $sourceAddress) {
                continue
            }

            ping.exe -n 1 -w 250 -S $sourceAddress $address | Out-Null
            if ($LASTEXITCODE -eq 0) {
                "{0,3}s ping={1} success" -f $second, $address |
                    Add-Content -LiteralPath $summaryPath -Encoding UTF8
            }
        }
        Start-Sleep -Milliseconds 500
    }

    pktmon.exe counters | Out-String | Add-Content -LiteralPath $summaryPath -Encoding UTF8
}
finally {
    pktmon.exe stop | Out-Null
    Write-Snapshot -Path $summaryPath -Stage "AFTER"

    foreach ($address in $probeAddresses) {
        foreach ($port in 22, 80, 443) {
            "TCP {0}:{1} = {2}" -f $address, $port, (Test-TcpPort -Address $address -Port $port) |
                Add-Content -LiteralPath $summaryPath -Encoding UTF8
        }
    }

    if (Test-Path -LiteralPath $etlPath) {
        pktmon.exe etl2pcap $etlPath --out $pcapPath | Out-Null
        pktmon.exe etl2txt $etlPath --out $textPath | Out-Null
    }

    foreach ($address in $temporaryAddresses) {
        Remove-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $address -PolicyStore ActiveStore `
            -Confirm:$false -ErrorAction SilentlyContinue
    }

    Set-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 `
        -Dhcp $originalDhcp -PolicyStore ActiveStore

    if ($metricChanged) {
        if ($originalAutomaticMetric -eq "Enabled") {
            Set-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 `
                -AutomaticMetric Enabled -PolicyStore ActiveStore
        }
        else {
            Set-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 `
                -AutomaticMetric Disabled -InterfaceMetric $originalInterfaceMetric -PolicyStore ActiveStore
        }
    }

    Write-Snapshot -Path $summaryPath -Stage "RESTORED"
}

Write-Host "Capture complete: $OutputDirectory"
Write-Host "Send summary.txt first. Keep fur602-boot.pcapng for deeper packet analysis if needed."
