# ---------------------------------------------------------------------------
#  install_p2_into_game.ps1 -- put the PATCHED OptiScaler into a game, and take it back out.
#
#  OptiScaler is normally installed as a proxy DLL that the game loads by name (dxgi.dll,
#  d3d12.dll, winmm.dll, nvngx.dll, ...). This script does exactly that with the build you
#  just made, backing up anything it displaces, and can undo it byte-for-byte.
#
#  It does NOT touch any other mod's files, and it never edits the game's own binaries.
#
#  usage:
#    .\install_p2_into_game.ps1 -GameDir <dir> -DryRun
#    .\install_p2_into_game.ps1 -GameDir <dir> -ProxyName dxgi.dll
#    .\install_p2_into_game.ps1 -GameDir <dir> -Uninstall
#
#  After installing, pick "Latewarp (Reflex 2)" in OptiScaler's menu: the backend is OFF by
#  default on purpose, so nothing changes for anyone who does not ask for it.
# ---------------------------------------------------------------------------
param(
    [Parameter(Mandatory = $true)][string]$GameDir,
    [ValidateSet('dxgi.dll','d3d12.dll','d3d11.dll','winmm.dll','nvngx.dll','dbghelp.dll')][string]$ProxyName = 'dxgi.dll',
    [string]$OptiScalerDll = '',
    [switch]$Uninstall,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$P2   = Split-Path -Parent $MyInvocation.MyCommand.Path
$Repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $P2))
if (-not $OptiScalerDll) { $OptiScalerDll = Join-Path $Repo '_re\repro_src\x64\ReleaseDebug\OptiScaler.dll' }

if (-not (Test-Path -LiteralPath $GameDir)) { throw "game dir not found: $GameDir" }
$GameDir = (Resolve-Path -LiteralPath $GameDir).Path
$statePath = Join-Path $GameDir '_p2_state.txt'
$slot = Join-Path $GameDir $ProxyName
function Get-Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }

# ---------------------------------------------------------------- uninstall --
if ($Uninstall) {
    if (-not (Test-Path -LiteralPath $statePath)) { throw "no _p2_state.txt in the game dir -- nothing this script installed" }
    $st = Get-Content -LiteralPath $statePath
    $add = ($st | Where-Object { $_ -like 'added=*' }) -replace '^added=', ''
    $bak = ($st | Where-Object { $_ -like 'backup=*' }) -replace '^backup=', ''
    $sha = ($st | Where-Object { $_ -like 'installedSha=*' }) -replace '^installedSha=', ''
    # Take the proxy name from the state, NOT from this invocation's default: otherwise an
    # uninstall without -ProxyName looks at the wrong file, leaves it behind and then deletes
    # the state file (found by test_game_install.ps1's "removes the file we added" case).
    $proxyRecorded = ($st | Where-Object { $_ -like 'proxy=*' }) -replace '^proxy=', ''
    if ($proxyRecorded) { $ProxyName = $proxyRecorded }
    $slot = Join-Path $GameDir $ProxyName
    Write-Host ("[uninstall] proxy from state: " + $ProxyName)
    if ((Test-Path -LiteralPath $slot) -and $sha -and ((Get-Sha $slot) -ne $sha)) {
        throw ("the installed file was replaced since (slot hash differs) -- refusing to touch it: " + $slot)
    }
    if ($bak -and (Test-Path -LiteralPath $bak)) {
        if ($DryRun) { Write-Host ("[dry] restore " + $bak + " -> " + $slot) }
        else { Copy-Item -LiteralPath $bak -Destination $slot -Force; Write-Host ("[uninstall] restored " + $slot + "  sha256 " + (Get-Sha $slot)) }
    } elseif ($add) {
        if ($DryRun) { Write-Host ("[dry] delete " + $slot + " (we added it)") }
        elseif (Test-Path -LiteralPath $slot) { Remove-Item -LiteralPath $slot -Force; Write-Host ("[uninstall] deleted " + $slot + " (we added it)") }
    }
    if (-not $DryRun) { Remove-Item -LiteralPath $statePath -Force }
    Write-Host "[uninstall] done"
    exit 0
}

# ---------------------------------------------------- anti-cheat policy gate --
# AC-P2-008 is a REFUSAL, not a warning: the scope decision is "no kernel-level anti-cheat"
# games, because an injected proxy in front of EAC/BattlEye/Vanguard/... is exactly what gets
# accounts banned. There is deliberately NO override switch and -DryRun refuses too.
# Uninstall is NOT gated: taking the mod out is never the risky direction.
$acsys = @(Get-ChildItem -LiteralPath $GameDir -Recurse -Depth 3 -File -Filter '*.sys' -ErrorAction SilentlyContinue)
$acmarkers = @('EasyAntiCheat', 'BEService', 'BEClient', 'BattlEye', 'vgk', 'mhyprot',
               'AntiCheatExpert', 'GameMon', 'npggnt', 'x3.xem', 'XIGNCODE', 'nProtect', 'HShield')
$achit = @(Get-ChildItem -LiteralPath $GameDir -Recurse -Depth 3 -File -ErrorAction SilentlyContinue |
           Where-Object { $n = $_.Name; @($acmarkers | Where-Object { $n -like ('*' + $_ + '*') }).Count -gt 0 })
if ($acsys.Count -gt 0) {
    throw ("REFUSED (AC-P2-008): a kernel driver is present in the game tree:" + [char]10 +
           "    " + $acsys[0].FullName + [char]10 +
           "This patch set is single-player / no-kernel-anti-cheat only; the installer has no" + [char]10 +
           "-Force switch. Nothing was written.")
}
if ($achit.Count -gt 0) {
    throw ("REFUSED (AC-P2-008): kernel-level anti-cheat detected in the game tree:" + [char]10 +
           "    " + $achit[0].FullName + [char]10 +
           "This patch set is single-player / no-kernel-anti-cheat only; the installer has no" + [char]10 +
           "-Force switch. Nothing was written.")
}
# ------------------------------------------------ nvngx.dll deployment guard --
# When OptiScaler is installed AS nvngx.dll it BECOMES the NGX entry point and has to find the
# real core to forward to. It looks for "_nvngx.dll" first (proxies/NVNGX_Proxy.h:447), which is
# exactly where install_latewarp_dll.ps1 puts the user's latewarp-capable core. Installing
# nvngx.dll without that file leaves the game with no usable NGX at all (DLSS and frame
# generation break), so refuse here instead of half-installing.
if ($ProxyName -eq 'nvngx.dll') {
    $coreSide = Join-Path $GameDir '_nvngx.dll'
    if (-not (Test-Path -LiteralPath $coreSide)) {
        throw ("REFUSED: -ProxyName nvngx.dll needs the real NGX core beside it as _nvngx.dll," + [char]10 +
               "but " + $coreSide + " does not exist. OptiScaler would become the NGX" + [char]10 +
               "entry point and then find no core to forward to, which breaks DLSS / frame" + [char]10 +
               "generation in the game. Run this first (it verifies the file and places it):" + [char]10 +
               "    .\install_latewarp_dll.ps1 -GameDir <same dir> -LatewarpDll <feature dll> -CoreDll <nvngx.dll>" + [char]10 +
               "Nothing was written.")
    }
    $coreLen = (Get-Item -LiteralPath $coreSide).Length
    if ($coreLen -lt 500000) {
        throw ("REFUSED: " + $coreSide + " is only " + $coreLen + " bytes -- that is not an NGX core" + [char]10 +
               "(the driver core alone is ~488 KB and knows nothing about feature 15). Nothing was written.")
    }
    Write-Host ("[guard] _nvngx.dll present (" + $coreLen + " bytes) -- OptiScaler will forward to it")
}

# ------------------------------------------------------------------ install --
if (-not (Test-Path -LiteralPath $OptiScalerDll)) { throw ("patched OptiScaler not found: " + $OptiScalerDll + "  (build it first: .\build_verify.ps1)") }
$exes = @(Get-ChildItem -LiteralPath $GameDir -Filter '*.exe' -File -ErrorAction SilentlyContinue)
$exes = @($exes | Where-Object { $_.Name -notmatch '^(vcredist|dxsetup|unins)' })
if ($exes.Count -eq 0) { throw ("no game executable in " + $GameDir + " -- refusing: this does not look like a game directory") }
if (Test-Path -LiteralPath $statePath) { throw "already installed here (a _p2_state.txt exists) -- run -Uninstall first" }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$bakDir = Join-Path $GameDir ('_p2backup_' + $stamp)
$srcSha = Get-Sha $OptiScalerDll

Write-Host ("game dir     : " + $GameDir)
Write-Host ("executables  : " + (($exes | Select-Object -First 4 | ForEach-Object { $_.Name }) -join ', '))
Write-Host ("proxy name   : " + $ProxyName)
Write-Host ("source build : " + $OptiScalerDll)
Write-Host ("source sha   : " + $srcSha)

if ($DryRun) { Write-Host "[dry] would back up and place the file; nothing written"; exit 0 }

$added = $false
$bakPath = ''
if (Test-Path -LiteralPath $slot) {
    New-Item -ItemType Directory -Force -Path $bakDir | Out-Null
    $bakPath = Join-Path $bakDir $ProxyName
    Copy-Item -LiteralPath $slot -Destination $bakPath -Force
    Write-Host ("[install] backed up existing " + $ProxyName + " -> " + $bakPath + "  sha256 " + (Get-Sha $bakPath))
} else {
    $added = $true
}
Copy-Item -LiteralPath $OptiScalerDll -Destination $slot -Force
if ((Get-Sha $slot) -ne $srcSha) { throw "post-copy hash mismatch -- install failed" }
Write-Host ("[install] placed " + $slot + "  sha256 " + $srcSha)

# OptiScaler reads OptiScaler.ini from next to itself. Only create one if the user has none:
# never overwrite their settings.
$iniDst = Join-Path $GameDir 'OptiScaler.ini'
$iniSrc = Join-Path (Split-Path $OptiScalerDll -Parent) 'OptiScaler.ini'
if ((-not (Test-Path -LiteralPath $iniDst)) -and (Test-Path -LiteralPath $iniSrc)) {
    Copy-Item -LiteralPath $iniSrc -Destination $iniDst -Force
    Write-Host ("[install] wrote a default OptiScaler.ini (none existed)")
} elseif (Test-Path -LiteralPath $iniDst) {
    Write-Host "[install] kept your existing OptiScaler.ini"
}

$state = @(('gameDir=' + $GameDir), ('proxy=' + $ProxyName), ('installedSha=' + $srcSha),
           ('backup=' + $bakPath), ('added=' + $(if ($added) { '1' } else { '' })), ('backupDir=' + $(if ($added) { '' } else { $bakDir })))
[System.IO.File]::WriteAllLines($statePath, $state)
Write-Host ("[install] state -> " + $statePath)
Write-Host ""
Write-Host "NEXT -- the deployment form matters, see p2\RUNBOOK_p2_host-run.md:"
Write-Host "  branch 1 (the app ALREADY creates feature 15): menu -> Advanced Settings ->"
Write-Host "           tick 'Latewarp: rewrite feature 15 params'   (ini: [Latewarp] Rewrite=true)"
Write-Host "  branch 2 (the app NEVER creates it):           FG Output = Reprojection +"
Write-Host "           tick 'Use NVIDIA latewarp (Reflex 2)'"
Write-Host "  Installed as nvngx.dll, the real core must sit beside it as _nvngx.dll"
Write-Host "  (install_latewarp_dll.ps1 places and verifies it)."
Write-Host "UNDO: .\install_p2_into_game.ps1 -GameDir <dir> -Uninstall"
