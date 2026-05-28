# --- CONFIG ---

$servers = @(
    "HorizonServer1",
    "HorizonServer2"
)

$remotePath = "C$\ProgramData\Omnissa\Horizon\Logs"
$workingDir = "D:\Logging"

# Ensure working directory exists
if (!(Test-Path $workingDir)) {
    New-Item -ItemType Directory -Path $workingDir | Out-Null
}

# Output file
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$outputFile = Join-Path $workingDir "horizon_aggregated_${timestamp}.csv"

# ---  CLEAN OLD LOGS ---
Get-ChildItem -Path $workingDir -Filter "*debug*" -File -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

Write-Host "Old debug logs removed."

# ---  COPY LOGS ---
foreach ($server in $servers) {

    $source = "\\$server\$remotePath"

    Write-Host "Copying from $server..."

    if (Test-Path $source) {

        Get-ChildItem -Path $source -Filter "debug*" -File | ForEach-Object {
            $destFile = Join-Path $workingDir "$server-$($_.Name)"
            Copy-Item $_.FullName -Destination $destFile -Force
        }
    }
    else {
        Write-Warning "Could not access $server"
    }
}

Write-Host "Copy complete."

# ---  PARSE LOGS ---
$results = @()

Get-ChildItem -Path $workingDir -Filter "*debug*" -File | ForEach-Object {

    $fileName = $_.Name
    $serverName = ($fileName -split "-")[0]

    Write-Host "Processing $fileName"

    Get-Content $_.FullName -ReadCount 1000 | ForEach-Object {

        foreach ($line in $_) {

            # event match
            if ($line -like "*BROKER_DESKTOP_REQUEST*") {

                # Extract regardless of formatting quirks
                $user = ""
                $ip   = ""
                $time = ""

                try {
                    if ($line -match "User\s+'?([^'\s,]+)") {
                        $user = $matches[1]
                    }

                    if ($line -match "ForwardedClientIpAddress=([^,\s]+)") {
                        $ip = $matches[1]
                    }

                    if ($line -match "Time=([^,]+)") {
                        $time = $matches[1].Trim()
                    }
                }
                catch {}

                # Always output row if event matched
                $results += [PSCustomObject]@{
                    Server = $serverName
                    User   = $user
                    IP     = $ip
                    Time   = $time
                }
            }
        }
    }
}

# ---  EXPORT ---
$results | Export-Csv -Path $outputFile -NoTypeInformation

Write-Host "--------------------------------------"
Write-Host "Rows written:" $results.Count
Write-Host "Output file:" $outputFile
Write-Host "--------------------------------------"
