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
  param([int]$Pid)
  try { return Get-Process -Id $Pid -ErrorAction Stop } catch { return $null }
}

function Get-RunningPid {
  $pidFile = Get-PidFile
  if (-not (Test-Path $pidFile)) { return $null }
  $pid = Get-Content $pidFile -Raw | ForEach-Object { $_.Trim() }
  if (-not $pid -or -not ($pid -match '^\d+$')) { return $null }
  $proc = Get-ProcessById -Pid ([int]$pid)
  if ($proc -and $proc.ProcessName -eq 'node') { return [int]$pid }
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

  # Build environment block for the child process
  $envBlock = @{}
  foreach ($key in $env.Keys) { $envBlock[$key] = $env[$key] }

  # Start node process in background
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $nodeBin
  $psi.Arguments = "`"$mainJs`" start"
  $psi.WorkingDirectory = $PROJECT_DIR
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
  $psi.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)

  # Pass environment variables
  foreach ($kv in $envBlock.GetEnumerator()) {
    $null = $psi.EnvironmentVariables.Add($kv.Key, $kv.Value)
  }

  $proc = New-Object System.Diagnostics.Process
  $proc.StartInfo = $psi
  $null = $proc.Start()

  # Write PID file
  $proc.Id | Out-File (Get-PidFile) -Encoding utf8

  # Start async stdout/stderr logging
  $logTime = Get-Date -Format "yyyy-MM-dd"
  $outLog = "$LOG_DIR\stdout-$logTime.log"
  $errLog = "$LOG_DIR\stderr-$logTime.log"

  # Read stdout asynchronously
  $proc.OutputDataReceived.Add({
    param($sender, $e)
    if ($e.Data) {
      Add-Content -Path $outLog -Value $e.Data -Encoding utf8
    }
  })
  $proc.BeginOutputReadLine()

  # Read stderr asynchronously
  $proc.ErrorDataReceived.Add({
    param($sender, $e)
    if ($e.Data) {
      Add-Content -Path $errLog -Value $e.Data -Encoding utf8
    }
  })
  $proc.BeginErrorReadLine()

  Write-Host "Started (PID: $($proc.Id))" -ForegroundColor Green
  Write-Host "Logs: $LOG_DIR" -ForegroundColor DarkGray
}

# =============================================================================
# Stop
# =============================================================================

function Stop-Daemon {
  $pid = Get-RunningPid
  if (-not $pid) {
    Write-Host "Not running" -ForegroundColor Yellow
    Remove-Item (Get-PidFile) -ErrorAction SilentlyContinue
    return
  }

  Write-Host "Stopping wechat-claude-code daemon (PID: $pid)..." -ForegroundColor Cyan

  # Try graceful shutdown first (SIGINT via CtrlC simulation)
  try {
    # On Windows, use taskkill to send Ctrl+C (SIGINT equivalent)
    $process = Start-Process -FilePath 'taskkill' -ArgumentList "/PID $pid /F" -NoNewWindow -PassThru -Wait
  } catch {
    # Fallback: kill process tree
    try {
      $process = Get-Process -Id $pid -ErrorAction Stop
      $process.Kill()
    } catch {
      Write-Host "Process already terminated" -ForegroundColor DarkGray
    }
  }

  # Wait for process to exit
  $timeout = 10
  $elapsed = 0
  while ($elapsed -lt $timeout) {
    $proc = Get-ProcessById -Pid $pid
    if (-not $proc) { break }
    Start-Sleep -Milliseconds 500
    $elapsed += 0.5
  }

  # Force kill if still alive
  $proc = Get-ProcessById -Pid $pid
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
  $pid = Get-RunningPid
  if ($pid) {
    Write-Host "Running (PID: $pid)" -ForegroundColor Green
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
