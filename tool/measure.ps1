# Magnet Rush — on-device performance capture.
#
# Drives Level 1 with adb input, holding to build the swarm to a series of
# targets, and screenshots the frame-time overlay at each one. The overlay is
# fed by Flutter's own SchedulerBinding timings (build + raster), which is the
# number that decides whether a frame was delivered on time.
#
# Requires the build to have been made with --dart-define=MR_STATS=true.
#
#   powershell -File tool/measure.ps1 -Label release-gles

param(
    [string]$Package = "ae.kanbanstudios.magnet_rush",
    [string]$Label = "run",
    [string]$OutDir = "docs/shots/perf",
    [int[]]$HoldSeconds = @(2, 4, 7, 11)
)

$ErrorActionPreference = "Continue"
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

function Mem($tag) {
    $m = (adb shell dumpsys meminfo $Package | Select-String "TOTAL PSS") -join ""
    if ($m -match "TOTAL PSS:\s+(\d+)") { $v = [int]$Matches[1] } else { $v = -1 }
    Write-Output ("MEM {0,-22} {1} kB" -f $tag, $v)
    return $v
}

function Shot($name) {
    adb shell screencap -p /sdcard/__m.png | Out-Null
    adb pull /sdcard/__m.png "$OutDir/$name.png" | Out-Null
    adb shell rm -f /sdcard/__m.png | Out-Null
}

adb shell am force-stop $Package | Out-Null
adb shell monkey -p $Package -c android.intent.category.LAUNCHER 1 | Out-Null
Start-Sleep -Seconds 10
Mem "$Label.home" | Out-Null

# Enter Level 1.
adb shell input tap 540 1691 | Out-Null
Start-Sleep -Seconds 8
Mem "$Label.level-loaded" | Out-Null
Shot "$Label-00-loaded"

foreach ($h in $HoldSeconds) {
    $job = Start-Job -ScriptBlock {
        param($d)
        adb shell input swipe 540 1500 540 1500 $d
    } -ArgumentList ($h * 1000)
    Start-Sleep -Seconds ([Math]::Max(1, $h - 1))
    Shot "$Label-hold-$h`s"
    Mem "$Label.hold-$h`s" | Out-Null
    Wait-Job $job | Out-Null
    Remove-Job $job
    Start-Sleep -Milliseconds 500
    Shot "$Label-release-after-$h`s"
    Start-Sleep -Seconds 2
}

Mem "$Label.peak" | Out-Null

# Five consecutive retries via the pause menu, to test reset cost and leaks.
for ($i = 1; $i -le 5; $i++) {
    adb shell input tap 63 155 | Out-Null      # pause
    Start-Sleep -Milliseconds 900
    adb shell input tap 270 1800 | Out-Null    # RETRY
    Start-Sleep -Seconds 2
}
Mem "$Label.after-5-retries" | Out-Null
Shot "$Label-after-retries"
Write-Output "DONE $Label"
