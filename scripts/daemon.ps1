#!/usr/bin/env pwsh
<#
.SYNOPSIS
  wechat-claude-code Windows daemon manager
.DESCRIPTION
  Manages the wechat-claude-code bridge service on Windows.
  Uses Start-Process in background mode (no Task Scheduler dependency).
  Supports: start, stop, restart, status, logs
#>

$ErrorActionPreference = 'Stop'

$DATA_DIR = "$env:USERPROFILE\.wechat-claude-code"
$PROJECT_DIR = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$SERVICE_NAME = "wechat-claude-code"

# Ensure log directory
$LOG_DIR = "$DATA_DIR\logs"
$null = New-Item -ItemType Directory -Path $LOG_DIR -Force

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
    # Check common paths
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

  # Redirect stdout/stderr to daily log files via cmd.exe /c
  $logTime = Get-Date -Format "yyyy-MM-dd"
  $outLog = "$LOG_DIR\stdout-$logTime.log"
  $errLog = "$LOG_DIR\stderr-$logTime.log"

  # Use Start-Process with redirected output to avoid event-based IO (unreliable in PS 5.1)
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
}

# =============================================================================
# Stop
# =============================================================================

function Stop-Daemon {
  $procPid = Get-RunningPid
  if (-not $procPid) {
    Write-Host "Not running" -ForegroundColor Yellow
    Remove-Item (Get-PidFile) -ErrorAction SilentlyContinue
    return
  }

  Write-Host "Stopping wechat-claude-code daemon (PID: $procPid)..." -ForegroundColor Cyan

  # On Windows, use taskkill /F to force kill the process tree
  try {
    $process = Start-Process -FilePath 'taskkill' -ArgumentList "/PID $procPid /F" -NoNewWindow -PassThru -Wait
  } catch {
    # Fallback: kill process directly
    try {
      $process = Get-Process -Id $procPid -ErrorAction Stop
      $process.Kill()
    } catch {
      Write-Host "Process already terminated" -ForegroundColor DarkGray
    }
  }

  # Wait for process to exit
  $timeout = 10
  $elapsed = 0
  while ($elapsed -lt $timeout) {
    $proc = Get-ProcessById -Pid $procPid
    if (-not $proc) { break }
    Start-Sleep -Milliseconds 500
    $elapsed += 0.5
  }

  # Force kill if still alive
  $proc = Get-ProcessById -Pid $procPid
  if ($proc) {
    try { $proc.Kill() } catch {}
  }

  Remove-Item (Get-PidFile) -ErrorAction SilentlyContinue
  Write-Host "Stopped" -ForegroundColor Green
}

# =============================================================================
# Status
# =============================================================================

function Get-Status {
  $procPid = Get-RunningPid
  if ($procPid) {
    Write-Host "Running (PID: $procPid)" -ForegroundColor Green
  } else {
    Write-Host "Not running" -ForegroundColor Yellow
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
    # Look for older logs
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
  'start'   { Start-Daemon }
  'stop'    { Stop-Daemon }
  'restart' {
    Stop-Daemon
    Start-Sleep -Seconds 2
    Start-Daemon
  }
  'status'  { Get-Status }
  'logs'    { Show-Logs }
  default {
    Write-Host @"
Usage: daemon.ps1 {start|stop|restart|status|logs}
Platform: Windows

Commands:
  start     Start the daemon in background
  stop      Stop the daemon
  restart   Restart the daemon
  status    Check if running
  logs      View recent logs
"@
  }
}
