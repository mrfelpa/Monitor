
$config = Get-Content -Path 'config.json' | ConvertFrom-Json

$logFilePath = Join-Path -Path $config.logDirectory -ChildPath 'connection_monitor.log'
$logger = New-Object -TypeName 'System.IO.StreamWriter' -ArgumentList $logFilePath, $true

function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $logEntry = "{0} | {1} | {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    $logger.WriteLine($logEntry)
    $logger.Flush()
}

function Get-GeoLocation {
    param (
        [Parameter(Mandatory=$true)]
        [string]$IPAddress
    )

    $cacheKey = "GeoLocation_$IPAddress"
    $geoLocation = Get-Cache -Key $cacheKey

    if ($geoLocation) {
        return $geoLocation
    }

    $url = "http://api.ipstack.com/$IPAddress`?access_key=$($config.ipstackApiKey)"

    try {
        $response = Invoke-RestMethod -Uri $url
        Set-Cache -Key $cacheKey -Value $response
        return $response
    } catch {
        Write-Log -Message "Error obtaining geolocation information for $IPAddress`: $_" -Level Error
        return $null
    }
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

function Monitor-Connections {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$ConnectionsToMonitor,
        [string[]]$AllowedRegions = $config.allowedRegions
    )

    foreach ($connection in $ConnectionsToMonitor.GetEnumerator()) {
        $IPAddress = $connection.Key
        $Port = $connection.Value

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
            Write-Log -Message "Error monitoring connection for $IPAddress`:$Port`: $_" -Level Error
        } finally {
            if ($tcpClient -and $tcpClient.Connected) {
                $tcpClient.Close()
            }
        }
    }
}

$connectionsToMonitor = @{
    '192.168.1.100' = 3306
    '10.0.0.50'     = 22
    '2001:db8::1'   = 80
}

Monitor-Connections -ConnectionsToMonitor $connectionsToMonitor

# Schedule the script to run every 5 minutes
$trigger = New-JobTrigger -Daily -At (Get-Date).AddMinutes(5)
$options = New-ScheduledJobOption -RunElevated
Register-ScheduledJob -Name 'ConnectionMonitor' -ScriptBlock { Monitor-Connections -ConnectionsToMonitor $connectionsToMonitor } -Trigger $trigger -ScheduledJobOption $options
