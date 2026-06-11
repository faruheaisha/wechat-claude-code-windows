# WeChat Claude Code Bridge (Windows Edition)

<p align="center">
  <strong>Chat with Claude Code in WeChat, just like texting a friend</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License: MIT"></a>
  <a href="https://github.com/faruheaisha/wechat-claude-code-windows"><img src="https://img.shields.io/badge/Windows-ready-blue?style=flat-square" alt="Windows"></a>
  <a href="README.md"><img src="https://img.shields.io/badge/Lang-中文-green?style=flat-square" alt="中文"></a>
</p>

Scan a QR code to bind your WeChat, and a new "friend" appears in your contacts. Send it a message — it gets forwarded to Claude Code running on your computer, and the reply streams back to WeChat in real time. Supports text, images, voice, and files.

This is a **Windows port** of [Wechat-ggGitHub/wechat-claude-code](https://github.com/Wechat-ggGitHub/wechat-claude-code). The original project supports only macOS/Linux; this fork adds full Windows native support.

---

## Highlights

| | |
|---|---|
| **Scan and go** | No account signup, no server deployment. Scan a QR code and you're done in a minute. All data stays on your machine. |
| **Clean messages** | Only key info gets pushed — progress, results, key decisions. Tool calls and intermediate noise are filtered out automatically. |
| **"Typing..." indicator** | WeChat shows a typing indicator while Claude is working, so you always know it's on it. |
| **Two-way files** | Send images, Word docs, PDFs for Claude to analyze. Files Claude generates get pushed directly to WeChat. |
| **Timeout reassurance** | Task taking longer than 5 minutes? You'll get an automatic message letting you know it's still working. |

---

## Prerequisites

- **Windows 10/11** (64-bit)
- **Node.js >= 18** — Download from [nodejs.org](https://nodejs.org) (check "Add to PATH" during installation)
- A personal WeChat account
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI** — installed and authenticated
  - Install via: `npm install -g @anthropic-ai/claude-code`
  - Supports third-party API providers (OpenRouter, DeepSeek, etc.) via `ANTHROPIC_BASE_URL` and `ANTHROPIC_API_KEY`
- **Git** — Download from [git-scm.com](https://git-scm.com)

---

## Install

**Option 1: skills CLI (recommended)**

```powershell
npx skills add faruheaisha/wechat-claude-code-windows
```

The first time you trigger the skill, it will automatically clone the source and install dependencies.

**Option 2: Manual clone**

```powershell
git clone https://github.com/faruheaisha/wechat-claude-code-windows.git $env:USERPROFILE\.claude\skills\wechat-claude-code-windows
cd $env:USERPROFILE\.claude\skills\wechat-claude-code-windows
npm install
```

---

## Quick Start

### 1. Bind WeChat

```powershell
cd $env:USERPROFILE\.claude\skills\wechat-claude-code-windows
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
npm run daemon -- status    # Check if running
npm run daemon -- stop      # Stop the service
npm run daemon -- restart   # Restart (after code updates)
npm run daemon -- logs      # View recent logs
```

---

## WeChat Commands

Send these directly in the WeChat chat:

| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/clear` | Clear current session, start fresh |
| `/stop` | Stop current task |
| `/model <name>` | Switch Claude model |
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

## How It Works

```
WeChat (phone) ←→ ilink Bot API ←→ Node.js daemon ←→ Claude Code CLI (local)
```

The daemon long-polls WeChat for new messages, forwards them to the local `claude` CLI, and streams replies back to WeChat. Everything runs on your own machine.

---

## Data Directory

All data is stored in `%USERPROFILE%\.wechat-claude-code\`:

```
%USERPROFILE%\.wechat-claude-code\
├── accounts\       # WeChat account credentials
├── config.json     # Global configuration
├── sessions\       # Session data
└── logs\           # Rotating logs (daily, 30-day retention)
```

---

## Windows Adaptation Notes

Compared to the original macOS/Linux version, this Windows fork includes:

| Change | Description |
|--------|-------------|
| **daemon.ps1** | PowerShell script replacing bash daemon.sh, uses `System.Diagnostics.Process` for background process management |
| **provider.ts** | Uses `claude.cmd` command name on Windows, adds `shell: true` for .cmd resolution |
| **Process killing** | Uses `taskkill` instead of `SIGTERM` (Windows doesn't support POSIX signals) |
| **Path handling** | Added Windows absolute path regex (`C:\...`), uses `USERPROFILE` env var for tilde resolution |
| **chmod skip** | Existing `process.platform !== 'win32'` guards in `store.ts` already handle this |
| **Auto-start** | Use Windows Startup folder or Task Scheduler for auto-start on boot (see INSTALL.md) |

---

## Roadmap

- **Message queue optimization** — Consecutive messages can produce mixed-up replies. Working on a better queuing strategy.
- **Prevent sleep** — Use Windows power settings to keep the system awake so sleep doesn't interrupt the service.
- **Resume desktop session** — Chat on your computer for a while, then continue the same session from WeChat on the go.

---

## License

[MIT](LICENSE)

### Credits

- Original project by [Wechat-ggGitHub](https://github.com/Wechat-ggGitHub) (macOS/Linux)
- WeChat Bot API by iBot / ClawBot team
