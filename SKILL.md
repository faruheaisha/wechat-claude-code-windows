---
name: wechat-claude-code
description: 微信消息桥接 - 在微信中与 Claude Code 聊天（Windows 版）。支持文字对话、图片识别、实时进度推送、斜杠命令。
---

# WeChat Claude Code Bridge (Windows 版)

在微信中与 Claude Code 聊天，就像给朋友发消息一样简单。支持文字、图片、文件传输。

## Windows 环境检查

本项目已在 Windows 10/11 + Node.js 18+ 下测试可用。

### 安装状态检查

```powershell
test-path $env:USERPROFILE\.claude\skills\wechat-claude-code-windows\package.json
```

- 输出 `True` → 源码就绪
- 输出 `False` → 需要先克隆源码

### 依赖检查

```powershell
test-path $env:USERPROFILE\.claude\skills\wechat-claude-code-windows\node_modules
```

- 输出 `False` → 运行 `cd $env:USERPROFILE\.claude\skills\wechat-claude-code-windows && npm install`
- 输出 `True` → 依赖就绪

### 微信登录检查

```powershell
get-childitem $env:USERPROFILE\.wechat-claude-code\accounts\*.json -ErrorAction SilentlyContinue | select -First 1
```

- 有文件 → 微信已绑定
- 无文件 → 需要运行 `npm run setup`

### 服务状态

```powershell
cd $env:USERPROFILE\.claude\skills\wechat-claude-code-windows && npm run daemon -- status
```

- `Running (PID: xxx)` → 正常运行
- `Not running` → 需要运行 `npm run daemon -- start`

## daemon 命令

启动后：

```
✅ 已启动 (账号: xxx)

可用命令:
  stop     停止服务
  restart  重启服务（更新代码后）
  logs     查看日志
```

停止后：

```
服务已停止 (PID: xxx)

可用命令:
  start    启动服务
  logs     查看日志
```

## 微信命令

在微信聊天中发送斜杠命令：

- `/help` 查看帮助
- `/clear` 清除会话
- `/stop` 停止当前任务
- `/status` 查看状态
- `/model <name>` 切换模型
- `/prompt <内容>` 设置提示词
- `/cwd <路径>` 切换工作目录
- `/skills` 列出所有 skills
- `/skills full` 查看完整描述
- `/history [N]` 查看对话历史
- `/undo [N]` 撤销最近 N 条消息

## 特殊说明

1. 第一次请先用 `setup` 命令绑定微信
2. 启动 daemon 后才能接收消息
3. 非命令类消息会自动转发给 Claude 处理
4. Claude 输出的文件路径会被自动识别并推送到微信
