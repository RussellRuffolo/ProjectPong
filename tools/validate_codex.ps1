param(
	[string]$GodotExe = "",
	[string]$ProjectPath = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

if ($GodotExe -eq "") {
	$GodotExe = Join-Path $repoRoot "Godot_v4.7.1-stable_win64_console.exe"
}

if ($ProjectPath -eq "") {
	$ProjectPath = Join-Path $repoRoot "project-pong"
}

if (-not (Test-Path -LiteralPath $GodotExe)) {
	throw "Godot console executable not found: $GodotExe"
}

if (-not (Test-Path -LiteralPath (Join-Path $ProjectPath "project.godot"))) {
	throw "Godot project not found: $ProjectPath"
}

$logFile = Join-Path $repoRoot "codex-validation.log"

& $GodotExe `
	--headless `
	--xr-mode off `
	--path $ProjectPath `
	--log-file $logFile `
	--quit

exit $LASTEXITCODE
