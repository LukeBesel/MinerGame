<#
.SYNOPSIS
	build.ps1 - headless CI/local build pipeline for Bottleneck (Windows PowerShell equivalent
	of build.sh). Runs the full headless test suite first (aborts the build on red tests), then
	exports each requested platform preset via `godot --headless --export-release`, zipping each
	output. Gracefully skips the export step (exit 0, clear message) when export templates are
	not installed -- the test gate above still ran either way. See docs/ARCHITECTURE.md §9/§10.

.PARAMETER Targets
	Platform keys to export: windows, linux, macos, web. Omit for all four.

.EXAMPLE
	./build.ps1
	./build.ps1 windows web
#>

param(
	[Parameter(ValueFromRemainingArguments = $true)]
	[string[]]$Targets = @()
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $RootDir

$GodotBin = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { "godot" }
$BuildsDir = Join-Path $RootDir "builds"
$TemplatesDir = Join-Path $env:APPDATA "Godot\export_templates"

$Presets = [ordered]@{
	"windows" = @{ Preset = "Windows Desktop"; Subdir = "windows"; File = "bottleneck.exe";     Zip = "bottleneck-windows.zip" }
	"linux"   = @{ Preset = "Linux";           Subdir = "linux";   File = "bottleneck.x86_64";  Zip = "bottleneck-linux.zip" }
	"macos"   = @{ Preset = "macOS";           Subdir = "macos";   File = "Bottleneck.app";     Zip = "bottleneck-macos.zip" }
	"web"     = @{ Preset = "Web";             Subdir = "web";     File = "index.html";         Zip = "bottleneck-web.zip" }
}

function Write-BuildLog([string]$Message) {
	Write-Host "[build.ps1] $Message"
}

function Invoke-Tests {
	Write-BuildLog "Running headless test suite..."
	& $GodotBin --headless --path $RootDir -s res://tests/run_tests.gd
	if ($LASTEXITCODE -ne 0) {
		Write-BuildLog "Tests FAILED -- aborting build."
		exit 1
	}
	Write-BuildLog "Tests passed."
}

function Test-TemplatesInstalled {
	if (-not (Test-Path $TemplatesDir)) { return $false }
	$children = Get-ChildItem -Path $TemplatesDir -Force -ErrorAction SilentlyContinue
	return ($null -ne $children) -and ($children.Count -gt 0)
}

function Export-One([string]$Key) {
	$cfg = $Presets[$Key]
	$outDir = Join-Path $BuildsDir $cfg.Subdir
	New-Item -ItemType Directory -Force -Path $outDir | Out-Null
	$exportPath = Join-Path $outDir $cfg.File

	Write-BuildLog "Exporting '$($cfg.Preset)' -> $exportPath"
	& $GodotBin --headless --path $RootDir --export-release $cfg.Preset $exportPath
	if ($LASTEXITCODE -ne 0) {
		Write-BuildLog "Export FAILED for '$($cfg.Preset)' -- see Godot output above."
		return $false
	}

	$zipPath = Join-Path $BuildsDir $cfg.Zip
	Write-BuildLog "Zipping $($cfg.Subdir)\ -> $zipPath"
	if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
	Compress-Archive -Path (Join-Path $outDir "*") -DestinationPath $zipPath
	Write-BuildLog "Done: $zipPath"
	return $true
}

function Main {
	Invoke-Tests

	if (-not (Test-TemplatesInstalled)) {
		Write-BuildLog "No Godot export templates found under $TemplatesDir --"
		Write-BuildLog "skipping platform exports (tests above already ran and gate the build)."
		Write-BuildLog "Install export templates (Editor > Manage Export Templates, or download"
		Write-BuildLog "Godot_v4.5-stable_export_templates.tpz and extract to"
		Write-BuildLog "$TemplatesDir\4.5.stable\) and re-run to produce builds\."
		exit 0
	}

	New-Item -ItemType Directory -Force -Path $BuildsDir | Out-Null

	$runTargets = $Targets
	if ($runTargets.Count -eq 0) {
		$runTargets = @("windows", "linux", "macos", "web")
	}

	$failures = 0
	foreach ($t in $runTargets) {
		if (-not $Presets.Contains($t)) {
			Write-BuildLog "Unknown target '$t' -- expected one of: $($Presets.Keys -join ', ')"
			$failures++
			continue
		}
		if (-not (Export-One $t)) {
			$failures++
		}
	}

	if ($failures -gt 0) {
		Write-BuildLog "$failures export(s) failed."
		exit 1
	}
	Write-BuildLog "All exports complete: $BuildsDir"
}

Main
