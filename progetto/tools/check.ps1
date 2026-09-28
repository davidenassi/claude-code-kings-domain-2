<#
.SYNOPSIS
  King's Domain project check: import, headless tests, optional screenshots.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\check.ps1
  powershell -ExecutionPolicy Bypass -File tools\check.ps1 -Screenshot -Camera "56000,36000,40"
#>
param(
    [switch]$SkipImport,
    [switch]$SkipTests,
    [switch]$Screenshot,
    [string]$Camera = "",
    [string]$ShotName = "main",
    [string]$TestFilter = "",
    [int]$Frames = 45,
    [string]$ExtraArgs = "",
    [string]$EngineArgs = "",
    [int]$TimeoutSec = 900
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Godot = $env:KD_GODOT
if (-not $Godot) { $Godot = "C:\Users\ciabe\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" }
if (-not (Test-Path $Godot)) { Write-Error "Godot not found: $Godot (set KD_GODOT)"; exit 2 }

$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$failed = $false

function Invoke-Godot([string[]]$GodotArgs, [string]$LogFile) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Godot
    $psi.Arguments = ($GodotArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = $Root
    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEndAsync()
    $stderr = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch {}
        Write-Host "TIMEOUT after $TimeoutSec s: $LogFile"
    }
    $text = $stdout.Result + "`n" + $stderr.Result
    Set-Content -Path $LogFile -Value $text -Encoding utf8
    return @{ Code = $p.ExitCode; Text = $text }
}

# Any line of the engine that says ERROR fails the check (Phase 19: "ERROR: Invalid polygon data" from a draw call
# had no res:// on its line and a run passed with it), except the ones the tests provoke on purpose to see that
# bad input is refused: those are listed here, one by one.
$ExpectedTestErrors = @(
    'SaveMigrator: missing save_version',
    'SaveMigrator: save_version \d+ is newer than the game',
    'Scheduler: duplicate system id dup',
    'SaveSystem: corrupted save user://tests/broken\.kds',
    'SaveSystem: cannot open user://tests/broken\.kds'
)

function Find-ScriptErrors([string]$Text, [string[]]$Expected = @()) {
    $patterns = @('SCRIPT ERROR', 'Parse Error', 'Failed to load script', 'Compile Error', 'Invalid call', 'Cannot infer', 'Identifier .* not declared', '^\s*ERROR:')
    $hits = @()
    foreach ($line in ($Text -split "`n")) {
        foreach ($pat in $patterns) {
            if ($line -match $pat) {
                $known = $false
                foreach ($e in $Expected) { if ($line -match $e) { $known = $true; break } }
                if (-not $known) { $hits += $line.Trim() }
                break
            }
        }
    }
    return $hits
}

if (-not $SkipImport) {
    Write-Host "== Import ==" -ForegroundColor Cyan
    $r = Invoke-Godot @('--headless', '--path', $Root, '--import') (Join-Path $LogDir "import.log")
    $errs = Find-ScriptErrors $r.Text
    if ($errs.Count -gt 0) { $errs | ForEach-Object { Write-Host $_ -ForegroundColor Red }; $failed = $true }
    else { Write-Host "import ok (exit $($r.Code))" -ForegroundColor Green }
}

if (-not $SkipTests) {
    Write-Host "== Tests ==" -ForegroundColor Cyan
    $targs = @('--headless', '--path', $Root, 'res://tests/test_runner.tscn')
    if ($TestFilter) { $targs += @('--', "--kd-test=$TestFilter") }
    $r = Invoke-Godot $targs (Join-Path $LogDir "tests.log")
    ($r.Text -split "`n") | Where-Object { $_ -match '^\[(ok|FAIL)\]|^FAILURE|^TESTS:' } | ForEach-Object {
        if ($_ -match 'FAIL') { Write-Host $_ -ForegroundColor Red } else { Write-Host $_ }
    }
    $errs = Find-ScriptErrors $r.Text $ExpectedTestErrors
    if ($errs.Count -gt 0) { $errs | ForEach-Object { Write-Host $_ -ForegroundColor Red }; $failed = $true }
    if ($r.Code -ne 0) { Write-Host "tests failed (exit $($r.Code))" -ForegroundColor Red; $failed = $true }
    else { Write-Host "tests ok" -ForegroundColor Green }
}

if ($Screenshot) {
    Write-Host "== Screenshot ==" -ForegroundColor Cyan
    $shot = "tests/output/$ShotName.png"
    $sargs = @('--path', $Root)
    if ($EngineArgs) { $sargs += ($EngineArgs -split ' ') }   # before '--': engine options such as --resolution
    $sargs += @('--', "--kd-screenshot=$shot", "--kd-frames=$Frames")
    if ($Camera) { $sargs += "--kd-camera=$Camera" }
    if ($ExtraArgs) { $sargs += ($ExtraArgs -split ' ') }
    $r = Invoke-Godot $sargs (Join-Path $LogDir "screenshot_$ShotName.log")
    $errs = Find-ScriptErrors $r.Text
    if ($errs.Count -gt 0) { $errs | ForEach-Object { Write-Host $_ -ForegroundColor Red }; $failed = $true }
    Write-Host "screenshot -> $shot (exit $($r.Code))"
}

if ($failed) { Write-Host "CHECK FAILED" -ForegroundColor Red; exit 1 }
Write-Host "CHECK PASSED" -ForegroundColor Green
exit 0

