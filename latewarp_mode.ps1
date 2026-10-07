# ---------------------------------------------------------------------------
#  latewarp_mode.ps1 -- pick the latewarp set that matches how YOU run the game.
#  Both sets use the SAME built OptiScaler.dll; only the configuration differs.
#
#    -Mode mfg   FRAME GENERATION ON (the game or the ReShade MFG addon generates frames)
#                [FrameGen] FGOutput = nofg / FGInput = DLSSG
#                [Latewarp] TagWarpInPlace = true / PresentOnly = false
#                => mechanism C warps ScalingOutputColor at the DLSS evaluate, so the GENERATED
#                   frames inherit the warp (multi-frame generation + the latency win). The
#                   viewmodel mask is fed by the game own HUDLessColor tag, which only exists
#                   while it generates frames. MEASURED 2026-10-01 13:39: mask 7.67%.
#
#    -Mode old   FRAME GENERATION OFF (no MFG anywhere). This is the classic enable path:
#                OptiScaler runs its own frame generation and takes its inputs from the
#                UPSCALER, and the warp happens on the present chain (the way the latewarp
#                worked before the multi-frame-generation work):
#                [FrameGen] FGOutput = Reprojection / FGInput = upscaler
#                [Latewarp] TagWarpInPlace = false / PresentOnly = true
#                => the present chain warps the display frame and produces the viewmodel mask
#                   and the pink "Show static elements" overlay.
#
#  usage: .\latewarp_mode.ps1 -Mode mfg        # or -Mode old
#         add -DryRun to only look, -IniOnly is implied for both (no DLL is touched)
#         -LegacyDll additionally installs the 2026-09-28 pre-P3C build (fallback for people
#         who want that exact binary); it is NOT needed for -Mode old to work.
# ---------------------------------------------------------------------------
param(
    [Parameter(Mandatory = $true)][ValidateSet("mfg", "old")][string]$Mode,
    [string]$GameDir = "E:\SteamLibrary\steamapps\common\Cyberpunk 2077\bin\x64",
    [switch]$LegacyDll,
    [switch]$DryRun
)
$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
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

if ($Mode -eq "mfg") {
    $pairs = @(@("FGOutput", "nofg"), @("FGInput", "DLSSG"), @("TagWarpInPlace", "true"), @("PresentOnly", "false"))
} else {
    $pairs = @(@("FGOutput", "Reprojection"), @("FGInput", "upscaler"), @("TagWarpInPlace", "false"), @("PresentOnly", "true"))
}

$t = [IO.File]::ReadAllText($ini)
foreach ($pair in $pairs) {
    $rx = "(?m)^[ \t]*" + $pair[0] + "[ \t]*=[ \t]*\S+[ \t\r]*$"
    $n = ([regex]::Matches($t, $rx)).Count
    if ($n -ne 1) { Write-Warning ("key " + $pair[0] + " not found exactly once (found " + $n + ") -- skipped") ; continue }
    $t = [regex]::Replace($t, $rx, ($pair[0] + " = " + $pair[1]))
}
Write-Host ("[mode] " + $Mode)
foreach ($pair in $pairs) { Write-Host ("       " + $pair[0] + " = " + $pair[1]) }
if ($DryRun) { Write-Host "[dry] nothing written"; exit 0 }
Backup-Ini $ini
[IO.File]::WriteAllText($ini, $t, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "       ini written -- restart the game to apply"

if ($LegacyDll) {
    $dll = Join-Path $Repo "_re\reflex2_mod\versions\P3C-pre_noWarpMask_20260928\OptiScaler_preP3C_noWarpMask.dll"
    if (-not (Test-Path -LiteralPath $dll)) { throw ("legacy DLL not found: " + $dll) }
    if (Get-Process Cyberpunk2077 -ErrorAction SilentlyContinue) { throw "the game is running -- close it first" }
    $install = Join-Path $PSScriptRoot "install_p2_into_game.ps1"
    & $install -GameDir $GameDir -Uninstall *>&1 | Out-Null
    & $install -GameDir $GameDir -ProxyName dxgi.dll -OptiScalerDll $dll *>&1 | Select-Object -Last 2 | ForEach-Object { Write-Host ("       " + $_) }
}