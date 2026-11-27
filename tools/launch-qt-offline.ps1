[CmdletBinding()]
param(
    [switch]$VerifyOnly,
    [switch]$OpenTuning,
    [switch]$ModalDesigner,
    [string]$ModalCapturePath,
    [string]$ProductionCapturePath
)

$ErrorActionPreference = 'Stop'
if ($OpenTuning -and $ModalDesigner) { throw 'Choose the production tuning panel or Modal Designer, not both.' }
if ($ModalCapturePath -and (-not $ModalDesigner -or $VerifyOnly)) {
    throw 'ModalCapturePath requires ModalDesigner and an actual launch.'
}
if ($ModalCapturePath) {
    $ModalCapturePath = [IO.Path]::GetFullPath($ModalCapturePath)
    if (-not (Test-Path -LiteralPath (Split-Path -Parent $ModalCapturePath) -PathType Container)) {
        throw 'Modal capture directory must already exist.'
    }
    if (Test-Path -LiteralPath $ModalCapturePath) {
        throw 'Modal capture path already exists; choose a fresh filename.'
    }
}
if ($ProductionCapturePath -and (-not $OpenTuning -or $ModalDesigner -or $VerifyOnly)) {
    throw 'ProductionCapturePath requires OpenTuning and an actual production launch.'
}
if ($ProductionCapturePath) {
    $ProductionCapturePath = [IO.Path]::GetFullPath($ProductionCapturePath)
    if (-not (Test-Path -LiteralPath (Split-Path -Parent $ProductionCapturePath) -PathType Container)) {
        throw 'Production capture directory must already exist.'
    }
    if (Test-Path -LiteralPath $ProductionCapturePath) {
        throw 'Production capture path already exists; choose a fresh filename.'
    }
}
$qtRoot = Split-Path -Parent $PSScriptRoot
$build = Join-Path $qtRoot 'build-fileio'
$exe = Join-Path $build 'prototype.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw "Missing rebuilt app: $exe" }
$cache = Get-Content -LiteralPath (Join-Path $build 'CMakeCache.txt')
$prefix = ($cache | Where-Object { $_ -match '^CMAKE_PREFIX_PATH:.*=' } | Select-Object -First 1) -replace '^[^=]*=', ''
$compiler = ($cache | Where-Object { $_ -match '^CMAKE_CXX_COMPILER:.*=' } | Select-Object -First 1) -replace '^[^=]*=', ''
$qtBin = Join-Path ($prefix -split ';')[0] 'bin'
if (-not (Test-Path -LiteralPath (Join-Path $qtBin 'Qt6Core.dll'))) { throw 'Active Qt runtime cannot be resolved from CMakeCache.txt' }
if (-not (Test-Path -LiteralPath $compiler)) { throw 'Active compiler runtime cannot be resolved from CMakeCache.txt' }
$env:PATH = "$qtBin;$(Split-Path -Parent $compiler);$env:PATH"
$env:QML_XHR_ALLOW_FILE_READ = '1'

# Never infer safety from substrings in another process's raw command line.
# Existing instances must be closed explicitly; this launcher never kills them.
if (-not $VerifyOnly) {
    $existing = @(Get-CimInstance Win32_Process -Filter "Name='prototype.exe'" | Where-Object {
        $_.ExecutablePath -and [StringComparer]::OrdinalIgnoreCase.Equals(
            [IO.Path]::GetFullPath($_.ExecutablePath), [IO.Path]::GetFullPath($exe))
    })
    if ($existing.Count) { throw 'Close the existing Qt app safely before launching; no process was stopped.' }
}

# Deny writes/deletion from before verification until the launched GUI exits.
# A concurrent shared-worktree linker cannot replace the verified executable.
$imageLock = [IO.File]::Open($exe, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
try {
    # An old binary that ignores the new flag cannot pass by exiting normally.
    $attempt = Join-Path $build ('launch-thc-check-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $attempt | Out-Null
    $stdout = Join-Path $attempt 'stdout.txt'
    $stderr = Join-Path $attempt 'stderr.txt'
    $hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
    $oldPlatform = $env:QT_QPA_PLATFORM
    $oldStderr = $env:QT_FORCE_STDERR_LOGGING
    try {
        $env:QT_QPA_PLATFORM = 'offscreen'
        $env:QT_FORCE_STDERR_LOGGING = '1'
        $check = Start-Process -FilePath $exe -WorkingDirectory $build -PassThru `
            -ArgumentList @('--offline-validation', '--verify-thc-live-integration', '--tab=4', '--run-exit-after-ms=10000') `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        # Windows PowerShell 5.1 must retain the native handle before the child
        # exits; otherwise Start-Process can expose a null ExitCode after Wait.
        $null = $check.Handle
        if (-not $check.WaitForExit(15000)) {
            $check.Kill()
            $check.WaitForExit()
            throw "Offline integration check timed out. Logs: $attempt"
        }
        $check.Refresh()
        $output = (Get-Content -LiteralPath $stdout,$stderr -Raw) -join "`n"
        if ($check.ExitCode -ne 0 -or $output -notmatch 'THC-LIVE-INTEGRATION PASS' `
            -or $output -match 'THC-LIVE-INTEGRATION FAIL') {
            throw "Refusing app without verified V53 integration. Rebuild current source. Logs: $attempt"
        }
    } finally {
        $env:QT_QPA_PLATFORM = $oldPlatform
        $env:QT_FORCE_STDERR_LOGGING = $oldStderr
    }
    Write-Output "Verified V53 packaged UI/native API (offline only). SHA256=$hash Logs=$attempt"
    if ($VerifyOnly) { return }
    $arguments = @('--offline-validation')
    if ($ModalDesigner) {
        $arguments += @('--modal-preview', '--modal-preview-version=v5-gemini-precision',
            '--modal-preview-selection=THC_LIVE_TUNING')
        if ($ModalCapturePath) {
            $arguments += '--modal-preview-capture=' + [IO.Path]::GetFullPath($ModalCapturePath)
        }
    } else {
        # Manual/tuning tab only when the tuning panel is requested; normal
        # launches open on the default RUN view.
        if ($OpenTuning) { $arguments += @('--tab=4', '--open-thc-live-tuning') }
        if ($ProductionCapturePath) {
            $arguments += '--capture-full=' + $ProductionCapturePath
            $arguments += '--run-exit-after-ms=10000'
        }
    }
    Push-Location $build
    try {
        & $exe @arguments
        if ($LASTEXITCODE -ne 0) { throw "Qt exited with code $LASTEXITCODE" }
        if ($ModalCapturePath) {
            if (-not (Test-Path -LiteralPath $ModalCapturePath -PathType Leaf) -or
                (Get-Item -LiteralPath $ModalCapturePath).Length -eq 0) {
                throw "Qt did not save the requested modal capture: $ModalCapturePath"
            }
            Write-Output "Modal capture saved: $ModalCapturePath"
        }
        if ($ProductionCapturePath) {
            if (-not (Test-Path -LiteralPath $ProductionCapturePath -PathType Leaf) -or
                (Get-Item -LiteralPath $ProductionCapturePath).Length -eq 0) {
                throw "Qt did not save the requested production capture: $ProductionCapturePath"
            }
            Write-Output "Production capture saved: $ProductionCapturePath"
        }
    } finally {
        Pop-Location
    }
} finally {
    $imageLock.Dispose()
}