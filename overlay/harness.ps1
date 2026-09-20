# Launcher for Windows: finds Git Bash and runs harness.sh.
# "bash" from PATH is not used on purpose: on Windows the first match is
# C:\Windows\System32\bash.exe, a WSL stub.
$ErrorActionPreference = 'Stop'

$candidates = @(
  (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),
  (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe')
)
$bash = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bash) {
  Write-Host '[harness] E_PREREQ Git Bash not found. Install Git for Windows: winget install Git.Git'
  exit 1
}

# Forward slashes: dirname inside bash does not understand backslashes.
$script = (Join-Path $PSScriptRoot 'harness.sh') -replace '\\', '/'
& $bash $script @args
exit $LASTEXITCODE
