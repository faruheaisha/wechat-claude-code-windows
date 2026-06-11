#Requires -Version 5.1

<#
.SYNOPSIS
  Watchdog for wechat-claude-code — auto-restarts the daemon on crash.
.DESCRIPTION
  Checks every 30 seconds whether the daemon process is alive.
  If not found, automatically starts it again.
#>

param()

$DATA_DIR = "$env:USERPROFILE\.wechat-claude-code"
$PROJECT_DIR = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$PID_FILE = "$DATA_DIR\wechat-claude-code.pid"
$WATCHDOG_FILE = "$DATA_DIR\watchdog.pid"
$WATCHDOG_LOG = "$DATA_DIR\logs\watchdog.log"
$null = New-Item -ItemType Directory -Path "$DATA_DIR\logs" -Force

function Write-Log {
  param([string]$Message, [string]$Level = "WATCHDOG")
  $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Add-Content -Path $WATCHDOG_LOG -Value "[$time] [$Level] $Message" -Encoding utf8
}

function Test-DaemonRunning {
  if (-not (Test-Path $PID_FILE)) { return $false }
  $pid = Get-Content $PID_FILE -Raw | ForEach-Object { $_.Trim() }
  if (-not $pid -or -not ($pid -match '^\d+$')) { return $false }
  try {
    $proc = Get-Process -Id ([int]$pid) -ErrorAction Stop
    return $proc.ProcessName -eq 'node'
  } catch { return $false }
}

# Write our PID
$processId = [System.Diagnostics.Process]::GetCurrentProcess().Id
$processId | Out-File $WATCHDOG_FILE -Encoding utf8

Write-Log "Watchdog started (PID: $processId)" -Level "START"

while ($true) {
  Start-Sleep -Seconds 30
  if (-not (Test-DaemonRunning)) {
    Write-Log "Daemon not running, restarting..." -Level "WARN"
    try {
      Push-Location $PROJECT_DIR
      & "$PROJECT_DIR\scripts\daemon.ps1" start *>&1 | Out-Null
      Pop-Location
      Write-Log "Daemon restart initiated" -Level "RESTART"
    } catch {
      Write-Log "Restart failed: $_" -Level "ERROR"
    }
  }
}
