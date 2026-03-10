# ClaudeDeploy 🚀

<div align="center">

[![npm version](https://badge.fury.io/js/claudedeploy.svg)](https://badge.fury.io/js/claudedeploy)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Node.js Version](https://img.shields.io/badge/node-%3E%3D16.0.0-brightgreen.svg)](https://nodejs.org/)

**问问 AI 专属 Claude Code 一键部署脚本**

**由 [问问AI (breakout.wenwen-ai.com)](https://breakout.wenwen-ai.com) 提供 · 使用专属 API 端点 · 无需自备 Anthropic 账号**

[中文文档](README_CN.md) | [English](README.md)

</div>

## ✨ 功能特性

- 🚀 **一行命令部署** - `curl | bash` 即可完成全部安装，真正小白友好
- 🔍 **智能跳过** - 自动检测已安装组件，已是最新版则跳过，避免重复安装
- 📦 **自动安装 Node.js** - 未安装 Node.js 时自动识别系统（apt/dnf/yum/apk）并安装
- 🔐 **Anthropic 原生协议** - 直接使用 Messages API，无需 OpenAI 兼容转换
- 🖥️ **交互式 CLI** - 引导式询问 API Key 和模型选择，操作简单
- 🔧 **两种部署模式** - SSH 远程部署 + 本地直接安装（腾讯云 Web 终端等场景）
- ⚡ **自动升级** - 检测到新版本时自动升级 claude-code 和 ccr

## 🚀 一键部署（推荐）

在 VPS 或服务器终端执行：

```bash
curl -fsSL https://raw.githubusercontent.com/yicheng0/ClaudeCode-Deploy-Manager/main/install.sh | bash
```

> **前提**：服务器可访问外网即可，Node.js 会自动安装。

脚本会依次引导你：
1. 输入 API Key（输入时不显示）
2. 选择默认模型（推荐选 1）
3. 自动完成 Node.js / claude-code / ccr 的安装
4. 自动生成配置文件

## 📦 npm CLI 方式

如果你已有 Node.js 环境，也可以使用交互式 CLI：

```bash
# 全局安装
npm install -g claudedeploy

# 启动交互式部署
claudedeploy
```

或者无需安装直接运行：

```bash
npx claudedeploy
```

## 🖥️ 使用流程示例

```
╔══════════════════════════════════════════════════╗
║     问问 AI - Claude Code 一键部署脚本           ║
╠══════════════════════════════════════════════════╣
║  本脚本由 问问AI (breakout.wenwen-ai.com) 提供            ║
║  使用专属 API 端点，无需自备 Anthropic 账号      ║
╚══════════════════════════════════════════════════╝

▶ API 配置
请输入 API Key（输入时不显示）: ****

▶ 选择默认模型
  1) claude-sonnet-4-6-20260218（推荐，速度快）
  2) claude-opus-4-6-20260205（更强，较慢）
  3) 手动输入其他模型名
请选择 (1/2/3，默认 1): 1

▶ 检查 Node.js 环境
[跳过]  Node.js v22.0.0 已安装且版本满足要求

▶ 检查 Claude Code 相关工具
[跳过]  claude-code 1.x.x 已是最新版本
[跳过]  claude-code-router 2.x.x 已是最新版本

▶ 生成配置文件
✅ 配置文件已写入: ~/.claude-code-router/config.json

✅ Claude Code 部署完成！
使用方法:
  ccr code    # 启动 Claude Code（推荐）
  claude      # 直接运行 claude
```

## 🔧 安装后使用

```bash
# 启动 Claude Code（推荐方式）
ccr code

# 直接运行 claude
claude
```

**首次使用提示**：如果 `ccr code` 停在 Claude 登录界面，先运行一次：

```bash
ANTHROPIC_AUTH_TOKEN=token claude
# 然后退出，再运行 ccr code 即可
```

如遇 `command not found`：

```bash
echo "export PATH=$(npm prefix -g)/bin:\$PATH" >> ~/.bashrc && source ~/.bashrc
```

## 🖥️ 支持平台

| 系统 | 支持情况 |
|------|----------|
| Ubuntu / Debian | ✅ 自动安装 Node.js |
| CentOS / RHEL / Amazon Linux | ✅ 自动安装 Node.js |
| Alpine Linux | ✅ 自动安装 Node.js |
| 腾讯云 Web 终端 | ✅ 本地安装模式 |
| 任意 Linux（Node.js >= 16） | ✅ |

## 📄 License

MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/yicheng0/ClaudeCode-Deploy-Manager/issues)
