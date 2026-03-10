#!/bin/bash
# ============================================================
#  问问 AI - Claude Code 一键部署脚本
#  用法: curl -fsSL https://raw.githubusercontent.com/mfzzf/ClaudeDeploy/main/install.sh | bash
# ============================================================

set -e

API_BASE_URL="https://breakout.wenwen-ai.com"
MODEL_1="claude-sonnet-4-6-20260218"
MODEL_2="claude-opus-4-6-20260205"
NODE_MIN_VER="16.0.0"

# ── 颜色 ────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}${BOLD}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}${BOLD}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}${BOLD}[ERROR]${NC} $*"; exit 1; }
step()    { echo -e "\n${BLUE}${BOLD}▶ $*${NC}"; }
skip()    { echo -e "${GREEN}[跳过]${NC}  $*"; }

# ── Banner ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║     问问 AI - Claude Code 一键部署脚本           ║${NC}"
echo -e "${BOLD}${BLUE}╠══════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${BLUE}║  本脚本由 问问AI (breakout.wenwen-ai.com) 提供   ║${NC}"
echo -e "${BOLD}${BLUE}║  使用专属 API 端点，无需自备 Anthropic 账号      ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# ── 工具函数 ─────────────────────────────────────────────────

# 从 /dev/tty 读输入（兼容管道运行）
read_input() {
  local prompt="$1"
  local answer
  read -r -p "$prompt" answer </dev/tty
  echo "$answer"
}

# 掩码输入
read_secret() {
  local prompt="$1"
  local answer
  stty -echo 2>/dev/null || true
  read -r -p "$prompt" answer </dev/tty
  stty echo 2>/dev/null || true
  echo ""
  echo "$answer"
}

# 版本比较：$1 >= $2 返回 true
version_gte() {
  [ "$(printf '%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]
}

# 获取全局已安装的 npm 包版本（未安装返回空）
get_installed_npm_version() {
  npm list -g "$1" --depth=0 2>/dev/null \
    | grep -E "── $1@" \
    | sed 's/.*@//' \
    | tr -d ' \r\n'
}

# 获取 npm 最新版本
get_latest_npm_version() {
  npm view "$1" version 2>/dev/null | tr -d ' \r\n'
}

# 检测是否存在第三方（非 breakout.wenwen-ai.com）的 api_base_url
# 返回 0 = 检测到第三方，返回 1 = 无需清理
is_third_party_config() {
  local cfg="$HOME/.claude-code-router/config.json"
  [ ! -f "$cfg" ] && return 1
  grep -q '"api_base_url"' "$cfg" || return 1
  grep '"api_base_url"' "$cfg" | grep -q 'breakout\.wenwen-ai\.com' && return 1
  return 0
}

# 清理第三方配置、包、环境变量及 claude 状态
cleanup_third_party() {
  local cfg="$HOME/.claude-code-router/config.json"
  local old_url
  old_url=$(grep '"api_base_url"' "$cfg" 2>/dev/null | head -1 \
            | sed 's/.*"api_base_url"[^"]*"\([^"]*\)".*/\1/')

  warn "检测到第三方中转站配置: ${old_url:-（未知）}"
  warn "需要完全卸载旧包和配置后重新安装。"
  CONFIRM=$(read_input "是否继续清理并重装？(Y/n，默认 Y): ")
  CONFIRM="${CONFIRM:-Y}"
  case "$CONFIRM" in
    [Nn]*) error "用户取消，退出" ;;
  esac

  local _npm_root _sudo_npm
  _npm_root=$(npm root -g 2>/dev/null || echo "")
  if [ -w "$_npm_root" ] || [ -w "$(dirname "$_npm_root")" ]; then
    _sudo_npm="npm"
  else
    _sudo_npm="sudo npm"
  fi

  info "卸载旧 npm 包..."
  $_sudo_npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
  $_sudo_npm uninstall -g @musistudio/claude-code-router 2>/dev/null || true
  success "旧 npm 包已卸载"

  info "删除旧配置目录 ~/.claude-code-router ..."
  rm -rf "$HOME/.claude-code-router"
  success "已删除 ~/.claude-code-router"

  info "删除 Claude Code 状态目录 ~/.claude ..."
  rm -rf "$HOME/.claude"
  success "已删除 ~/.claude"

  info "清除旧环境变量..."
  for rc_file in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zshrc"; do
    if [ -f "$rc_file" ]; then
      sed -i '/ANTHROPIC_AUTH_TOKEN/d' "$rc_file"
      sed -i '/ANTHROPIC_API_KEY/d' "$rc_file"
      sed -i '/ANTHROPIC_BASE_URL/d' "$rc_file"
    fi
  done
  unset ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_BASE_URL 2>/dev/null || true
  success "旧环境变量已清除"
}

# 安装或跳过（已是最新则跳过，否则安装/升级）
install_or_skip_npm_pkg() {
  local PKG="$1"
  local DISPLAY="$2"
  local INSTALLED LATEST

  INSTALLED=$(get_installed_npm_version "$PKG")
  if [ -z "$INSTALLED" ]; then
    info "安装 $DISPLAY..."
    $SUDO_NPM install -g "$PKG" 2>&1 | tail -3
    success "$DISPLAY 安装完成"
  else
    info "检查 $DISPLAY 最新版本..."
    LATEST=$(get_latest_npm_version "$PKG")
    if [ -n "$LATEST" ] && [ "$INSTALLED" = "$LATEST" ]; then
      skip "$DISPLAY $INSTALLED 已是最新版本"
    else
      info "$DISPLAY $INSTALLED → ${LATEST:-最新版}，升级中..."
      $SUDO_NPM install -g "$PKG" 2>&1 | tail -3
      success "$DISPLAY 升级完成"
    fi
  fi
}

# ── 1. 询问 API Key ──────────────────────────────────────────
step "API 配置"
API_KEY=$(read_secret "请输入 API Key（输入时不显示）: ")
if [ -z "$API_KEY" ]; then
  error "API Key 不能为空"
fi
success "API Key 已设置"

# ── 2. 选择模型 ──────────────────────────────────────────────
step "选择默认模型"
echo "  1) ${MODEL_1}（推荐，速度快）"
echo "  2) ${MODEL_2}（更强，较慢）"
echo "  3) 手动输入其他模型名"
echo ""

MODEL_CHOICE=$(read_input "请选择 (1/2/3，默认 1): ")
MODEL_CHOICE="${MODEL_CHOICE:-1}"

case "$MODEL_CHOICE" in
  1) MODEL="$MODEL_1" ;;
  2) MODEL="$MODEL_2" ;;
  3) MODEL=$(read_input "请输入模型名: ") ;;
  *) warn "无效选择，使用默认模型 1"; MODEL="$MODEL_1" ;;
esac
success "已选择模型: $MODEL"

# ── 2.5 检测并清理第三方配置 ─────────────────────────────────
step "检测现有配置"
if is_third_party_config; then
  cleanup_third_party
  success "清理完成，继续安装..."
else
  skip "未检测到第三方配置，无需清理"
fi

# ── 3. 检测 Node.js ──────────────────────────────────────────
step "检查 Node.js 环境"

install_node() {
  info "正在自动安装 Node.js LTS..."
  if command -v apt-get &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - 2>/dev/null
    sudo apt-get install -y nodejs
  elif command -v dnf &>/dev/null; then
    curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash - 2>/dev/null
    sudo dnf install -y nodejs
  elif command -v yum &>/dev/null; then
    curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash - 2>/dev/null
    sudo yum install -y nodejs
  elif command -v apk &>/dev/null; then
    sudo apk add --no-cache nodejs npm
  else
    error "无法自动安装 Node.js，请手动安装后重试: https://nodejs.org/"
  fi
}

if command -v node &>/dev/null; then
  NODE_VER=$(node --version 2>/dev/null | tr -d 'v')
  if version_gte "$NODE_VER" "$NODE_MIN_VER"; then
    skip "Node.js v${NODE_VER} 已安装且版本满足要求"
  else
    warn "Node.js v${NODE_VER} 版本过低（需 >= ${NODE_MIN_VER}），重新安装..."
    install_node
    success "Node.js 已更新"
  fi
else
  install_node
  success "Node.js 安装完成"
fi

if ! command -v npm &>/dev/null; then
  error "npm 未找到，请检查 Node.js 安装"
fi

# ── 4. 检测并安装/升级 claude-code 和 ccr ───────────────────
step "检查 Claude Code 相关工具"

# 判断是否需要 sudo
NPM_GLOBAL_ROOT=$(npm root -g 2>/dev/null || echo "")
if [ -w "$NPM_GLOBAL_ROOT" ] || [ -w "$(dirname "$NPM_GLOBAL_ROOT")" ]; then
  SUDO_NPM="npm"
else
  SUDO_NPM="sudo npm"
fi

install_or_skip_npm_pkg "@anthropic-ai/claude-code" "claude-code"
install_or_skip_npm_pkg "@musistudio/claude-code-router" "claude-code-router"

# 刷新 PATH
if ! command -v claude &>/dev/null; then
  export PATH="$(npm bin -g 2>/dev/null):$PATH"
fi

# ── 5. 生成 config.json ──────────────────────────────────────
step "生成配置文件"

CONFIG_DIR="$HOME/.claude-code-router"
CONFIG_FILE="$CONFIG_DIR/config.json"
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

SKIP_CONFIG=false
if [ -f "$CONFIG_FILE" ]; then
  OVERWRITE=$(read_input "配置文件已存在，是否覆盖？(Y/n，默认 Y): ")
  OVERWRITE="${OVERWRITE:-Y}"
  case "$OVERWRITE" in
    [Nn])
      skip "保留现有配置文件，跳过写入"
      SKIP_CONFIG=true
      ;;
  esac
fi

if [ "$SKIP_CONFIG" != "true" ]; then
  DEFAULT_PROVIDER="openai,${MODEL}"
  cat > "$CONFIG_FILE" <<EOF
{
  "LOG": false,
  "CLAUDE_PATH": "",
  "HOST": "127.0.0.1",
  "PORT": 3456,
  "APIKEY": "${API_KEY}",
  "API_TIMEOUT_MS": "600000",
  "PROXY_URL": "",
  "Transformers": [],
  "Providers": [
    {
      "name": "openai",
      "api_base_url": "${API_BASE_URL}/v1/messages",
      "api_key": "${API_KEY}",
      "models": ["${MODEL}"],
      "transformer": { "use": ["Anthropic"] }
    }
  ],
  "Router": {
    "default": "${DEFAULT_PROVIDER}",
    "background": "${DEFAULT_PROVIDER}",
    "think": "${DEFAULT_PROVIDER}",
    "longContext": "${DEFAULT_PROVIDER}",
    "longContextThreshold": 60000,
    "webSearch": "${DEFAULT_PROVIDER}"
  }
}
EOF
  chmod 600 "$CONFIG_FILE"
  success "配置文件已写入: $CONFIG_FILE"
fi

# ── 5.5 写入环境变量到 shell RC（Linux 直接读环境变量）────────
step "配置环境变量"

if [ -n "$ZSH_VERSION" ] || [ "$SHELL" = "/bin/zsh" ]; then
  ENV_RC="$HOME/.zshrc"
else
  ENV_RC="$HOME/.bashrc"
fi

# 先删除旧的同名变量行（避免重复），包括旧版 ANTHROPIC_AUTH_TOKEN
sed -i '/ANTHROPIC_AUTH_TOKEN/d' "$ENV_RC"
sed -i '/ANTHROPIC_API_KEY/d' "$ENV_RC"
sed -i '/ANTHROPIC_BASE_URL/d' "$ENV_RC"

# 写入新值（用引号包裹 key 值，防止特殊字符导致 bash 解析错误）
echo "export ANTHROPIC_API_KEY=\"${API_KEY}\"" >> "$ENV_RC"
echo "export ANTHROPIC_BASE_URL=\"${API_BASE_URL}\"" >> "$ENV_RC"

# 同时在当前 shell 会话生效
export ANTHROPIC_API_KEY="${API_KEY}"
export ANTHROPIC_BASE_URL="${API_BASE_URL}"

success "环境变量已写入 ${ENV_RC}，并在当前会话生效"

# ── 6. 完成 ──────────────────────────────────────────────────
step "完成"

GLOBAL_BIN=$(npm bin -g 2>/dev/null || echo "")

echo ""
echo -e "${GREEN}${BOLD}✅ Claude Code 部署完成！${NC}"
echo ""
echo -e "${CYAN}使用方法:${NC}"
echo "  ccr code          # 启动 Claude Code（推荐）"
echo "  claude            # 直接运行 claude"
echo ""

# 检查 PATH
if [ -n "$GLOBAL_BIN" ] && [[ ":$PATH:" != *":$GLOBAL_BIN:"* ]]; then
  if [ -n "$ZSH_VERSION" ] || [ "$SHELL" = "/bin/zsh" ]; then
    SHELL_RC="$HOME/.zshrc"
  else
    SHELL_RC="$HOME/.bashrc"
  fi
  echo -e "${YELLOW}⚠ 如遇到 \"command not found\"，请运行:${NC}"
  echo "  echo 'export PATH=${GLOBAL_BIN}:\$PATH' >> ${SHELL_RC}"
  echo "  source ${SHELL_RC}"
  echo ""
fi

echo -e "${YELLOW}💡 首次使用提示：${NC}"
echo "  如果 ccr code 停在 Claude 登录界面，先运行一次:"
echo "  ANTHROPIC_AUTH_TOKEN=token claude"
echo "  然后退出，再运行 ccr code 即可"
echo ""
