<#
.SYNOPSIS
  Backs up Dawnward Chronicles and Total RP 3 for ONE game flavour folder
  (for example _classic_era_ or the Forever folder) before installing a new
  Dawnward package, and proves the copies are complete.

.DESCRIPTION
  * Refuses to run while any game client from that World of Warcraft folder is running.
  * Copies, into <BackupRoot>\<yyyyMMdd-HHmmss>-<flavour>\ (keeping relative paths):
      Interface\AddOns\DawnwardChronicles\      (whole folder, if present)
      Interface\AddOns\totalRP3*\               (whole folders, if present)
      WTF\Account\...\SavedVariables\DawnwardChronicles*.lua and .lua.bak
      WTF\Account\...\SavedVariables\totalRP3*.lua and .lua.bak
      (account-wide and per-character)
  * Hashes every original and its copy (SHA-256), requires them to match,
    re-reads each copy, and writes manifest.csv in the backup folder.
  * Never deletes, moves or writes anything inside the World of Warcraft folder.
  * Each flavour is backed up separately: Classic Era and Forever data are never mixed.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Backup-DawnwardData.ps1 -Flavour _classic_era_
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Flavour,
    [string]$WowRoot = 'C:\Program Files (x86)\World of Warcraft',
    [string]$BackupRoot = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Coding Projects\Dawnward Backups')
)

$ErrorActionPreference = 'Stop'
$source = Join-Path $WowRoot $Flavour
if (-not (Test-Path -LiteralPath $source)) { throw "Flavour folder not found: $source" }

$running = Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -and $_.Path.StartsWith($WowRoot, [StringComparison]::OrdinalIgnoreCase) }
if ($running) {
    throw ("World of Warcraft is still running ({0}). Exit the game completely (and wait for it to close), then run this again." -f
        (($running | ForEach-Object { $_.ProcessName }) -join ', '))
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dest = Join-Path $BackupRoot ("{0}-{1}" -f $stamp, $Flavour.Trim('_'))
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
$addons = Join-Path $source 'Interface\AddOns'
if (Test-Path -LiteralPath $addons) {
    Get-ChildItem -LiteralPath $addons -Directory | Where-Object {
        $_.Name -eq 'DawnwardChronicles' -or $_.Name -like 'totalRP3*' } | ForEach-Object {
        Get-ChildItem -LiteralPath $_.FullName -Recurse -File | ForEach-Object { $files.Add($_) }
    }
}
$account = Join-Path $source 'WTF\Account'
if (Test-Path -LiteralPath $account) {
    Get-ChildItem -LiteralPath $account -Recurse -File -Include 'DawnwardChronicles*.lua', 'DawnwardChronicles*.lua.bak',
        'totalRP3*.lua', 'totalRP3*.lua.bak' | Where-Object { $_.DirectoryName -like '*\SavedVariables' } |
        ForEach-Object { $files.Add($_) }
}
if ($files.Count -eq 0) { Write-Host "Nothing to back up in $source (no Dawnward or Total RP 3 files)."; return }

$manifest = New-Object System.Collections.Generic.List[object]
$bad = 0
foreach ($f in $files) {
    $rel = $f.FullName.Substring($source.Length + 1)
    $target = Join-Path $dest $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath $f.FullName -Destination $target
    $a = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    $b = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    $readable = $true
    try { [void][System.IO.File]::ReadAllBytes($target) } catch { $readable = $false }
    $ok = ($a -eq $b) -and $readable
    if (-not $ok) { $bad++ }
    $manifest.Add([pscustomobject]@{ File = $rel; Bytes = $f.Length; SHA256 = $a; CopySHA256 = $b; Readable = $readable; Match = $ok })
}
$manifest | Export-Csv -LiteralPath (Join-Path $dest 'manifest.csv') -NoTypeInformation -Encoding UTF8

Write-Host ("Backed up {0} files from {1}" -f $files.Count, $source)
Write-Host ("Backup folder: {0}" -f $dest)
if ($bad -gt 0) {
    Write-Host ("WARNING: {0} file(s) did not verify. Do NOT install; see manifest.csv." -f $bad) -ForegroundColor Red
    exit 1
}
Write-Host 'Every copy matches its original (SHA-256) and is readable. You may now install.' -ForegroundColor Green
