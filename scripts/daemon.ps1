#!/usr/bin/env pwsh
<#
.SYNOPSIS
  wechat-claude-code Windows daemon manager
.DESCRIPTION
  Manages the wechat-claude-code bridge service on Windows.
  Features:
  - Background process management via Start-Process
  - Automatic restart on crash (watchdog)
  - Windows sleep prevention (via keep-alive.ps1)
  - Daily rotating log files
  - Supports: start, stop, restart, status, logs
#>

$ErrorActionPreference = 'Stop'

$DATA_DIR = "$env:USERPROFILE\.wechat-claude-code"
$PROJECT_DIR = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$SERVICE_NAME = "wechat-claude-code"

# Ensure directories
$LOG_DIR = "$DATA_DIR\logs"
$null = New-Item -ItemType Directory -Path $LOG_DIR -Force

$WATCHDOG_LOG = "$LOG_DIR\watchdog.log"
$KEEPALIVE_SCRIPT = Join-Path $PROJECT_DIR "scripts\keep-alive.ps1"
$WATCHDOG_FILE = "$DATA_DIR\watchdog.pid"

# =============================================================================
# Helper functions
# =============================================================================

function Get-PidFile {
  return "$DATA_DIR\$SERVICE_NAME.pid"
}

function Get-ProcessById {
  param([int]$ProcessId)
  try { return Get-Process -Id $ProcessId -ErrorAction Stop } catch { return $null }
}

function Write-Log {
  param([string]$Message, [string]$Level = "INFO")
  $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Add-Content -Path $WATCHDOG_LOG -Value "[$time] [$Level] $Message" -Encoding utf8
}

function Get-RunningPid {
  $pidFile = Get-PidFile
  if (-not (Test-Path $pidFile)) { return $null }
  $rawPid = Get-Content $pidFile -Raw | ForEach-Object { $_.Trim() }
  if (-not $rawPid -or -not ($rawPid -match '^\d+$')) { return $null }
  $proc = Get-ProcessById -ProcessId ([int]$rawPid)
  if ($proc -and $proc.ProcessName -eq 'node') { return [int]$rawPid }
  return $null
}

function Get-NodeBin {
  $node = (Get-Command node -ErrorAction SilentlyContinue).Source
  if (-not $node) {
    $paths = @(
      "$env:ProgramFiles\nodejs\node.exe",
      "${env:ProgramFiles(x86)}\nodejs\node.exe",
      "$env:LOCALAPPDATA\Programs\nodejs\node.exe",
      "$env:USERPROFILE\AppData\Roaming\npm\node.exe"
    )
    foreach ($p in $paths) {
      if (Test-Path $p) { $node = $p; break }
    }
  }
  return $node
}

# =============================================================================
# Start
# =============================================================================

function Start-Daemon {
  $existingPid = Get-RunningPid
  if ($existingPid) {
    Write-Host "Already running (PID: $existingPid)" -ForegroundColor Yellow
    return
  }

  $nodeBin = Get-NodeBin
  if (-not $nodeBin) {
    Write-Error "Node.js not found. Please install Node.js >= 18 from https://nodejs.org"
    exit 1
  }

  $mainJs = Join-Path $PROJECT_DIR "dist\main.js"
  if (-not (Test-Path $mainJs)) {
    Write-Host "Building project first..." -ForegroundColor Cyan
    Push-Location $PROJECT_DIR
    npm run build
    Pop-Location
  }

  Write-Host "Starting wechat-claude-code daemon..." -ForegroundColor Cyan

  # Start keep-alive (sleep prevention) in background if available
  if (Test-Path $KEEPALIVE_SCRIPT) {
    $keepAliveProc = Start-Process -FilePath "powershell" -ArgumentList @(
      "-ExecutionPolicy", "Bypass",
      "-File", "`"$KEEPALIVE_SCRIPT`"", "start"
    ) -WindowStyle Hidden -PassThru
    $keepAliveProc.Id | Out-File "$DATA_DIR\keepalive.pid" -Encoding utf8
    Write-Host "  Sleep prevention: active" -ForegroundColor DarkGray
  }

  # Redirect stdout/stderr to daily log files
  $logTime = Get-Date -Format "yyyy-MM-dd"
  $outLog = "$LOG_DIR\stdout-$logTime.log"
  $errLog = "$LOG_DIR\stderr-$logTime.log"

  $startArgs = @{
    FilePath               = $nodeBin
    ArgumentList           = "`"$mainJs`" start"
    WorkingDirectory       = $PROJECT_DIR
    NoNewWindow            = $false
    WindowStyle            = 'Hidden'
    RedirectStandardOutput = $outLog
    RedirectStandardError  = $errLog
    PassThru               = $true
  }
  $proc = Start-Process @startArgs

  # Write PID file
  $proc.Id | Out-File (Get-PidFile) -Encoding utf8

  Write-Host "Started (PID: $($proc.Id))" -ForegroundColor Green
  Write-Host "Logs: $LOG_DIR" -ForegroundColor DarkGray
  Write-Host ""
  Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray

  Write-Log "Daemon started (PID: $($proc.Id))" -Level "START"
}

# =============================================================================
# Stop (also cleans up keep-alive)
# =============================================================================

function Stop-Daemon {
  $procPid = Get-RunningPid
  if (-not $procPid) {
    Write-Host "Not running" -ForegroundColor Yellow
    Remove-Item (Get-PidFile) -ErrorAction SilentlyContinue
    return
  }

  Write-Host "Stopping daemon (PID: $procPid)..." -ForegroundColor Cyan

  # Stop keep-alive process
  $keepAlivePidFile = "$DATA_DIR\keepalive.pid"
  if (Test-Path $keepAlivePidFile) {
    $kaPid = Get-Content $keepAlivePidFile -Raw | ForEach-Object { $_.Trim() }
    if ($kaPid -match '^\d+$') {
      try {
        taskkill //F //PID $kaPid 2>$null
      } catch { }
    }
    Remove-Item $keepAlivePidFile -ErrorAction SilentlyContinue
    Write-Log "Keep-alive process stopped" -Level "STOP"
  }

  # Stop watchdog if running
  Stop-Watchdog

  # Kill the daemon process
  try {
    taskkill //F //PID $procPid 2>$null
  } catch {
    try {
      $process = Get-Process -Id $procPid -ErrorAction Stop
      $process.Kill()
    } catch {
      Write-Host "  Process already terminated" -ForegroundColor DarkGray
    }
  }

  # Wait for exit
  $timeout = 10
  $elapsed = 0
  while ($elapsed -lt $timeout) {
    $proc = Get-ProcessById -ProcessId $procPid
    if (-not $proc) { break }
    Start-Sleep -Milliseconds 500
    $elapsed += 0.5
  }

  # Force kill if still alive
  $proc = Get-ProcessById -ProcessId $procPid
  if ($proc) {
    try { $proc.Kill() } catch {}
  }

  Remove-Item (Get-PidFile) -ErrorAction SilentlyContinue
  Write-Host "Stopped" -ForegroundColor Green
  Write-Log "Daemon stopped (PID: $procPid)" -Level "STOP"
}

# =============================================================================
# Watchdog (auto-restart on crash)
# =============================================================================

function Start-Watchdog {
  $existingWatchdog = Get-WatchdogPid
  if ($existingWatchdog) {
    Write-Host "Watchdog already running (PID: $existingWatchdog)" -ForegroundColor Yellow
    return
  }

  $watchdogScript = Join-Path $PROJECT_DIR "scripts\watchdog.ps1"
  if (-not (Test-Path $watchdogScript)) {
    Write-Host "  Watchdog script not found at $watchdogScript" -ForegroundColor Yellow
    return
  }

  Write-Host "Starting watchdog..." -ForegroundColor Cyan

  $watchdogProc = Start-Process -FilePath "powershell" -ArgumentList @(
    "-ExecutionPolicy", "Bypass",
    "-NoProfile",
    "-File", "`"$watchdogScript`""
  ) -WindowStyle Hidden -PassThru

  Write-Host "  Watchdog (PID: $($watchdogProc.Id)): active" -ForegroundColor DarkGray
  Write-Log "Watchdog started (PID: $($watchdogProc.Id))" -Level "START"
}

function Stop-Watchdog {
  if (Test-Path $WATCHDOG_FILE) {
    $watchdogPid = Get-Content $WATCHDOG_FILE -Raw | ForEach-Object { $_.Trim() }
    if ($watchdogPid -match '^\d+$') {
      try {
        taskkill //F //PID $watchdogPid 2>$null
        Write-Log "Watchdog stopped (PID: $watchdogPid)" -Level "STOP"
      } catch { }
    }
    Remove-Item $WATCHDOG_FILE -ErrorAction SilentlyContinue
  }
}

function Get-WatchdogPid {
  if (-not (Test-Path $WATCHDOG_FILE)) { return $null }
  $rawPid = Get-Content $WATCHDOG_FILE -Raw | ForEach-Object { $_.Trim() }
  if (-not $rawPid -or -not ($rawPid -match '^\d+$')) { return $null }
  try {
    $proc = Get-Process -Id ([int]$rawPid) -ErrorAction Stop
    if ($proc.ProcessName -eq 'powershell') { return [int]$rawPid }
    return $null
  } catch { return $null }
}

# =============================================================================
# Status
# =============================================================================

function Get-Status {
  $procPid = Get-RunningPid
  $watchdogPid = Get-WatchdogPid
  $keepAlivePidFile = "$DATA_DIR\keepalive.pid"
  $keepAliveRunning = $false
  if (Test-Path $keepAlivePidFile) {
    $kaPid = Get-Content $keepAlivePidFile -Raw | ForEach-Object { $_.Trim() }
    if ($kaPid -match '^\d+$') {
      try {
        $proc = Get-Process -Id ([int]$kaPid) -ErrorAction Stop
        $keepAliveRunning = $proc.ProcessName -eq 'powershell'
      } catch { }
    }
  }

  if ($procPid) {
    Write-Host "Daemon:      Running (PID: $procPid)" -ForegroundColor Green
  } else {
    Write-Host "Daemon:      Not running" -ForegroundColor Yellow
  }

  if ($watchdogPid) {
    Write-Host "Watchdog:    Running (PID: $watchdogPid)" -ForegroundColor Green
  } else {
    Write-Host "Watchdog:    Inactive" -ForegroundColor DarkGray
  }

  if ($keepAliveRunning) {
    Write-Host "Keep-alive:  Active" -ForegroundColor Green
  } else {
    Write-Host "Keep-alive:  Inactive" -ForegroundColor DarkGray
  }
}

# =============================================================================
# Logs
# =============================================================================

function Show-Logs {
  $logTime = Get-Date -Format "yyyy-MM-dd"
  $outLog = "$LOG_DIR\stdout-$logTime.log"
  $errLog = "$LOG_DIR\stderr-$logTime.log"

  $found = $false
  if (Test-Path $outLog) {
    Write-Host "=== stdout ($logTime) ===" -ForegroundColor Cyan
    Get-Content $outLog -Tail 50
    $found = $true
  }
  if (Test-Path $errLog) {
    Write-Host "=== stderr ($logTime) ===" -ForegroundColor Cyan
    Get-Content $errLog -Tail 50
    $found = $true
  }

  if (-not $found) {
    $files = Get-ChildItem "$LOG_DIR\*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 3
    if ($files) {
      foreach ($f in $files) {
        Write-Host "=== $($f.Name) ===" -ForegroundColor Cyan
        Get-Content $f.FullName -Tail 50
      }
    } else {
      Write-Host "No logs found" -ForegroundColor Yellow
    }
  }
}

# =============================================================================
# Main dispatcher
# =============================================================================

$command = $args[0]

switch ($command) {
  'start'   {
    Start-Daemon
    Start-Watchdog
  }
  'stop'    { Stop-Daemon }
  'restart' {
    Stop-Daemon
    Start-Sleep -Seconds 2
    Start-Daemon
    Start-Watchdog
  }
  'status'  { Get-Status }
  'logs'    { Show-Logs }
  default {
    Write-Host @"
Usage: daemon.ps1 {start|stop|restart|status|logs}

Platform: Windows
Features: Sleep prevention, Watchdog auto-restart, Daily logs

Commands:
  start     Start the daemon (with sleep prevention and watchdog)
  stop      Stop the daemon and all helpers
  restart   Restart the daemon
  status    Show daemon, watchdog, and sleep-prevention status
  logs      View recent logs
"@
  }
}
