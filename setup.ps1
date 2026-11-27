<#
BendCNC one-step setup for Windows.
Installs the runtime used by CAD import / sequence planning:
  - Python 3 + shapely, numpy, networkx
  - Node.js LTS
Usage (PowerShell):  powershell -ExecutionPolicy Bypass -File setup.ps1
#>
$ErrorActionPreference = 'Stop'

function Refresh-Path {
    $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('PATH', 'User')
}

function Find-Python {
    foreach ($name in 'python', 'python3', 'py') {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue |
            Where-Object { $_.Source -notmatch 'WindowsApps' } | Select-Object -First 1
        if ($cmd) {
            & $cmd.Source -c "import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)" 2>$null
            if ($LASTEXITCODE -eq 0) { return $cmd.Source }
        }
    }
    return $null
}

function Install-WithWinget($id, $label) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "$label not found and winget is unavailable. Install $label manually, then rerun setup.ps1."
    }
    Write-Host "Installing $label ..." -ForegroundColor Cyan
    winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements
    Refresh-Path
}

Write-Host '== BendCNC setup ==' -ForegroundColor Green

# 1. Python
$python = Find-Python
if (-not $python) {
    Install-WithWinget 'Python.Python.3.12' 'Python 3'
    $python = Find-Python
    if (-not $python) { throw 'Python was installed but is not on PATH yet. Open a new terminal and rerun setup.ps1.' }
}
Write-Host "Python: $python"

# 2. Python packages
Write-Host 'Installing Python packages (shapely, numpy, networkx) ...' -ForegroundColor Cyan
& $python -m pip install --upgrade --user pip
& $python -m pip install --user shapely numpy networkx
if ($LASTEXITCODE -ne 0) { throw 'pip install failed.' }
& $python -c "import shapely, numpy, networkx; print('shapely', shapely.__version__)"
if ($LASTEXITCODE -ne 0) { throw 'Python packages are not importable.' }

# 3. Node.js
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Install-WithWinget 'OpenJS.NodeJS.LTS' 'Node.js'
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw 'Node.js was installed but is not on PATH yet. Open a new terminal and rerun setup.ps1.'
}
Write-Host "Node: $(node --version)"

# 4. Planner submodule
if (Test-Path "$PSScriptRoot\.git") {
    git -C $PSScriptRoot submodule update --init --recursive
}
if (-not (Test-Path "$PSScriptRoot\sequence-planner\tools\plan_sequence.mjs")) {
    Write-Warning 'sequence-planner is missing. Clone with: git clone --recurse-submodules https://github.com/BendCNC/BendCNC.git'
}

# Pin the interpreter so the app never picks a Python without shapely.
[Environment]::SetEnvironmentVariable('UNFOLD_PYTHON', $python, 'User')
Write-Host "UNFOLD_PYTHON set to $python (user environment)."

Write-Host ''
Write-Host 'Setup complete. CAD import and sequence planning are ready.' -ForegroundColor Green
Write-Host 'To build the app you also need Qt 6.8+ (MinGW or MSVC) with CMake and Ninja; see README.md.'
