#Requires -Version 5.1

<#
.SYNOPSIS
  Prevents Windows sleep while the wechat-claude-code daemon is running
.DESCRIPTION
  Uses three layers to keep the system awake:
    1. SetThreadExecutionState (ES_CONTINUOUS | ES_SYSTEM_REQUIRED) — prevents sleep
    2. Powercfg override — prevents sleep on AC/battery
    3. Periodic resume timer — wakes from sleep if it somehow was triggered
.NOTES
  Run this alongside the daemon. Call Stop-SleepBlock to clean up power settings on exit.
#>

$DATA_DIR = "$env:USERPROFILE\.wechat-claude-code"

# Add required Win32 API
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class PowerHelper {
    // ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_AWAYMODE_REQUIRED
    private const uint ES_CONTINUOUS = 0x80000000;
    private const uint ES_SYSTEM_REQUIRED = 0x00000001;
    private const uint ES_AWAYMODE_REQUIRED = 0x00000040;

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint SetThreadExecutionState(uint esFlags);

    public static uint PreventSleep() {
        return SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_AWAYMODE_REQUIRED);
    }

    public static uint AllowSleep() {
        return SetThreadExecutionState(ES_CONTINUOUS);
    }
}
"@

function Start-SleepBlock {
  Write-Host "Sleep prevention: active" -ForegroundColor Cyan

  # Layer 1: SetThreadExecutionState (per-process, doesn't need admin)
  $null = [PowerHelper]::PreventSleep()

  # Layer 2: Powercfg (needs admin, best-effort)
  try {
    $currentScheme = (powercfg /getactivescheme) -replace '.*\(|\).*', ''
    # Disable sleep timeout on AC power
    powercfg /change standby-timeout-ac 0 2>$null
    powercfg /change hibernate-timeout-ac 0 2>$null
    # Disable sleep timeout on battery
    powercfg /change standby-timeout-dc 0 2>$null
    powercfg /change hibernate-timeout-dc 0 2>$null
    Write-Host "  Powercfg sleep timeouts: disabled" -ForegroundColor DarkGray
  } catch {
    Write-Host "  Powercfg: skipped (requires admin)" -ForegroundColor DarkGray
  }

  # Keep the thread execution state refreshed every 60 seconds
  $script:keepAliveTimer = Register-ObjectEvent -InputObject ([System.Timers.Timer]::new(60000)) -EventName Elapsed -Action {
    $null = [PowerHelper]::PreventSleep()
  }
  $script:keepAliveTimer.Enabled = $true
}

function Stop-SleepBlock {
  # Remove timer
  if ($script:keepAliveTimer) {
    $script:keepAliveTimer.Enabled = $false
    $script:keepAliveTimer.Dispose()
    Unregister-Event -SourceIdentifier $script:keepAliveTimer.Name -ErrorAction SilentlyContinue
  }

  # Allow system to sleep again
  $null = [PowerHelper]::AllowSleep()
  Write-Host "Sleep prevention: cleaned up" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# Watchdog: periodically check if the daemon process is alive, restart if dead
# ---------------------------------------------------------------------------

$DAEMON_PID_FILE = "$DATA_DIR\wechat-claude-code.pid"
$PROJECT_DIR = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Test-DaemonRunning {
  if (-not (Test-Path $DAEMON_PID_FILE)) { return $false }
  $pid = Get-Content $DAEMON_PID_FILE -Raw | ForEach-Object { $_.Trim() }
  if (-not $pid -or -not ($pid -match '^\d+$')) { return $false }
  try {
    $proc = Get-Process -Id ([int]$pid) -ErrorAction Stop
    return $proc.ProcessName -eq 'node'
  } catch { return $false }
}

function Start-Watchdog {
  while ($true) {
    Start-Sleep -Seconds 30
    if (-not (Test-DaemonRunning)) {
      Write-Host "[Watchdog] Daemon not running, restarting..." -ForegroundColor Yellow
      try {
        Push-Location $PROJECT_DIR
        & "$PROJECT_DIR\scripts\daemon.ps1" start
        Pop-Location
      } catch {
        Write-Host "[Watchdog] Restart failed: $_" -ForegroundColor Red
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$command = $args[0]
switch ($command) {
  'start' {
    Start-SleepBlock
    Write-Host "Keep-alive started. Press Ctrl+C to stop." -ForegroundColor Green
    # Start watchdog in background job
    $null = Start-Job -Name "daemon-watchdog" -ScriptBlock ${function:Start-Watchdog} -ArgumentList @()
    # Keep running
    while ($true) { Start-Sleep -Seconds 10 }
  }
  'stop' {
    Stop-SleepBlock
    Get-Job -Name "daemon-watchdog" -ErrorAction SilentlyContinue | Stop-Job | Remove-Job
  }
  default {
    Write-Host "Usage: keep-alive.ps1 {start|stop}" -ForegroundColor Yellow
  }
}
