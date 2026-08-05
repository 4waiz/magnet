# Magnet Rush — scripted Level 1 playthrough.
#
# Drives the one-finger control with adb: repeated hold/release cycles long
# enough to build a swarm and fire it, capturing a frame after each cycle.
# Used to reach and photograph the later encounters (wall, armour, hazard,
# bridge, key, portal) without a human on the device.

param(
    [string]$Package = "ae.kanbanstudios.magnet_rush",
    [string]$OutDir = "docs/shots/play",
    [int]$Cycles = 14,
    [int]$HoldMs = 2600,
    # Hold high on the screen: the results and failure overlays put their
    # buttons in the lower third, and a blind hold there dismisses the very
    # screen the run is trying to photograph.
    [int]$HoldY = 900
)

$ErrorActionPreference = "Continue"
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

adb shell am force-stop $Package | Out-Null
adb shell monkey -p $Package -c android.intent.category.LAUNCHER 1 | Out-Null
Start-Sleep -Seconds 11
adb shell input tap 540 1691 | Out-Null   # PLAY
Start-Sleep -Seconds 7

for ($i = 1; $i -le $Cycles; $i++) {
    $job = Start-Job -ScriptBlock {
        param($y, $d)
        adb shell input swipe 540 $y 540 $y $d
    } -ArgumentList $HoldY, $HoldMs

    # Shoot mid-hold (swarm at its largest for this cycle).
    Start-Sleep -Milliseconds ($HoldMs - 500)
    adb shell screencap -p /sdcard/__p.png | Out-Null
    adb pull /sdcard/__p.png "$OutDir/cycle-$('{0:d2}' -f $i)-hold.png" | Out-Null

    Wait-Job $job | Out-Null
    Remove-Job $job

    # Shoot just after release (blast + destruction).
    Start-Sleep -Milliseconds 350
    adb shell screencap -p /sdcard/__p.png | Out-Null
    adb pull /sdcard/__p.png "$OutDir/cycle-$('{0:d2}' -f $i)-blast.png" | Out-Null

    Start-Sleep -Milliseconds 900
}

adb shell rm -f /sdcard/__p.png | Out-Null
Write-Output "playthrough complete: $Cycles cycles -> $OutDir"
