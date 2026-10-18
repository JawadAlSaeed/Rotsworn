<#
.SYNOPSIS
  Checks that a quiet run (quiet_run.bat, card #168) never takes keyboard focus and opens on the
  right screen. Opens a REAL game window, so run it only when the PC owner agrees.

.DESCRIPTION
  1. Remembers which window has focus now (GetForegroundWindow).
  2. Starts the quiet launcher hidden, with the game switches you give it (default: a title
     screen picture run).
  3. Every 100 ms for -Seconds, checks that the focused window does not belong to the game, and
     every second notes where the game's window is.
  4. Stops the game and prints PASS or FAIL (and INCONCLUSIVE if the game never showed a window).

  While it runs, keep working in another window (type in Notepad, click around): the test is that
  your typing keeps going to that window. Do not click the game window.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\quiet_focus_check.ps1 -Seconds 20 --shots=2 --screen=menu
#>
[CmdletBinding(PositionalBinding = $false)]
param(
	[int]$Seconds = 20,
	[Parameter(ValueFromRemainingArguments = $true)][string[]]$GameArgs
)

$ErrorActionPreference = "Stop"
if (-not ("QuietNative" -as [type])) {
	Add-Type -TypeDefinition (Get-Content -Raw -Path (Join-Path $PSScriptRoot "quiet\QuietNative.cs"))
}
[QuietNative]::MakeDpiAware()
if (-not $GameArgs -or $GameArgs.Count -eq 0) { $GameArgs = @("--shots=2", "--screen=title") }

function Get-GodotPids() {
	$ids = @()
	foreach ($p in Get-CimInstance Win32_Process -Filter "Name like 'Godot%'") {
		if ($p.CommandLine -like "*Rotsworn-quiet*") { $ids += [uint32]$p.ProcessId }
	}
	return $ids
}

$monitors = @([QuietNative]::Monitors())
Write-Host "Screens: $($monitors.Count)"
for ($i = 0; $i -lt $monitors.Count; $i++) {
	$m = $monitors[$i]
	Write-Host ("  screen {0}: {1},{2} to {3},{4}{5}" -f $i, $m[0], $m[1], $m[2], $m[3], $(if ($m[8] -eq 1) { "  (main)" } else { "" }))
}
$before = [QuietNative]::ForegroundDescription()
Write-Host "Focus before: $before"

$log = Join-Path $env:TEMP "quiet_focus_check.log"
$launcher = Join-Path $PSScriptRoot "quiet_run.ps1"
$argText = "-NoProfile -ExecutionPolicy Bypass -File `"$launcher`" " + (($GameArgs | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join " ")
$host_ = Start-Process -FilePath "powershell" -ArgumentList $argText -WindowStyle Hidden -PassThru -RedirectStandardOutput $log

$stolen = 0
$seenWindow = $false
$lastNote = ""
$ticks = $Seconds * 10
$godotPids = @()
for ($t = 0; $t -lt $ticks; $t++) {
	if ($t % 10 -eq 0) {
		$godotPids = @(Get-GodotPids)
		if ($godotPids.Count -gt 0) {
			foreach ($w in [QuietNative]::WindowsOf([uint32[]]$godotPids)) {
				$seenWindow = $true
				$cx = ($w[1] + $w[3]) / 2; $cy = ($w[2] + $w[4]) / 2
				$where = "off all screens"
				for ($i = 0; $i -lt $monitors.Count; $i++) {
					$m = $monitors[$i]
					if ($cx -ge $m[0] -and $cx -lt $m[2] -and $cy -ge $m[1] -and $cy -lt $m[3]) { $where = "screen $i" + $(if ($m[8] -eq 1) { " (main)" } else { " (not the main one)" }) }
				}
				$note = "Game window at {0},{1} size {2}x{3} on {4}" -f $w[1], $w[2], ($w[3] - $w[1]), ($w[4] - $w[2]), $where
				if ($note -ne $lastNote) { Write-Host $note; $lastNote = $note }
			}
		}
	}
	$fg = [QuietNative]::ForegroundPid()
	if ($fg -ne 0 -and ($godotPids -contains [uint32]$fg)) {
		$stolen++
		if ($stolen -eq 1) { Write-Host "FOCUS TAKEN by the game at $($t / 10) s: $([QuietNative]::ForegroundDescription())" }
	}
	Start-Sleep -Milliseconds 100
}

$after = [QuietNative]::ForegroundDescription()
Write-Host "Focus after: $after"
foreach ($id in (Get-GodotPids)) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
if (-not $host_.HasExited) { Stop-Process -Id $host_.Id -Force -ErrorAction SilentlyContinue }
Write-Host "Launcher log: $log"

if (-not $seenWindow) {
	Write-Host "INCONCLUSIVE: the game never showed a window (see the log)."
	exit 2
}
if ($stolen -gt 0) {
	Write-Host "FAIL: the game's window had keyboard focus in $stolen of $ticks checks."
	exit 1
}
Write-Host "PASS: the game's window never had keyboard focus during $Seconds s."
if ($before -ne $after) { Write-Host "(The focused window changed anyway: that was you or another program, not the game.)" }
exit 0
