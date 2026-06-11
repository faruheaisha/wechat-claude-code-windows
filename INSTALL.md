# Windows 安装指南

本文档提供在 Windows 上安装和配置 wechat-claude-code 的详细说明。

---

## 完整安装步骤

### 1. 安装 Node.js

从 [nodejs.org](https://nodejs.org) 下载 Node.js **LTS 版本（>= 18）**。

安装时务必勾选：
- ☑ **Add to PATH**（添加到 PATH 环境变量）
- ☑ 使用默认安装设置

验证安装：

```powershell
node --version
npm --version
```

### 2. 安装 Git

从 [git-scm.com](https://git-scm.com) 下载安装 Git。

安装时选择：
- 使用 **Git from the command line and also from 3rd-party software**
- 使用 **Checkout as-is, commit as-is**（默认行尾设置）
- 使用 **Windows' default console window**（或 Windows Terminal）

### 3. 安装 Claude Code CLI

```powershell
npm install -g @anthropic-ai/claude-code
```

然后运行 `claude` 完成认证（会打开浏览器引导登录）。

### 4. 安装本桥接工具

```powershell
git clone https://github.com/faruheaisha/wechat-claude-code-windows.git $env:USERPROFILE\.claude\skills\wechat-claude-code-windows
cd $env:USERPROFILE\.claude\skills\wechat-claude-code-windows
npm install
```

---

## 设置开机自启

### 方法一：启动文件夹（推荐）

1. 按 `Win + R`，输入 `shell:startup`，回车
2. 创建文件 `start-wechat-bridge.bat`，内容：
```batch
@echo off
cd /d %USERPROFILE%\.claude\skills\wechat-claude-code-windows
powershell -ExecutionPolicy Bypass -File scripts\daemon.ps1 start
```

### 方法二：任务计划程序

1. 打开"任务计划程序"
2. 创建任务：
   - 触发器：登录时
   - 操作：启动程序 → `powershell`
   - 参数：`-ExecutionPolicy Bypass -File "%USERPROFILE%\.claude\skills\wechat-claude-code-windows\scripts\daemon.ps1" start`
   - 勾选"不管用户是否登录都要运行"

---

## 常见问题

### "claude" 命令找不到

确保 Claude Code CLI 已全局安装，并且 npm 全局包目录在 PATH 中。通常位于：

```powershell
# 检查 claude 命令
where.exe claude
```

### PowerShell 执行策略

如果遇到脚本执行错误，可能需要设置执行策略：

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

### 端口/网络问题

本工具不需要开放入站端口，它使用出站 HTTPS 连接（fetch API）与微信 ilink Bot API 通信，无需修改防火墙。

### 日志查看

```powershell
npm run daemon -- logs
```

日志目录：`%USERPROFILE%\.wechat-claude-code\logs\`

---

## 更新

```powershell
cd $env:USERPROFILE\.claude\skills\wechat-claude-code-windows
git pull
npm install
npm run daemon -- restart
```
