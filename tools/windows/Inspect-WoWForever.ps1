<#
.SYNOPSIS
  Read-only inventory of the World of Warcraft installation for Dawnward
  Chronicles launch checks: installed game flavours and builds, executable
  versions, every installed addon's TOC metadata (Total RP 3 in particular),
  and which Dawnward / Total RP 3 SavedVariables files exist.

.DESCRIPTION
  Never writes inside the World of Warcraft folder, never reads the contents
  of SavedVariables files (only their names, sizes and dates), never starts
  the game. The report is written to the console and to a text file in the
  backup folder you choose (default: your Desktop\Coding Projects\Dawnward Backups).

  Paste the report back to the Dawnward session so it can confirm the
  Forever interface number, the installed TRP3 build and any addon conflicts.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Inspect-WoWForever.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Inspect-WoWForever.ps1 -WowRoot "D:\Games\World of Warcraft"
#>
[CmdletBinding()]
param(
    [string]$WowRoot,
    [string]$ReportDir = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Coding Projects\Dawnward Backups')
)

$ErrorActionPreference = 'Continue'
$lines = New-Object System.Collections.Generic.List[string]
function Say([string]$text) { $lines.Add($text); Write-Host $text }

function Find-WowRoot {
    $keys = @('HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft',
              'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft')
    foreach ($k in $keys) {
        try {
            $p = (Get-ItemProperty -Path $k -ErrorAction Stop).InstallPath
            if ($p) {
                # InstallPath points at one flavour folder (for example ...\_retail_\); its parent is the root.
                $root = Split-Path -Path $p.TrimEnd('\') -Parent
                if (Test-Path -LiteralPath (Join-Path $root '.build.info')) { return $root }
                if (Test-Path -LiteralPath (Join-Path $p '.build.info')) { return $p }
            }
        } catch { }
    }
    $default = 'C:\Program Files (x86)\World of Warcraft'
    if (Test-Path -LiteralPath $default) { return $default }
    return $null
}

if (-not $WowRoot) { $WowRoot = Find-WowRoot }
Say "Dawnward Chronicles: read-only WoW inspection, $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
if (-not $WowRoot -or -not (Test-Path -LiteralPath $WowRoot)) {
    Say "World of Warcraft folder not found. Run again with -WowRoot ""<path to the World of Warcraft folder>""."
    return
}
Say "WoW root: $WowRoot"

# Is any game client running? (Only reported here; the backup script refuses to run while one is.)
$running = Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -and $_.Path.StartsWith($WowRoot, [StringComparison]::OrdinalIgnoreCase) }
Say ("Game processes running from this folder: " + $(if ($running) { ($running | ForEach-Object { $_.ProcessName }) -join ', ' } else { 'none' }))

# .build.info: one row per installed product (Product, Version, Branch, ...).
$buildInfo = Join-Path $WowRoot '.build.info'
Say ''
Say '== Installed products (.build.info)'
if (Test-Path -LiteralPath $buildInfo) {
    $rows = Get-Content -LiteralPath $buildInfo
    if ($rows.Count -gt 0) {
        $header = $rows[0].Split('|') | ForEach-Object { ($_ -split '!')[0] }
        $want = @('Branch', 'Active', 'Version', 'Product', 'Tags')
        for ($i = 1; $i -lt $rows.Count; $i++) {
            $cells = $rows[$i].Split('|')
            $out = @()
            for ($c = 0; $c -lt $header.Count -and $c -lt $cells.Count; $c++) {
                if ($want -contains $header[$c]) { $out += "$($header[$c])=$($cells[$c])" }
            }
            Say ('  ' + ($out -join '  '))
        }
    }
} else { Say '  (no .build.info)' }

# Each flavour folder (_retail_, _classic_era_, ...) has a .flavor.info.
Say ''
Say '== Game flavour folders'
$flavours = Get-ChildItem -LiteralPath $WowRoot -Directory -Force | Where-Object {
    Test-Path -LiteralPath (Join-Path $_.FullName '.flavor.info') }
foreach ($f in $flavours) {
    $flavorInfo = (Get-Content -LiteralPath (Join-Path $f.FullName '.flavor.info') -ErrorAction SilentlyContinue) -join ' / '
    Say "-- $($f.Name)  (.flavor.info: $flavorInfo)"
    Get-ChildItem -LiteralPath $f.FullName -Filter '*.exe' -File | ForEach-Object {
        $v = $_.VersionInfo
        Say ("   exe {0}: FileVersion {1}, ProductVersion {2}, {3:N0} bytes, modified {4:yyyy-MM-dd}" -f
            $_.Name, $v.FileVersion, $v.ProductVersion, $_.Length, $_.LastWriteTime)
    }
}

function Read-TocFields([string]$path) {
    $fields = [ordered]@{}
    foreach ($line in (Get-Content -LiteralPath $path -TotalCount 60 -ErrorAction SilentlyContinue)) {
        if ($line -match '^##\s*([^:]+):\s*(.*)$') { $fields[$Matches[1].Trim()] = $Matches[2].Trim() }
    }
    return $fields
}

foreach ($f in $flavours) {
    $addons = Join-Path $f.FullName 'Interface\AddOns'
    Say ''
    Say "== AddOns in $($f.Name)"
    if (-not (Test-Path -LiteralPath $addons)) { Say '   (no Interface\AddOns folder)'; continue }
    foreach ($dir in (Get-ChildItem -LiteralPath $addons -Directory | Sort-Object Name)) {
        $tocs = Get-ChildItem -LiteralPath $dir.FullName -Filter '*.toc' -File
        if (-not $tocs) { Say "   $($dir.Name): no .toc file (WoW will not load it)"; continue }
        foreach ($toc in $tocs) {
            $t = Read-TocFields $toc.FullName
            $deps = @($t['Dependencies'], $t['RequiredDeps'], $t['Dep']) | Where-Object { $_ }
            Say ("   {0}\{1}: Title={2} | Version={3} | Interface={4} | Deps={5} | OptionalDeps={6} | SavedVariables={7}" -f
                $dir.Name, $toc.Name, $t['Title'], $t['Version'], $t['Interface'], ($deps -join ','),
                $t['OptionalDeps'], $t['SavedVariables'])
        }
        if ($dir.Name -like 'totalRP3*') {
            $hash = (Get-FileHash -LiteralPath $tocs[0].FullName -Algorithm SHA256).Hash
            Say "      TOC SHA-256 $hash"
        }
    }
}

foreach ($f in $flavours) {
    $account = Join-Path $f.FullName 'WTF\Account'
    if (-not (Test-Path -LiteralPath $account)) { continue }
    Say ''
    Say "== Dawnward / Total RP 3 SavedVariables in $($f.Name) (names, sizes and dates only)"
    Get-ChildItem -LiteralPath $account -Recurse -File -Include 'DawnwardChronicles*', 'totalRP3*' -ErrorAction SilentlyContinue |
        ForEach-Object {
            Say ("   {0}  {1:N0} bytes  {2:yyyy-MM-dd HH:mm}" -f $_.FullName.Substring($f.FullName.Length + 1), $_.Length, $_.LastWriteTime)
        }
}

Say ''
Say 'In game, also run:  /dump GetBuildInfo()   and   /dump WOW_PROJECT_ID'
try {
    New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
    $file = Join-Path $ReportDir ("wow-inspection-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $lines | Set-Content -LiteralPath $file -Encoding UTF8
    Write-Host "`nReport saved to $file"
} catch { Write-Host "Could not save the report: $_" }
