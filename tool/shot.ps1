# Magnet Rush — runtime screenshot helper.
#
# Verifies the app under test is actually in the foreground before capturing,
# so a screenshot can never be mistaken for another app on the same emulator.
#
#   powershell -File tool/shot.ps1 -Out docs/shots/01_level1.png [-Hold 3]

param(
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$Package = "ae.kanbanstudios.magnet_rush",
    [double]$Hold = 0,
    [int]$SettleSeconds = 3
)

$ErrorActionPreference = "Stop"

Start-Sleep -Seconds $SettleSeconds

$fg = (adb shell dumpsys activity activities | Select-String -Pattern "topResumedActivity") -join ""
if ($fg -notmatch [regex]::Escape($Package)) {
    Write-Error "FOREGROUND MISMATCH - expected '$Package'. Got: $fg"
    exit 2
}

if ($Hold -gt 0) {
    # Long-press the middle of the screen to drive hold-to-attract, then shoot
    # while the finger is still down.
    $size = (adb shell wm size) -replace '.*:\s*', ''
    $w, $h = $size.Trim() -split 'x'
    $cx = [int]([int]$w / 2)
    $cy = [int]([int]$h * 0.62)
    $ms = [int]($Hold * 1000)
    Start-Job -ScriptBlock {
        param($x, $y, $d)
        adb shell input swipe $x $y $x $y $d
    } -ArgumentList $cx, $cy, $ms | Out-Null
    Start-Sleep -Milliseconds ([int]($ms * 0.75))
}

$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

# NOTE: no `2>&1` on adb — Windows PowerShell 5.1 wraps native stderr in
# ErrorRecords and reports failure even on exit code 0.
$ErrorActionPreference = "Continue"
adb shell screencap -p /sdcard/__mr_shot.png | Out-Null
adb pull /sdcard/__mr_shot.png $Out | Out-Null
adb shell rm -f /sdcard/__mr_shot.png | Out-Null
$ErrorActionPreference = "Stop"

if (Test-Path $Out) {
    Write-Output "OK $Out ($((Get-Item $Out).Length) bytes) fg=$Package"
} else {
    Write-Error "capture failed"
    exit 3
}
