
# A script to remove Emtpy Document Sets from a SharePoint document library based on existence of a populated metadata field.
#
# When Purview removes files that have reached end of retention (disposal) it will leave behind empty Document Sets
# Script will check for emptiness and remove accordinly if metadata is present. 

# Usage> .\script.ps1 -SiteURL "https://mytennant.sharepoint.com/sites/mySite" -DocumentLibraryName "Documents" -DisposalTagValue(optional) "myvalue"

param (
    [string]$siteURL,
    [string]$documentLibraryName,
    [string]$DisposalTagValue
)

$Global:Report = @()

function Test-DocSetHasFiles {
    param ($DriveId, $ItemId)

    try {
        $children = Get-MgDriveItemChild -DriveId $DriveId -DriveItemId $ItemId -All -ErrorAction Stop
    }
    catch {
        return $false
    }

    foreach ($child in $children) {

        $hasFile   = $child.File -ne $null
        $hasFolder = $child.Folder -ne $null
        $size      = $child.Size

        $isRealFile   = ($hasFile -and $size -gt 0)
        $isRealFolder = ($hasFolder -and $size -eq 0)

        if ($isRealFile) {
            return $true
        }

        if ($isRealFolder -and $child.Id) {
            if (Test-DocSetHasFiles -DriveId $DriveId -ItemId $child.Id) {
                return $true
            }
        }
    }

    return $false
}

function Process-Folders {
    param ($DriveId, $FolderId)

    try {
        $items = Get-MgDriveItemChild -DriveId $DriveId -DriveItemId $FolderId -All -ErrorAction Stop
    }
    catch {
        return
    }

    $folders = $items | Where-Object { $_.Folder -ne $null }

    foreach ($folder in $folders) {

        try {
            $fields = Get-MgDriveItemListItemField -DriveId $DriveId -DriveItemId $folder.Id
            $props  = $fields.AdditionalProperties

            $ct  = $props["ContentType"]
            $tag = $props["DisposalTag"]

            if ($ct -and $ct -like "*Record File*") {

                if ([System.String]::IsNullOrWhiteSpace($tag)) {

                    $Global:Report += [PSCustomObject]@{
                        Name = $folder.Name
                        Status = "Skipped"
                        DisposalTag = $tag
                        Error = "No tag"
                        Url = $folder.WebUrl
                    }

                    Process-Folders -DriveId $DriveId -FolderId $folder.Id
                    continue
                }

                if ($DisposalTagValue -and $tag -ne $DisposalTagValue) {

                    $Global:Report += [PSCustomObject]@{
                        Name = $folder.Name
                        Status = "Skipped"
                        DisposalTag = $tag
                        Error = "Tag mismatch"
                        Url = $folder.WebUrl
                    }

                    Process-Folders -DriveId $DriveId -FolderId $folder.Id
                    continue
                }

                $hasFiles = Test-DocSetHasFiles -DriveId $DriveId -ItemId $folder.Id

                if ($hasFiles) {

                    $Global:Report += [PSCustomObject]@{
                        Name = $folder.Name
                        Status = "NotEmpty"
                        DisposalTag = $tag
                        Error = ""
                        Url = $folder.WebUrl
                    }

                    continue
                }

                try {
                    Remove-MgDriveItemRetentionLabel -DriveId $DriveId -DriveItemId $folder.Id -ErrorAction Stop
                    Remove-MgDriveItem -DriveId $DriveId -DriveItemId $folder.Id -ErrorAction Stop

                    $status = "Deleted"
                    $error  = ""
                }
                catch {
                    $status = "Failed"
                    $error  = $_.Exception.Message
                }

                $Global:Report += [PSCustomObject]@{
                    Name = $folder.Name
                    Status = $status
                    DisposalTag = $tag
                    Error = $error
                    Url = $folder.WebUrl
                }

                continue
            }
        }
        catch {}

        if ($folder.Folder -and $folder.Id) {
            Process-Folders -DriveId $DriveId -FolderId $folder.Id
        }
    }
}

# MAIN
Connect-MgGraph -Scopes "Sites.FullControl.All","Files.ReadWrite.All","RecordsManagement.ReadWrite.All" -NoWelcome

$uri  = [System.Uri]$siteURL
$site = Get-MgSite -SiteId ($uri.Host + ":" + $uri.AbsolutePath.TrimEnd('/'))

$drive = Get-MgSiteDrive -SiteId $site.Id | Where-Object { $_.Name -eq $documentLibraryName }

if (-not $drive) { return }

Process-Folders -DriveId $drive.Id -FolderId "root"

# =====================
# SUMMARY
# =====================
Write-Host ""
Write-Host "========== SUMMARY =========="

$total    = $Global:Report.Count
$deleted  = ($Global:Report | Where-Object Status -eq "Deleted").Count
$notEmpty = ($Global:Report | Where-Object Status -eq "NotEmpty").Count
$skipped  = ($Global:Report | Where-Object Status -eq "Skipped").Count
$failed   = ($Global:Report | Where-Object Status -eq "Failed").Count

Write-Host ("Total   : {0}" -f $total)
Write-Host ("Deleted : {0}" -f $deleted)
Write-Host ("NotEmpty: {0}" -f $notEmpty)
Write-Host ("Skipped : {0}" -f $skipped)
Write-Host ("Failed  : {0}" -f $failed)

# =====================
# WINDOWS FORM REPORT
# =====================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Windows.Forms.DataVisualization

$form = New-Object System.Windows.Forms.Form
$form.Text = "Empty Record File Cleanup Report"
$form.Width = 900
$form.Height = 600

# Chart
$chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
$chart.Width = 400
$chart.Height = 300
$chart.Left = 10
$chart.Top = 10

$chartArea = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea
$chart.ChartAreas.Add($chartArea)

$series = New-Object System.Windows.Forms.DataVisualization.Charting.Series
$series.ChartType = "Column"

$counts = $Global:Report | Group-Object Status

foreach ($c in $counts) {
    [void]$series.Points.AddXY($c.Name, $c.Count)
}

$chart.Series.Add($series)
$form.Controls.Add($chart)

# Label
$label = New-Object System.Windows.Forms.Label
$label.Text = "Deleted Document Sets (URLs):"
$label.Left = 10
$label.Top = 320
$label.Width = 200 
$form.Controls.Add($label)

# ListBox
$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Left = 10
$listBox.Top = 350
$listBox.Width = 850
$listBox.Height = 150

$Global:Report | Where-Object Status -eq "Deleted" | ForEach-Object {
    $listBox.Items.Add($_.Url) | Out-Null
}

$form.Controls.Add($listBox)

# Copy Button
$copyButton = New-Object System.Windows.Forms.Button
$copyButton.Text = "Copy URLs"
$copyButton.Left = 10
$copyButton.Top = 510
$copyButton.Width = 120

$copyButton.Add_Click({
    $urls = $listBox.Items -join "`r`n"
    [System.Windows.Forms.Clipboard]::SetText($urls)
})

$form.Controls.Add($copyButton)

$form.Topmost = $true
$form.ShowDialog()

Disconnect-MgGraph
