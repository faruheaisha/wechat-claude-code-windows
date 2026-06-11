# WeChat Claude Code Bridge (Windows 版)

<p align="center">
  <strong>在微信中与 Claude Code 聊天，就像给朋友发消息一样简单</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License: MIT"></a>
  <a href="https://github.com/faruheaisha/wechat-claude-code-windows"><img src="https://img.shields.io/badge/Windows-ready-blue?style=flat-square" alt="Windows"></a>
  <a href="README_en.md"><img src="https://img.shields.io/badge/Lang-English-blue?style=flat-square" alt="English"></a>
</p>

扫描二维码绑定微信，你的通讯录里会出现一个新的"好友"。给它发消息 —— 消息会被转发到你电脑上运行的 Claude Code，回复实时推送到微信。支持文字、图片、语音和文件。

本项目是 [Wechat-ggGitHub/wechat-claude-code](https://github.com/Wechat-ggGitHub/wechat-claude-code) 的 **Windows 适配分支**。原项目仅支持 macOS/Linux，本分支增加了 Windows 原生支持。

---

## 特点

| | |
|---|---|
| **扫码即用** | 无需注册账号，无需部署服务器。扫描二维码即可绑定，所有数据存储在你的电脑上。 |
| **消息干净** | 仅推送核心信息 —— 进度、结果、关键决策。工具调用和中间过程自动过滤。 |
| **"正在输入..."提示** | Claude 处理时微信会显示"对方正在输入..."，让你随时知道它正在工作。 |
| **双端文件传输** | 发送图片、Word、PDF 给 Claude 分析；Claude 生成的文件自动推送到微信。 |
| **超时安抚** | 任务超过 5 分钟未响应，会自动发送消息告知你仍在处理中。 |
| **24h 连续运行** | 内置防休眠唤醒 + 看门狗自动重启 + 活跃监听，确保服务持续在线。 |
| **反检测机制** | 随机间隔轮询、类人打字速度、随机思考延迟、UA 轮换，模拟真实用户行为。 |
| **断线自动恢复** | 连接健康检查和指数退避重试，网络中断后自动恢复。 |

---

## 安装前提

- **Windows 10/11**（64位）
- **Node.js >= 18** — 从 [nodejs.org](https://nodejs.org) 下载安装（安装时勾选"Add to PATH"）
- **个人微信账号**
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI** — 已安装并完成认证
  - 可通过 `npm install -g @anthropic-ai/claude-code` 安装
  - 支持第三方 API 提供商（如 OpenRouter、DeepSeek 等），设置 `ANTHROPIC_BASE_URL` 和 `ANTHROPIC_API_KEY` 即可
- **Git** — 从 [git-scm.com](https://git-scm.com) 下载安装

---

## 安装

### 方法一：skills CLI（推荐）

```powershell
npx skills add faruheaisha/wechat-claude-code-windows
```

首次触发 skill 时会自动克隆源码并安装依赖。

### 方法二：手动克隆

```powershell
git clone https://github.com/faruheaisha/wechat-claude-code-windows.git $env:USERPROFILE\.claude\skills\wechat-claude-code-windows
cd $env:USERPROFILE\.claude\skills\wechat-claude-code-windows
npm install
```

---

## 快速开始

### 1. 绑定微信

```powershell
cd $env:USERPROFILE\.claude\skills\wechat-claude-code-windows
npm run setup
```

会弹出二维码图片，用微信扫描即可。

### 2. 启动服务

```powershell
npm run daemon -- start
```

### 3. 开始聊天

打开微信，给你的新"好友"发消息。

### 服务管理

```powershell
npm run daemon -- status    # 查看运行状态（含 Watchdog 和防休眠状态）
npm run daemon -- stop      # 停止服务（同时清理防休眠和 watchdog）
npm run daemon -- restart   # 重启（代码更新后使用）
npm run daemon -- logs      # 查看日志
```

`start` 命令会自动启动：
- **主进程** — Node.js 桥接服务
- **Watchdog** — 每 30 秒检测主进程，崩溃时自动重启
- **防休眠** — 防止 Windows 进入睡眠状态，确保 24h 在线

> **提示:** 要完全实现 7×24 运行，请配合任务计划程序设置开机自启（见 INSTALL.md）。

---

## 云服务器部署（24/7 不间断运行）

如果需要 **不依赖本地电脑、24 小时在线**，可以将桥接服务部署到云服务器上。

### 前置条件

- 任意 Ubuntu 22.04+ VPS（可使用 GitHub Student Pack 的 DigitalOcean $200 额度，选择 $4/月 Droplet）
- SSH 登录权限
- 微信扫码绑定 + Claude Code CLI 认证

### 一键部署

SSH 登录到云服务器后，执行：

```bash
curl -fsSL https://raw.githubusercontent.com/faruheaisha/wechat-claude-code-windows/main/scripts/deploy-cloud.sh | bash
```

脚本会自动完成：安装 Node.js → 克隆仓库 → 安装依赖 → 安装 Claude Code CLI → 配置 systemd 开机自启。

### 部署后配置

```bash
# 1. 微信扫码绑定
node /opt/wechat-claude-code/dist/main.js setup

# 2. 认证 Claude Code CLI
su - wcc-bridge -c 'claude'

# 3. 启动服务
systemctl start wechat-bridge

# 4. 查看状态
systemctl status wechat-bridge

# 5. 实时日志
journalctl -u wechat-bridge -f
```

### 架构对比

```
本地运行:  微信 ←→ ilink API ←→ Node.js(本机) ←→ Claude Code(本机)     ❌ 关机即停
云服务器:  微信 ←→ ilink API ←→ Node.js(云端) ←→ Claude Code(云端)     ✅ 24/7 在线
```

部署后微信上的对话由云服务器处理，本地电脑关机不影响正常使用。

> **注意:** 云服务器上的 Claude Code 访问的是云端的文件系统，无法操作你本地电脑上的文件。项目代码可通过 Git 同步到服务器。

---

## 微信命令

在微信聊天中直接发送以下命令：

| 命令 | 说明 |
|------|------|
| `/help` | 显示帮助 |
| `/clear` | 清除当前会话，开始新对话 |
| `/stop` | 停止当前任务 |
| `/model <name>` | 切换 Claude 模型 |
| `/prompt <内容>` | 设置系统提示词（如"请用中文回答"） |
| `/cwd <路径>` | 切换工作目录 |
| `/skills` | 列出已安装的 Skills |
| `/status` | 查看当前会话状态 |
| `/history [条数]` | 查看最近对话历史 |
| `/compact` | 压缩上下文，开始新的 SDK 会话 |
| `/reset` | 完全重置（包括工作目录） |
| `/undo [条数]` | 撤销最近 N 条消息 |
| `/<skill> [参数]` | 触发任意已安装 Skill |

---

## 数据目录

所有数据存储在 `%USERPROFILE%\.wechat-claude-code\`：

```
%USERPROFILE%\.wechat-claude-code\
├── accounts\       # 微信账号凭据
├── config.json     # 全局配置
├── sessions\       # 会话数据
└── logs\           # 日志文件（每日轮转，保留30天）
```

---

## Windows 适配说明

相比原版 macOS/Linux 版本，此 Windows 分支做了以下适配：

| 改动项 | 说明 |
|--------|------|
| **daemon.ps1** | 使用 PowerShell 脚本替代 bash daemon.sh，通过 System.Diagnostics.Process 管理后台进程 |
| **provider.ts** | 修正 claude 命令路径（Windows 使用 claude.cmd），添加 shell:true 以解析 .cmd 文件 |
| **进程管理** | 使用 `taskkill` 替代 `SIGTERM` 信号（Windows 不支持 POSIX 信号）；内置看门狗自动重启崩溃进程 |
| **路径处理** | 新增 Windows 绝对路径（`C:\...`）的正则匹配；使用 `USERPROFILE` 替代 `HOME` |
| **chmod 跳过** | 原有 `chmodSync` 在 Windows 上自动跳过（已有 `process.platform !== 'win32'` 守卫） |
| **自动启动** | 推荐使用「启动」文件夹或任务计划程序实现开机自启（详见 INSTALL.md） |
| **防休眠** | `keep-alive.ps1` 使用 Win32 API `SetThreadExecutionState` 和 Powercfg 防止系统休眠 |
| **反检测** | `antidetect.ts` 轮询间隔抖动、类人打字速度模拟、随机思考时间、用户代理轮换、消息间隔随机化 |
| **连接韧性** | 健康检查（每 5 分钟）、指数退避重试、最大连续失败后降级为慢速恢复模式 |

---

## 路线图

这些功能已在开发中：

- **消息队列优化** — 连续消息可能导致回复混乱，正在改进队列策略
- **桌面会话延续** — 在电脑上聊天后，从微信继续同一会话

已实现：
- ✅ **系统休眠防护** — `SetThreadExecutionState` + Powercfg 防止 Windows 休眠中断服务
- ✅ **看门狗自动重启** — 后台进程每 30 秒检测，崩溃时自动拉起
- ✅ **连接健康检查** — 每 5 分钟检测 API 连通性，故障时自动恢复
- ✅ **反检测机制** — 轮询间隔抖动、类人打字速度、随机思考延迟、UA 轮换、消息间隔随机化

---

## 开源协议

[MIT](LICENSE)

### 致谢

- 感谢 [Wechat-ggGitHub](https://github.com/Wechat-ggGitHub) 的原始 macOS 版项目
- 感谢 iBot / ilink 团队的微信 Bot API
