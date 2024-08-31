Import-Module NLog

$logConfig = @"
<nlog>
  <targets>
    <target xsi:type="File" name="logfile" fileName="${basedir}/connection_monitor.log" 
            archiveEvery="Size" maxArchiveFiles="5" 
            archiveNumbering="Date" 
            layout="${longdate}|${level}|${message}" />
  </targets>
  <rules>
    <logger name="*" minlevel="Info" writeTo="logfile" />
  </rules>
</nlog>
"@
Set-Content -Path 'NLog.config' -Value $logConfig

$config = Get-Content -Path 'config.json' | ConvertFrom-Json

if (-not $config.logDirectory -or -not $config.ipstackApiKey -or -not $config.notificationEmail -or -not $config.smtpServer) {
    throw "Configurações obrigatórias não estão presentes no arquivo de configuração."
}

$geoLocationCache = @{}
$cacheExpirationTime = 3600 # 1 hora
$scriptVersion = "1.0.0"
$executionId = [guid]::NewGuid().ToString()
$hostName = $env:COMPUTERNAME

function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $logEntry = "{0} | {1} | {2} | {3} | {4} | {5}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message, $scriptVersion, $hostName, $executionId
    [NLog.LogManager]::GetCurrentClassLogger().Log($Level, $logEntry)
}

function Get-GeoLocation {
    param (
        [Parameter(Mandatory=$true)]
        [string]$IPAddress
    )

    $currentTime = Get-Date
    if ($geoLocationCache.ContainsKey($IPAddress) -and ($currentTime - $geoLocationCache[$IPAddress].Timestamp).TotalSeconds -lt $cacheExpirationTime) {
        return $geoLocationCache[$IPAddress].Data
    }

    $url = "http://api.ipstack.com/$IPAddress?access_key=$($config.ipstackApiKey)"
    $retryCount = 0
    $maxRetries = 3
    $retryDelay = 2 # segundos

    while ($retryCount -lt $maxRetries) {
        try {
            $response = Invoke-RestMethod -Uri $url
            $geoLocationCache[$IPAddress] = @{ Data = $response; Timestamp = $currentTime }
            return $response
        } catch {
            Write-Log -Message "Error obtaining geolocation information for $IPAddress: $_" -Level Error
            Start-Sleep -Seconds $retryDelay
            $retryCount++
            $retryDelay *= 2 # Atraso exponencial
        }
    }
    return $null
}

function Send-Notification {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message
    )

    try {
        Send-MailMessage -To $config.notificationEmail -Subject 'Connection Alert' -Body $Message -SmtpServer $config.smtpServer -Port $config.smtpPort -Username $config.smtpUsername -Password $config.smtpPassword
    } catch {
        Write-Log -Message "Error sending notification: $_" -Level Error
    }
}

function Monitor-Connection {
    param (
        [string]$IPAddress,
        [int]$Port,
        [string[]]$AllowedRegions
    )

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.Connect($IPAddress, $Port)

        $geoLocation = Get-GeoLocation -IPAddress $IPAddress
        if ($geoLocation -and $AllowedRegions -contains $geoLocation.country_code) {
            Write-Log -Message "Connection allowed from $($geoLocation.country_name) for IP address $IPAddress on port $Port"
        } else {
            $message = "Connection detected from $($geoLocation.country_name) ($($geoLocation.country_code)) for IP address $IPAddress on port $Port"
            Send-Notification -Message $message
            Write-Log -Message $message -Level Warning
        }
    } catch {
        Write-Log -Message "Error monitoring connection for $IPAddress:$Port: $_" -Level Error
    } finally {
        if ($tcpClient -and $tcpClient.Connected) {
            $tcpClient.Close()
        }
    }
}

function Monitor-Connections {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$ConnectionsToMonitor,
        [string[]]$AllowedRegions = $config.allowedRegions
    )

    $jobs = @()
    foreach ($connection in $ConnectionsToMonitor.GetEnumerator()) {
        $IPAddress = $connection.Key
        $Port = $connection.Value
        $jobs += Start-Job -ScriptBlock { Monitor-Connection -IPAddress $using:IPAddress -Port $using:Port -AllowedRegions $using:AllowedRegions }
    }
    $jobs | Wait-Job | Receive-Job
}

$connectionsToMonitor = @{
    '192.168.1.100' = 3306
    '10.0.0.50'     = 22
    '2001:db8::1'   = 80
}

Monitor-Connections -ConnectionsToMonitor $connectionsToMonitor

$trigger = New-JobTrigger -Daily -At (Get-Date).AddMinutes(5)
$options = New-ScheduledJobOption -RunElevated
Register-ScheduledJob -Name 'ConnectionMonitor' -ScriptBlock { Monitor-Connections -ConnectionsToMonitor $connectionsToMonitor } -Trigger $trigger -ScheduledJobOption $options
