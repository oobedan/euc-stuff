# Used this for a Horizon View environment, there's no reboot / shutdown schedules built in like CVAD so sessions have a opportunity to ge stuck.
# logic is if session has been logged in for too long, then a a AD group check is done to determine if user is VIP or night shift user.
# intention is that this would be a scheduled task.

# ==========================================

# Configuration

# ==========================================

$MaxHours     = 10

$AllowedGroup = "NightlyRestart"

$ShutdownDelaySeconds = 1800   # 30 minutes

$ShutdownMessage = "Please save your work. System is getting restarted for maintenance."


# ==========================================

# Get AD domain DN (native ADSI)

# ==========================================

try {

    $rootDSE  = [ADSI]"LDAP://RootDSE"

    $domainDN = $rootDSE.defaultNamingContext

}

catch {

    exit 0

}

 

# ==========================================

# ADSI group membership check

# ==========================================

function Test-IsInAllowedGroup {

    param ([string]$SamAccountName)

 

    try {

        $searcher = New-Object System.DirectoryServices.DirectorySearcher

        $searcher.SearchRoot = "LDAP://$domainDN"

        $searcher.Filter = "(&(objectClass=user)(sAMAccountName=$SamAccountName))"

        $searcher.PropertiesToLoad.Add("memberOf") | Out-Null

 

        $result = $searcher.FindOne()

        if (-not $result) { return $false }

 

        foreach ($groupDN in $result.Properties.memberOf) {

            if ($groupDN -like "CN=$AllowedGroup,*") {

                return $true

            }

        }

        return $false

    }

    catch {

        return $false

    }

}

 

# ==========================================

# Get logged-in users via quser (reliable)

# ==========================================

$quserOutput = & quser 2>$null | Select-Object -Skip 1

if (-not $quserOutput) { exit 0 }

 

foreach ($line in $quserOutput) {

 

    if (:IsNullOrWhiteSpace($line)) {

        continue

    }

 

    # Parse quser output by whitespace tokens

    $tokens = $line -split '\s+'

 

    # Username (strip active-session marker '>')

    $userName = $tokens[0].Trim().TrimStart('>')

 

    # Rebuild LOGON TIME safely

    if ($tokens[-1] -match 'AM|PM') {

        # 12-hour format

        $logonText = "$($tokens[-3]) $($tokens[-2]) $($tokens[-1])"

    }

    else {

        # 24-hour format

        $logonText = "$($tokens[-2]) $($tokens[-1])"

    }

 

    # Parse logon time using current culture

    try {

        $logonTime = :Parse(

            $logonText,

            [Globalization.CultureInfo]::CurrentCulture

        )

    }

    catch {

        continue

    }

 

    # Calculate logged-in duration

    $hoursLoggedIn = ((Get-Date) - $logonTime).TotalHours

 

    if ($hoursLoggedIn -lt $MaxHours) {

        continue

    }

 

    # Check AD group exemption

    if (-not (Test-IsInAllowedGroup -SamAccountName $userName)) {

 

        # ==========================================

        # Trigger forced restart with 30‑minute warning

        # ==========================================

        shutdown.exe /r /f /t $ShutdownDelaySeconds /c $ShutdownMessage

        break

    }

}
