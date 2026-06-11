# WeChat Claude Code Bridge (Windows Edition)

<p align="center">
  <strong>Chat with an AI coding assistant in WeChat, just like texting a friend</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License: MIT"></a>
  <a href="https://github.com/faruheaisha/wechat-claude-code-windows"><img src="https://img.shields.io/badge/Windows-ready-blue?style=flat-square" alt="Windows"></a>
  <a href="README.md"><img src="https://img.shields.io/badge/Lang-中文-green?style=flat-square" alt="中文"></a>
</p>

Scan a QR code to bind your WeChat, and a new "friend" appears in your contacts. Send it a message — it gets forwarded to Claude Code (supports DeepSeek and other third-party LLMs via cc-switch), and the reply streams back in real time. Supports text, images, voice, and files.

This is a **Windows port** of [Wechat-ggGitHub/wechat-claude-code](https://github.com/Wechat-ggGitHub/wechat-claude-code), with added cloud deployment support for 24/7 operation even when your local machine is off.

---

## Highlights

| | |
|---|---|
| **Scan and go** | No account signup, no server deployment. Scan a QR code and you're done in a minute. |
| **Clean messages** | Only key info gets pushed — progress, results, key decisions. Tool calls and intermediate noise filtered out. |
| **"Typing..." indicator** | WeChat shows a typing indicator while Claude is working. |
| **Two-way files** | Send images, Word docs, PDFs for Claude to analyze. Generated files auto-push to WeChat. |
| **URL auto-fetch** | Paste a WeChat article or webpage link — bot automatically reads and summarizes the content. |
| **Timeout reassurance** | Tasks >5 min get an automatic "still working" message. |
| **Cloud 24/7** | Deploy to a VPS for around-the-clock operation. Turn off your PC, chat keeps working. |
| **LLM freedom** | Built-in cc-switch — swap between DeepSeek, OpenRouter, or any Anthropic-compatible API. |
| **/model in WeChat** | Send `/model flash` or `/model pro` to switch models on the fly. |
| **Session keepalive** | 15-min heartbeat, 5-second reconnect on expiry, daily auto-restart for long-term stability. |
| **Anti-detection** | Randomized poll intervals, human-like typing speed, random think delays, UA rotation. |
| **Auto-recovery** | Health checks + exponential backoff retry — resumes automatically after network interruptions. |
| **Watchdog** | Background process checks every 30s, auto-restarts on crash. |
| **Sleep prevention** | Win32 API `SetThreadExecutionState` + Powercfg prevents system sleep. |

---

## Prerequisites

- **Windows 10/11** (64-bit)
- **Node.js >= 18** — Download from [nodejs.org](https://nodejs.org) (check "Add to PATH" during installation)
- A personal WeChat account
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI** — installed and authenticated
  - `npm install -g @anthropic-ai/claude-code`
  - Supports third-party API providers via environment variables:
    ```bash
    set ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
    set ANTHROPIC_API_KEY=sk-your-key-here
    ```
- **Git** — Download from [git-scm.com](https://git-scm.com)

---

## Install

### Option 1: skills CLI (recommended)

```powershell
npx skills add faruheaisha/wechat-claude-code-windows
```

### Option 2: Manual clone

```powershell
git clone https://github.com/faruheaisha/wechat-claude-code-windows.git $env:USERPROFILE\.claude\skills\wechat-claude-code-windows
cd $env:USERPROFILE\.claude\skills\wechat-claude-code-windows
npm install
```

---

## Quick Start

### 1. Bind WeChat

```powershell
npm run setup
```

A QR code image will open — scan it with WeChat.

### 2. Start the service

```powershell
npm run daemon -- start
```

### 3. Start chatting

Open WeChat and send a message to your new "friend".

### Manage the service

```powershell
npm run daemon -- status    # Full status (daemon, watchdog, sleep prevention)
npm run daemon -- stop      # Stop all services
npm run daemon -- restart   # Restart after code updates
npm run daemon -- logs      # View recent logs
```

### Switch LLM Models (cc-switch)

Configure environment variables:

```powershell
set ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
set ANTHROPIC_API_KEY=sk-your-key
```

Then configure model mapping in `~/.claude/settings.json`:

```json
{
  "model": "deepseek-v4-flash",
  "modelMap": {
    "opus": "deepseek-v4-pro",
    "sonnet": "deepseek-v4-flash",
    "haiku": "deepseek-v4-flash"
  }
}
```

Switch models in WeChat with `/model flash` or `/model pro`.

---

## Cloud Deployment (24/7 Operation)

For **true around-the-clock operation** without relying on your local machine.

### Architecture

```
Local:  WeChat ←→ ilink API ←→ Node.js(local) ←→ Claude Code(local)   ❌ stops on shutdown
Cloud:  WeChat ←→ ilink API ←→ Node.js(cloud) ←→ Claude Code(cloud)   ✅ 24/7 online
```

### One-Click Deploy

SSH into your Ubuntu 22.04+ VPS and run:

```bash
curl -fsSL https://raw.githubusercontent.com/faruheaisha/wechat-claude-code-windows/main/scripts/deploy-cloud.sh | bash
```

The script handles: Node.js install → repo clone → npm install + build → Claude Code CLI → systemd service.

### Post-Deploy Setup

```bash
# 1. Bind WeChat (MUST scan on the server itself!)
node /opt/wechat-claude-code/dist/main.js setup

# 2. Authenticate Claude Code CLI
su - wcc-bridge -c 'claude'

# 3. Set environment variables for third-party LLM
cat > /opt/wechat-claude-code/.env << EOF
ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
ANTHROPIC_API_KEY=sk-your-key
EOF

# 4. Configure model mapping
cat > /var/lib/wcc-bridge/.claude/settings.json << EOF
{
  "model": "deepseek-v4-flash",
  "modelMap": {
    "opus": "deepseek-v4-pro",
    "sonnet": "deepseek-v4-flash",
    "haiku": "deepseek-v4-flash"
  }
}
EOF

# 5. Start the service
systemctl start wechat-bridge

# 6. Check status
systemctl status wechat-bridge

# 7. Live logs
journalctl -u wechat-bridge -f
```

> **Important:** ilink verifies the scanning device's IP. You **must scan the QR code on the server itself** — locally scanned credentials won't work on the cloud.

### Connection Stability

Once deployed, the service includes:
- **15-min keepalive heartbeat** — refreshes session periodically
- **5-second fast reconnect** — exponential backoff on session expiry, not 1-hour wait
- **Daily 3 AM restart** — cron job refreshes the connection
- **systemd watchdog** — auto-restart within 10 seconds of crash
- **Network recovery** — health checks + exponential backoff

---

## Tips

### Sharing Links

WeChat doesn't allow forwarding to bot accounts via the share menu. **Workaround:**

| What you want to do | How |
|:--|:--|
| Share a WeChat article | Long press article → copy link → paste into bot chat |
| Share a video post | Long press → copy link → paste into bot |
| Share chat history | Take a screenshot (bot supports image recognition) or copy text |
| Share files | Send directly in the chat |
| Share images | Send directly |

The bot automatically fetches the URL content and summarizes it.

### WeChat Commands

Send these directly in the WeChat chat:

| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/clear` | Clear current session, start fresh |
| `/stop` | Stop current task |
| `/model <name>` | Switch model (flash / pro) |
| `/prompt <text>` | Set a system prompt (e.g. "reply in Chinese") |
| `/cwd <path>` | Switch working directory |
| `/skills` | List installed Skills |
| `/status` | View current session state |
| `/history [n]` | View recent chat history |
| `/compact` | Compact context, start a new SDK session |
| `/reset` | Full reset including working directory |
| `/undo [n]` | Remove last N messages from history |
| `/<skill> [args]` | Trigger any installed Skill |

---

## Data Directory

```
%USERPROFILE%\.wechat-claude-code\
├── accounts\       # WeChat account credentials
├── config.json     # Global configuration (working directory, prompts)
├── sessions\       # Session data
├── logs\           # Rotating logs (daily, 30-day retention)
└── get_updates_buf # Message sync buffer
```

On Linux cloud servers: `/var/lib/wcc-bridge/.wechat-claude-code/`.

---

## Windows Adaptation Notes

| Change | Description |
|--------|-------------|
| **daemon.ps1** | PowerShell replacing bash daemon.sh, three-layer protection (main + watchdog + keepalive) |
| **provider.ts** | Uses `claude.cmd` on Windows with `cmd.exe /c` instead of `shell: true` |
| **Process killing** | Uses `taskkill` instead of `SIGTERM` (no POSIX signals on Windows) |
| **Path handling** | Added `C:\...` regex support, uses `USERPROFILE` env var |
| **Sleep prevention** | `keep-alive.ps1` uses Win32 API `SetThreadExecutionState` + Powercfg |

---

## Roadmap

Implemented:
- ✅ **QR scan binding** — No registration, no server setup
- ✅ **File transfer** — Images/Word/PDF bidirectional
- ✅ **Auto URL fetch** — Read WeChat article / webpage links automatically
- ✅ **cc-switch support** — Free LLM model switching (DeepSeek, OpenRouter)
- ✅ **/model in WeChat** — Switch models on the fly
- ✅ **Cloud 24/7 deployment** — DigitalOcean VPS one-click deploy
- ✅ **Session keepalive & fast reconnect** — Heartbeat + exponential backoff + daily restart
- ✅ **Anti-detection** — Human-like behavior simulation
- ✅ **Auto-recovery** — Health checks + exponential backoff
- ✅ **Watchdog + sleep prevention** — Crash recovery + system awake

In development:
- **Message queue optimization** — Prevent mixed replies from consecutive messages
- **Desktop session continuity** — Continue computer chat sessions from WeChat

---

## License

[MIT](LICENSE)

### Credits

- Original project by [Wechat-ggGitHub](https://github.com/Wechat-ggGitHub) (macOS/Linux)
- WeChat Bot API by iBot / ilink team
