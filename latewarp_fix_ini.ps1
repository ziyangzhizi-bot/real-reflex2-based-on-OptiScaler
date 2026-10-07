# ---------------------------------------------------------------------------
#  latewarp_fix_ini.ps1 -- restore the KNOWN-GOOD ini values in one command.
#
#  Why this exists: the OptiScaler panel writes its runtime state back to
#  OptiScaler.ini when you press "Save Settings", and that state contains values
#  OptiScaler resolved itself (FGOutput/FGInput become "auto") plus every debug
#  key that was on. The latewarp then runs in the wrong mode or paints the
#  diagnostic heat map over the screen. This script puts the keys back.
#
#  usage: .\latewarp_fix_ini.ps1 [-GameDir <bin\x64>] [-DryRun]
# ---------------------------------------------------------------------------
param(
    [string]$GameDir = "E:\SteamLibrary\steamapps\common\Cyberpunk 2077\bin\x64",
    [switch]$DryRun
)
$ErrorActionPreference = "Stop"
$ini = Join-Path $GameDir "OptiScaler.ini"
if (-not (Test-Path -LiteralPath $ini)) { throw ("ini not found: " + $ini) }

# robustness: warn when the game is up (the ini is only read at start) and always keep a backup
if (Get-Process Cyberpunk2077 -ErrorAction SilentlyContinue) {
    Write-Warning "Cyberpunk2077 is running: the change is only picked up after a restart."
}
function Backup-Ini([string]$path) {
    $bak = $path + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
    Copy-Item -LiteralPath $path -Destination $bak -Force
    Write-Host ("[ini] backup -> " + $bak)
}

# key = the value the shipped configuration needs
$want = [ordered]@{
    FGOutput = "nofg"; FGInput = "DLSSG"
    Rewrite = "true"; TagWarpInPlace = "true"; ViewmodelMask = "true"; PresentOnly = "false"
    WarpScale = "1.000000"; MaskThreshold = "5.000000"; DepthCutoff = "0.028000"
    DiagMap = "0.000000"; PeakBoost = "0.000000"; HighlightProtect = "false"
    FeedComposite = "false"; ProbeState = "false"; FeedCompositeApply = "false"
    UseNvidiaLatewarp = "true"
}

$t = [IO.File]::ReadAllText($ini)
$changed = 0; $missing = @()
foreach ($k in $want.Keys) {
    $rx = "(?m)^[ \t]*" + $k + "[ \t]*=[ \t]*(.*?)[ \t\r]*$"
    $m = [regex]::Matches($t, $rx)
    if ($m.Count -eq 0) { $missing += $k; continue }
    $cur = $m[0].Groups[1].Value.Trim()
    if ($cur -ne $want[$k]) {
        Write-Host ("  " + $k.PadRight(20) + " " + $cur + "  ->  " + $want[$k])
        $changed++
    }
    $t = [regex]::Replace($t, $rx, ($k + " = " + $want[$k]))
}
if ($missing.Count) { Write-Host ("  not present in this ini (skipped): " + ($missing -join ", ")) }
Write-Host ("[fix] " + $changed + " value(s) differ")
if ($DryRun) { Write-Host "[dry] nothing written"; exit 0 }
if ($changed -gt 0) { Backup-Ini $ini; [IO.File]::WriteAllText($ini, $t, (New-Object System.Text.UTF8Encoding($false))) }
Write-Host "[fix] ini is now the shipped configuration -- restart the game"