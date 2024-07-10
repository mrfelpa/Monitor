# Considerations

- The script uses the free IPstack service (https://ipstack.com/) to obtain geolocation information. It is recommended to consult the API documentation and usage limits.
- The script requires authentication for sending emails, be sure to correctly configure the SMTP server, user, and password data.
- Change the list of ***allowed countries (allowedRegions)*** according to your need.

# Requirements

- Windows PowerShell 5.1 or higher
- PowerShell modules:
  
                ConvertFrom-Json
                New-Object
                Get-Date
                Join-Path
                Get-Cache
                Set-Cache
                Invoke-RestMethod
                Send-MailMessage
                New-JobTrigger
                New-ScheduledJobOption
                Register-ScheduledJob

- A free account on a geolocation service like IPstack (https://ipstack.com/)
- Access to an SMTP server for sending email notifications.

# Configuration

- Create a file named config.json in the same folder as the script, the file must contain the following settings in JSON format:

        {
          ipstackApiKey: YOUR_API_ACCESS_KEY,
          notificationEmail: RECIPIENT_EMAIL,
          smtpServer: SMTP_SERVER,
          smtpPort: SMTP_PORT,
          smtpUsername: SMTP_USERNAME,
          smtpPassword: SMTP_PASSWORD,
          allowedRegions: [US, CA, FR],
          logDirectory: PATH_TO_LOG_DIRECTORY
        }

# Use

- Save the script as connection_monitor.ps1.
- Run the script in PowerShell to check connections once.

- ***(Optional) Scheduling:*** To run the script automatically every 5 minutes, use the commented code at the end of the script:
- You must run this code with administrative privileges.
