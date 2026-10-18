<#
.SYNOPSIS
  Quiet picture run (card #168): starts the game in a window that never takes keyboard or mouse
  focus, on the second screen if there is one, with no sound. For test runs a person is not
  watching (--shots, --autoplay ...) while the owner plays something else.

.DESCRIPTION
  Godot's "no focus" window flag (project setting display/window/size/no_focus) can only be set
  before the window is created, and it cannot be given on the command line. So this script builds
  a SHADOW PROJECT next to nothing the owner uses: a folder under %LOCALAPPDATA%\Rotsworn-quiet
  whose project.godot is a copy with no_focus switched on and the window mode set to windowed, and
  whose other entries are folder links (junctions) to the real project's folders. Godot is started
  with --path pointing at that shadow. The real project folder is never edited, so a normal run
  (run_game.bat, the editor) can never pick the setting up, even while a quiet run is going.

  Everything after the options goes to the game as its own switches, so
    tools\quiet_run.bat --shots=2 --screen=menu
  is the same as `run_game.bat -- --shots=2 --screen=menu` but quiet. Saves, settings and the
  shots folder are the same ones a normal run uses (the game name is the same).

.PARAMETER Size
  Window size as WxH (default 1920x1080, made smaller to fit the chosen screen).
.PARAMETER Headless
  No window at all (still through the shadow project). For checking the launcher itself.
.PARAMETER DryRun
  Print what would happen (screens, chosen place, command) and change nothing.
.PARAMETER PrepareOnly
  Build the shadow project, print its path, and do not start the game.
.PARAMETER NoImport
  Skip the asset import step that run_game.bat also does first.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
	[string]$Size = "1920x1080",
	[switch]$Headless,
	[switch]$DryRun,
	[switch]$PrepareOnly,
	[switch]$NoImport,
	[Parameter(ValueFromRemainingArguments = $true)][string[]]$GameArgs
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if (-not ("QuietNative" -as [type])) {
	Add-Type -TypeDefinition (Get-Content -Raw -Path (Join-Path $PSScriptRoot "quiet\QuietNative.cs"))
}
[QuietNative]::MakeDpiAware()

$godot = $env:GODOT
if (-not $godot) { $godot = "C:\Users\Drago\Godot\Godot_v4.7.2-stable_win64_console.exe" }

# ---- where the window goes -------------------------------------------------------------------
# A second screen if there is one (the first that is not the main one), else the main screen.
$monitors = @([QuietNative]::Monitors())
$target = $null
foreach ($m in $monitors) { if ($m[8] -eq 0) { $target = $m; break } }
$onSecond = $true
if ($null -eq $target) {
	$onSecond = $false
	foreach ($m in $monitors) { if ($m[8] -eq 1) { $target = $m; break } }
}
if ($null -eq $target -and $monitors.Count -gt 0) { $target = $monitors[0] }
$width = 1920; $height = 1080
if ($Size -match '^(\d+)x(\d+)$') { $width = [int]$Matches[1]; $height = [int]$Matches[2] }
$posX = 0; $posY = 0
if ($null -ne $target) {
	$workW = $target[6] - $target[4]
	$workH = $target[7] - $target[5]
	# Keep the 16:9 shape; leave room for the title bar and the taskbar, and a margin all round:
	# a window as wide as the screen pokes its border past the edge, and Windows then moves it
	# back onto the main screen (seen on the owner's PC).
	$margin = 64
	$scale = [Math]::Min(1.0, [Math]::Min(($workW - 2 * $margin) / $width, ($workH - 2 * $margin - 60) / $height))
	$width = [int]($width * $scale)
	$height = [int]($height * $scale)
	$posX = $target[4] + [int](($workW - $width) / 2)
	$posY = $target[5] + [int](($workH - $height) / 2)
}

# ---- the shadow project ----------------------------------------------------------------------
$md5 = [System.Security.Cryptography.MD5]::Create()
$hash = [BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant()))).Replace("-", "").Substring(0, 8).ToLowerInvariant()
$shadow = Join-Path $env:LOCALAPPDATA ("Rotsworn-quiet\" + (Split-Path -Leaf $root) + "-" + $hash)
$skipNames = @(".git", ".github", ".githooks", ".claude", "build", "test_results", "project.godot")

## Sets key=value inside [section] of a Godot config text (replaces the key or adds it).
function Set-ConfigValue([string[]]$lines, [string]$section, [string]$key, [string]$value) {
	$out = New-Object System.Collections.Generic.List[string]
	$inSection = $false; $done = $false; $sawSection = $false
	foreach ($line in $lines) {
		if ($line -match '^\[(.+)\]\s*$') {
			if ($inSection -and -not $done) { $out.Add("$key=$value"); $out.Add(""); $done = $true }
			$inSection = ($Matches[1] -eq $section)
			if ($inSection) { $sawSection = $true }
			$out.Add($line)
			continue
		}
		if ($inSection -and $line.StartsWith("$key=")) {
			if (-not $done) { $out.Add("$key=$value"); $done = $true }
			continue
		}
		$out.Add($line)
	}
	if (-not $done) {
		if (-not $sawSection) { $out.Add("[$section]"); $out.Add("") }
		$out.Add("$key=$value")
	}
	return $out.ToArray()
}

## The project.godot of the shadow project: the real one plus the quiet window settings.
function Get-QuietProjectText() {
	$text = [IO.File]::ReadAllText((Join-Path $root "project.godot"), [Text.Encoding]::UTF8)
	$lines = $text -split "`r?`n"
	$lines = Set-ConfigValue $lines "display" "window/size/no_focus" "true"
	$lines = Set-ConfigValue $lines "display" "window/size/mode" "0"
	# The place and size also go into the project itself: on the owner's PC the --position switch
	# alone left the window on the main screen (Godot's default "centre of the primary screen").
	$lines = Set-ConfigValue $lines "display" "window/size/initial_position_type" "0"
	$lines = Set-ConfigValue $lines "display" "window/size/initial_position" "Vector2i($posX, $posY)"
	$lines = Set-ConfigValue $lines "display" "window/size/window_width_override" "$width"
	$lines = Set-ConfigValue $lines "display" "window/size/window_height_override" "$height"
	return ($lines -join "`n")
}

## Empties the shadow folder. Folder links are removed as links (rmdir), never followed.
function Clear-Shadow() {
	foreach ($item in Get-ChildItem -Force -LiteralPath $shadow) {
		if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
			& cmd.exe /c rmdir "$($item.FullName)" | Out-Null
		} elseif ($item.PSIsContainer) {
			throw "Unexpected real folder in the shadow project: $($item.FullName). Delete it by hand."
		} else {
			Remove-Item -Force -LiteralPath $item.FullName
		}
	}
}

function Build-Shadow() {
	New-Item -ItemType Directory -Force -Path $shadow | Out-Null
	Clear-Shadow
	foreach ($item in Get-ChildItem -Force -LiteralPath $root) {
		if ($skipNames -contains $item.Name) { continue }
		$link = Join-Path $shadow $item.Name
		if ($item.PSIsContainer) {
			New-Item -ItemType Junction -Path $link -Target $item.FullName | Out-Null
		} else {
			Copy-Item -LiteralPath $item.FullName -Destination $link
		}
	}
	[IO.File]::WriteAllText((Join-Path $shadow "project.godot"), (Get-QuietProjectText), (New-Object Text.UTF8Encoding($false)))
}

# ---- the command -----------------------------------------------------------------------------
$engineArgs = @("--path", $shadow)
if ($Headless) {
	$engineArgs += "--headless"
} else {
	# --audio-driver Dummy: a test run makes no sound for whoever is playing next to it.
	$engineArgs += @("--windowed", "--resolution", "${width}x${height}", "--position", "$posX,$posY", "--audio-driver", "Dummy")
}
if ($GameArgs -and $GameArgs.Count -gt 0) { $engineArgs += "--"; $engineArgs += $GameArgs }

function Join-Args([string[]]$list) {
	return ($list | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join " "
}

Write-Host "Quiet run: screens found = $($monitors.Count); window on the $(if ($onSecond) { 'SECOND screen' } else { 'only screen (sent behind other windows)' }) at $posX,$posY, ${width}x${height}"
Write-Host "Shadow project: $shadow"
Write-Host "Command: $godot $(Join-Args $engineArgs)"
if ($DryRun) { exit 0 }

if (-not $NoImport) {
	# Like run_game.bat: new or changed art and sounds are imported into the real project first.
	& $godot --headless --path $root --import 2>&1 | Out-Null
}
Build-Shadow
if ($PrepareOnly) { exit 0 }

$proc = Start-Process -FilePath $godot -ArgumentList (Join-Args $engineArgs) -NoNewWindow -PassThru
$null = $proc.Handle
if ($Headless) {
	$proc.WaitForExit()
	exit $proc.ExitCode
}
if ($onSecond) {
	# Godot opens the window at the main screen's corner whatever --position says (seen on the
	# owner's PC), so the launcher moves it to the second screen itself, without activating it,
	# as soon as it shows and for the next few seconds (in case the game places it again).
	$started = Get-Date
	while (-not $proc.HasExited -and ((Get-Date) - $started).TotalSeconds -lt 15) {
		$pids = @($proc.Id)
		foreach ($child in Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.Id)") { $pids += [uint32]$child.ProcessId }
		foreach ($w in [QuietNative]::WindowsOf([uint32[]]$pids)) {
			if ($w[1] -ne $posX -or $w[2] -ne $posY) { [void][QuietNative]::MoveTo($w[0], $posX, $posY) }
		}
		Start-Sleep -Milliseconds 250
	}
	$proc.WaitForExit()
	exit $proc.ExitCode
}
# Only one screen: the window cannot hide on another one, so push it to the bottom of the window
# stack (no activation) for the first half minute. It never had focus; this stops it covering
# whatever the owner is playing.
$started = Get-Date
while (-not $proc.HasExited) {
	if (((Get-Date) - $started).TotalSeconds -lt 30) {
		$pids = @($proc.Id)
		foreach ($child in Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.Id)") { $pids += [uint32]$child.ProcessId }
		foreach ($w in [QuietNative]::WindowsOf([uint32[]]$pids)) { [void][QuietNative]::SendBehind($w[0]) }
	}
	Start-Sleep -Milliseconds 500
}
$proc.WaitForExit()
exit $proc.ExitCode
