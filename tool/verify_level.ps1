# Magnet Rush — verify Level 1 can actually be played through.
#
# Deliberately does NOT screenshot while playing. Pulling a frame every cycle
# drops the emulator to ~2 FPS, so a "hold" delivers only a handful of
# simulation frames and the run stalls. Instead this drives the game with
# `adb input` only, reads progress from the `[state]` log line, and takes a
# single screenshot when the run reaches a terminal phase.
#
# Needs a build with --dart-define=MR_LOG_CAMERA=true (works in release).
#
#   powershell -File tool/verify_level.ps1 -OutPrefix docs/shots/08

param(
    [string]$Package = "ae.kanbanstudios.magnet_rush",
    [string]$OutPrefix = "docs/shots/08",
    [int]$MaxCycles = 40,
    [int]$HoldMs = 5000,
    [int]$GapMs = 700,
    [int]$HoldY = 1250
)

$ErrorActionPreference = "Continue"

function LastState {
    $line = (adb logcat -d -s flutter:I | Select-String "\[state\]" | Select-Object -Last 1)
    if ($null -eq $line) { return $null }
    return "$line"
}

function Shot($name) {
    adb shell screencap -p /sdcard/__v.png | Out-Null
    adb pull /sdcard/__v.png "$OutPrefix`_$name.png" | Out-Null
    adb shell rm -f /sdcard/__v.png | Out-Null
    Write-Output "  shot -> $OutPrefix`_$name.png"
}

adb shell am force-stop $Package | Out-Null
adb logcat -c | Out-Null
adb shell monkey -p $Package -c android.intent.category.LAUNCHER 1 | Out-Null
Start-Sleep -Seconds 12
adb shell input tap 540 1691 | Out-Null   # PLAY
Start-Sleep -Seconds 8

$wallCleared = $false
$sawArmour = $false
$sawBridge = $false
$sawKey = $false
$sawPortal = $false

for ($i = 1; $i -le $MaxCycles; $i++) {
    adb shell input swipe 540 $HoldY 540 $HoldY $HoldMs | Out-Null
    Start-Sleep -Milliseconds $GapMs

    $s = LastState
    if ($null -eq $s) { continue }

    if ($s -match "wallAlive=(\d+)/(\d+)") { $alive = [int]$Matches[1]; $total = [int]$Matches[2] }
    else { $alive = -1; $total = -1 }
    if ($s -match "coreZ=([\d\.\-]+)") { $z = $Matches[1] } else { $z = "?" }
    if ($s -match "phase=(\w+)") { $phase = $Matches[1] } else { $phase = "?" }
    if ($s -match "orbit=(\d+)") { $orbit = $Matches[1] } else { $orbit = "?" }

    Write-Output ("cycle {0,2}  z={1,-6} wall={2}/{3}  orbit={4,-3} phase={5}" -f $i, $z, $alive, $total, $orbit, $phase)

    if (-not $wallCleared -and $alive -eq 0 -and $total -gt 0) {
        $wallCleared = $true
        Write-Output "  *** WALL CLEARED ***"
        Shot "wall_cleared"
    }
    if (-not $sawArmour -and $s -match "armour=([1-9]\d*)") {
        $sawArmour = $true; Write-Output "  *** ARMOUR IN ORBIT ***"; Shot "armour"
    }
    if (-not $sawBridge -and $s -match "bridge=true") {
        $sawBridge = $true; Write-Output "  *** BRIDGE FORMED ***"; Shot "bridge"
    }
    if (-not $sawKey -and $s -match "key=true") {
        $sawKey = $true; Write-Output "  *** KEY COLLECTED ***"; Shot "key"
    }
    if (-not $sawPortal -and $s -match "portal=true") {
        $sawPortal = $true; Write-Output "  *** PORTAL UNLOCKED ***"; Shot "portal"
    }
    if ($phase -eq "complete") {
        Write-Output "  *** LEVEL COMPLETE ***"
        Start-Sleep -Seconds 3
        Shot "results"
        break
    }
    if ($phase -eq "failed") {
        Write-Output "  *** RUN FAILED ***"
        Start-Sleep -Seconds 2
        Shot "failure"
        break
    }
}

Write-Output ""
Write-Output "wallCleared=$wallCleared armour=$sawArmour bridge=$sawBridge key=$sawKey portal=$sawPortal"
LastState
