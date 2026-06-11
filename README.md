# WeChat Claude Code Bridge (Windows 版)

<p align="center">
  <strong>在微信中与 AI 编程助手聊天，就像给朋友发消息一样简单</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License: MIT"></a>
  <a href="https://github.com/faruheaisha/wechat-claude-code-windows"><img src="https://img.shields.io/badge/Windows-ready-blue?style=flat-square" alt="Windows"></a>
  <a href="README_en.md"><img src="https://img.shields.io/badge/Lang-English-blue?style=flat-square" alt="English"></a>
</p>

扫描二维码绑定微信，你的通讯录里会出现一个新的"好友"。给它发消息 —— 消息会被转发到 Claude Code（支持 DeepSeek 等第三方 LLM），回复实时推送到微信。支持文字、图片、语音和文件。

本项目是 [Wechat-ggGitHub/wechat-claude-code](https://github.com/Wechat-ggGitHub/wechat-claude-code) 的 **Windows 适配分支**，增加了云服务器部署支持，实现关机后依然 24/7 在线。

---

## 特点

| | |
|---|---|
| **扫码即用** | 无需注册账号，扫描二维码即可绑定，一分钟搞定 |
| **消息干净** | 仅推送核心信息 —— 进度、结果、关键决策，工具调用自动过滤 |
| **"正在输入..."提示** | Claude 处理时微信实时显示"对方正在输入..." |
| **双端文件传输** | 发送图片、Word、PDF 给 Claude 分析；生成的文件自动推送到微信 |
| **链接自动读取** | 发公众号/网页链接自动抓取内容，无需手动操作 |
| **超时安抚** | 任务超过 5 分钟未响应，自动发消息告知你仍在处理中 |
| **云服务器部署** | 一键部署到 DigitalOcean/VPS，关机后依然 24 小时在线 |
| **LLM 自由切换** | 内置 cc-switch 支持，可随意切换 DeepSeek、OpenRouter 等第三方模型 |
| **微信 /model 控制** | 在聊天中直接发送 `/model flash` 或 `/model pro` 切换模型 |
| **会话保活** | 每 15 分钟心跳保活，过期后 5 秒自动重连，长期稳定运行 |
| **反检测机制** | 随机间隔轮询、类人打字速度、随机思考延迟、UA 轮换 |
| **断线自动恢复** | 健康检查 + 指数退避重试，网络中断后自动恢复 |
| **看门狗守护** | 后台进程每 30 秒检测，崩溃自动拉起 |
| **系统防休眠** | Win32 API SetThreadExecutionState + Powercfg 防止系统休眠 |

---

## 安装前提

- **Windows 10/11**（64位）
- **Node.js >= 18** — 从 [nodejs.org](https://nodejs.org) 下载安装（勾选"Add to PATH"）
- **个人微信账号**
- **[Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)** — 已安装并认证
  - `npm install -g @anthropic-ai/claude-code`
  - 支持第三方 API 提供商，设置环境变量即可：
    ```bash
    set ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
    set ANTHROPIC_API_KEY=sk-your-key-here
    ```
- **Git** — 从 [git-scm.com](https://git-scm.com) 下载安装

---

## 安装

### 方法一：skills CLI（推荐）

```powershell
npx skills add faruheaisha/wechat-claude-code-windows
```

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
npm run daemon -- status    # 运行状态（含 Watchdog 和防休眠）
npm run daemon -- stop      # 停止服务
npm run daemon -- restart   # 重启（代码更新后使用）
npm run daemon -- logs      # 查看日志
```

### 切换 LLM 模型（cc-switch）

```powershell
# 使用 DeepSeek
set ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
set ANTHROPIC_API_KEY=sk-your-key

# 使用 OpenRouter
set ANTHROPIC_BASE_URL=https://openrouter.ai/api/v1
set ANTHROPIC_API_KEY=sk-or-your-key
```

然后在 `~/.claude/settings.json` 中配置模型映射：

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

微信聊天中用 `/model flash` 或 `/model pro` 随时切换。

---

## 云服务器部署（24/7 不间断运行）

如果需要 **不依赖本地电脑、24 小时在线**，可以将桥接服务部署到云服务器上。

### 架构对比

```
本地:  微信 ←→ ilink API ←→ Node.js(本机) ←→ Claude Code(本机)   ❌ 关机即停
云端:  微信 ←→ ilink API ←→ Node.js(云端) ←→ Claude Code(云端)   ✅ 24/7 在线
```

### 一键部署

SSH 登录到云服务器后，执行：

```bash
curl -fsSL https://raw.githubusercontent.com/faruheaisha/wechat-claude-code-windows/main/scripts/deploy-cloud.sh | bash
```

脚本自动完成：Node.js → 克隆仓库 → 安装依赖 → 安装 Claude Code CLI → 配置 systemd 开机自启。

### 部署后配置

```bash
# 1. 微信扫码绑定（必须在服务器上扫码！）
node /opt/wechat-claude-code/dist/main.js setup

# 2. 认证 Claude Code CLI
su - wcc-bridge -c 'claude'

# 3. 设置环境变量
cat > /opt/wechat-claude-code/.env << EOF
ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
ANTHROPIC_API_KEY=sk-your-key
EOF

# 4. 配置模型映射（cc-switch）
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

# 5. 启动服务
systemctl start wechat-bridge

# 6. 查看状态
systemctl status wechat-bridge

# 7. 实时日志
journalctl -u wechat-bridge -f
```

> **注意：** ilink 会检查扫码设备 IP，**必须直接在服务器上扫码**才能使用云部署。本地扫码的凭据无法在服务器上使用。

### 连接稳定性保障

部署后服务自带：
- **每 15 分钟心跳保活** — 定期刷新会话，防止超时
- **5 秒快速重连** — 会话过期后立即以指数退避重试，而非等 1 小时
- **每日凌晨 3 点自动重启** — crontab 定时刷新连接
- **sysemtmd 看门狗** — 崩溃 10 秒内自动恢复
- **网络恢复** — 健康检查 + 指数退避，断网后自动重连

---

## 使用技巧

### 发送链接

由于微信平台限制，无法直接将 Bot 加入转发列表。**替代方法：**

| 你想做的 | 操作方法 |
|:--|:--|
| 分享公众号文章 | 长按文章 → 复制链接 → 粘贴到 Bot 聊天 |
| 分享视频号 | 长按视频 → 复制链接 → 粘贴发送 |
| 分享聊天记录 | 截图发送（支持图片识别）或复制关键文字 |
| 分享文件 | 直接在聊天中发送文件 |
| 分享图片 | 直接发送图片 |

Bot 会自动读取链接内容并总结回复。

### 微信命令

在聊天中直接发送：

| 命令 | 说明 |
|------|------|
| `/help` | 显示帮助 |
| `/clear` | 清除当前会话，开始新对话 |
| `/stop` | 停止当前任务 |
| `/model <name>` | 切换模型（flash / pro） |
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

```
%USERPROFILE%\.wechat-claude-code\
├── accounts\       # 微信账号凭据
├── config.json     # 全局配置（工作目录、提示词等）
├── sessions\       # 会话数据
├── logs\           # 日志文件（每日轮转，保留30天）
└── get_updates_buf # 消息同步缓冲
```

服务器上在 `/var/lib/wcc-bridge/.wechat-claude-code/`。

---

## Windows 适配说明

| 改动项 | 说明 |
|--------|------|
| **daemon.ps1** | PowerShell 脚本替代 bash，三层守护（主进程 + Watchdog + 防休眠） |
| **provider.ts** | claude.cmd 命令路径 + cmd.exe /c 兼容 |
| **进程管理** | `taskkill` 替代 `SIGTERM`（Windows 不支持 POSIX 信号） |
| **路径处理** | `C:\...` 正则匹配 + `USERPROFILE` 替代 `HOME` |
| **防休眠** | Win32 API `SetThreadExecutionState` + Powercfg |

---

## 路线图

已实现：
- ✅ **扫码绑定** — 微信 Bot 免注册、免服务器
- ✅ **文件传输** — 图片/Word/PDF 双向传输
- ✅ **链接自动抓取** — 公众号/网页链接自动读取内容
- ✅ **cc-switch 支持** — 第三方 LLM 自由切换（DeepSeek / OpenRouter）
- ✅ **微信 /model 命令** — 随时切换模型
- ✅ **24/7 云服务器部署** — DigitalOcean VPS 一键部署
- ✅ **会话保活与快速重连** — 心跳 + 指数退避 + 每日重启
- ✅ **反检测机制** — 类人行为模拟，降低风控概率
- ✅ **断线自动恢复** — 健康检查 + 指数退避
- ✅ **看门狗 + 防休眠** — 崩溃自愈 + 系统不睡眠

开发中：
- **消息队列优化** — 连续消息避免回复混乱
- **桌面会话延续** — 电脑聊天后从微信继续同一会话

---

## 开源协议

[MIT](LICENSE)

### 致谢

- 感谢 [Wechat-ggGitHub](https://github.com/Wechat-ggGitHub) 的原始 macOS 版项目
- 感谢 iBot / ilink 团队的微信 Bot API
