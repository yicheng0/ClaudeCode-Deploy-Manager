#!/bin/bash
# ============================================================
#  问问 AI - Claude Code 一键部署脚本
#  用法: curl -fsSL https://raw.githubusercontent.com/mfzzf/ClaudeDeploy/main/install.sh | bash
# ============================================================

set -e

API_BASE_URL="https://breakout.wenwen-ai.com"
MODEL_1="claude-sonnet-4-5-20251022"
MODEL_2="claude-opus-4-5-20251022"
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
echo -e "${BOLD}${BLUE}║  本脚本由 问问AI (wenwen-ai.com) 提供            ║${NC}"
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
  if [[ "$OVERWRITE" =~ ^[Nn]$ ]]; then
    skip "保留现有配置文件，跳过写入"
    SKIP_CONFIG=true
  fi
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
