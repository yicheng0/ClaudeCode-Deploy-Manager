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
PROVIDER_NAME="anthropic"

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
  printf '\n' >/dev/tty
  printf '%s\n' "$answer"
}

strip_line_breaks() {
  printf '%s' "$1" | tr -d '\r\n'
}

# 版本比较：$1 >= $2 返回 true
version_gte() {
  [ "$(printf '%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]
}

is_official_base_url() {
  local url
  url=$(normalize_base_url "$1")
  [ "$url" = "$(normalize_base_url "$API_BASE_URL")" ] || [ "$url" = "https://api.anthropic.com" ]
}

normalize_base_url() {
  local url="$1"
  url="${url%%\?*}"
  url="${url%%\#*}"
  url="${url%/}"
  url="${url%/v1/messages}"
  url="${url%/v1}"
  printf '%s\n' "${url%/}"
}

file_has_non_official_url() {
  local file="$1"
  local pattern="$2"
  local line url

  [ -f "$file" ] || return 1

  while IFS= read -r line; do
    url=$(printf '%s\n' "$line" | grep -oE "https?://[^\"'[:space:]]+" | head -1)
    [ -z "$url" ] && continue
    is_official_base_url "$url" || return 0
  done < <(grep -E "$pattern" "$file" 2>/dev/null || true)

  return 1
}

get_npm_global_bin() {
  local prefix
  prefix=$(npm prefix -g 2>/dev/null || true)
  if [ -n "$prefix" ]; then
    printf '%s/bin\n' "$prefix"
  fi
}

get_existing_claude_url() {
  local cfg="$HOME/.claude-code-router/config.json"
  local claude_json="$HOME/.claude.json"
  local claude_settings="$HOME/.claude/settings.json"
  local claude_settings_local="$HOME/.claude/settings.local.json"
  local url=""

  if [ -f "$cfg" ]; then
    url=$(grep '"api_base_url"' "$cfg" 2>/dev/null | head -1 | grep -oE "https?://[^\"'[:space:]]+" | head -1 || true)
  fi
  if [ -z "$url" ] && [ -f "$claude_json" ]; then
    url=$(grep '"apiBaseUrl"' "$claude_json" 2>/dev/null | head -1 | grep -oE "https?://[^\"'[:space:]]+" | head -1 || true)
  fi
  if [ -z "$url" ] && [ -f "$claude_settings" ]; then
    url=$(grep 'ANTHROPIC_BASE_URL' "$claude_settings" 2>/dev/null | head -1 | grep -oE "https?://[^\"'[:space:]]+" | head -1 || true)
  fi
  if [ -z "$url" ] && [ -f "$claude_settings_local" ]; then
    url=$(grep 'ANTHROPIC_BASE_URL' "$claude_settings_local" 2>/dev/null | head -1 | grep -oE "https?://[^\"'[:space:]]+" | head -1 || true)
  fi

  printf '%s\n' "$url"
}

get_settings_files_to_scan() {
  printf '%s\n' "$HOME/.claude/settings.json"
  printf '%s\n' "$HOME/.claude/settings.local.json"
  if [ "$PWD" != "$HOME" ]; then
    printf '%s\n' "$PWD/.claude/settings.json"
    printf '%s\n' "$PWD/.claude/settings.local.json"
  fi
  printf '%s\n' "/etc/claude-code/managed-settings.json"
}

file_has_auth_override_config() {
  local file="$1"
  [ -f "$file" ] || return 1

  grep -qE '"apiKeyHelper"|"forceLoginMethod"|"forceLoginOrgUUID"|"oauthAccount"|ANTHROPIC_AUTH_TOKEN|ANTHROPIC_CUSTOM_HEADERS' "$file" 2>/dev/null
}

get_detected_third_party_reason() {
  local file

  while IFS= read -r file; do
    [ -f "$file" ] || continue
    if file_has_non_official_url "$file" '"api_base_url"|"apiBaseUrl"|ANTHROPIC_BASE_URL'; then
      printf '检测到第三方 URL 配置: %s\n' "$file"
      return 0
    fi
    if file_has_auth_override_config "$file"; then
      printf '检测到第三方认证覆盖配置: %s\n' "$file"
      return 0
    fi
  done < <(get_settings_files_to_scan)

  if [ -f "$HOME/.claude/.credentials.json" ]; then
    printf '检测到已有 Claude 登录凭证: %s\n' "$HOME/.claude/.credentials.json"
    return 0
  fi

  return 1
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

# 检测是否存在第三方（非 breakout.wenwen-ai.com）的 api_base_url 或 apiBaseUrl
# 返回 0 = 检测到第三方，返回 1 = 无需清理
is_third_party_config() {
  local existing_url existing_base
  local rc_file

  existing_url=$(get_existing_claude_url)
  existing_base=$(normalize_base_url "$existing_url")

  if [ -n "$existing_base" ] && [ "$existing_base" != "$(normalize_base_url "$API_BASE_URL")" ]; then
    return 0
  fi

  # 检测 claude-code-router config
  file_has_non_official_url "$HOME/.claude-code-router/config.json" '"api_base_url"' && return 0
  file_has_non_official_url "$HOME/.claude.json" '"apiBaseUrl"' && return 0

  if get_detected_third_party_reason >/dev/null; then
    return 0
  fi

  # 检测 shell rc 文件中的第三方 URL
  for rc_file in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zshrc"; do
    file_has_non_official_url "$rc_file" 'ANTHROPIC_BASE_URL' && return 0
  done

  # 检测当前会话里的第三方 URL
  if [ -n "$ANTHROPIC_BASE_URL" ] && ! is_official_base_url "$ANTHROPIC_BASE_URL"; then
    return 0
  fi

  return 1
}

# 清理第三方配置、包、环境变量及 claude 状态
cleanup_third_party() {
  local old_url
  local reason
  old_url=$(get_existing_claude_url)
  reason=$(get_detected_third_party_reason || true)

  warn "检测到第三方中转站配置: ${old_url:-（未知）}"
  [ -n "$reason" ] && warn "$reason"
  warn "将删除旧的 Claude 配置目录和错误 JSON，然后重建。"
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

  info "删除 Claude 配置目录 ~/.claude ..."
  rm -rf "$HOME/.claude"
  success "已删除 ~/.claude"

  if [ "$PWD" != "$HOME" ] && [ -d "$PWD/.claude" ]; then
    info "删除当前目录下的共享 Claude 配置 $PWD/.claude ..."
    rm -rf "$PWD/.claude"
    success "已删除 $PWD/.claude"
  fi

  info "删除错误的 ~/.claude.json ..."
  rm -f "$HOME/.claude.json"
  success "已删除 ~/.claude.json"

  if [ -f "/etc/claude-code/managed-settings.json" ] && [ -w "/etc/claude-code/managed-settings.json" ]; then
    info "删除系统级 Claude managed settings ..."
    rm -f "/etc/claude-code/managed-settings.json"
    success "已删除 /etc/claude-code/managed-settings.json"
  elif [ -f "/etc/claude-code/managed-settings.json" ]; then
    warn "检测到 /etc/claude-code/managed-settings.json，但当前无权限删除；它仍可能覆盖你的配置"
  fi

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
API_KEY=$(strip_line_breaks "$API_KEY")
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
MODEL=$(strip_line_breaks "$MODEL")
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
  NPM_GLOBAL_BIN=$(get_npm_global_bin)
  if [ -n "$NPM_GLOBAL_BIN" ]; then
    export PATH="${NPM_GLOBAL_BIN}:$PATH"
  fi
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
  DEFAULT_PROVIDER="${PROVIDER_NAME},${MODEL}"
  if command -v python3 &>/dev/null; then
    python3 - "$CONFIG_FILE" "$PROVIDER_NAME" "$(normalize_base_url "$API_BASE_URL")/v1/messages" "$API_KEY" "$MODEL" "$DEFAULT_PROVIDER" <<'PYEOF'
import json, sys

path, provider_name, api_base_url, api_key, model, default_provider = sys.argv[1:7]

config = {
    "LOG": False,
    "CLAUDE_PATH": "",
    "HOST": "127.0.0.1",
    "PORT": 3456,
    "APIKEY": api_key,
    "API_TIMEOUT_MS": "600000",
    "PROXY_URL": "",
    "Transformers": [],
    "Providers": [
        {
            "name": provider_name,
            "api_base_url": api_base_url,
            "api_key": api_key,
            "models": [model],
            "transformer": {"use": ["Anthropic"]},
        }
    ],
    "Router": {
        "default": default_provider,
        "background": default_provider,
        "think": default_provider,
        "longContext": default_provider,
        "longContextThreshold": 60000,
        "webSearch": default_provider,
    },
}

with open(path, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2)
PYEOF
  else
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
      "name": "${PROVIDER_NAME}",
      "api_base_url": "$(normalize_base_url "$API_BASE_URL")/v1/messages",
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
  fi
  chmod 600 "$CONFIG_FILE"
  if command -v python3 &>/dev/null; then
    python3 - "$CONFIG_FILE" <<'PYEOF'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    json.load(f)
PYEOF
  fi
  success "配置文件已写入: $CONFIG_FILE"
  GENERATED_URL=$(grep '"api_base_url"' "$CONFIG_FILE" | head -1 | grep -oE "https?://[^\"'[:space:]]+" | head -1 || true)
  info "已读取新配置: ${GENERATED_URL}"
fi

# ── 5.5 写入环境变量到 shell RC（Linux 直接读环境变量）────────
step "配置环境变量"

if [ -n "$ZSH_VERSION" ] || [ "$SHELL" = "/bin/zsh" ]; then
  ENV_RC="$HOME/.zshrc"
else
  ENV_RC="$HOME/.bashrc"
fi

# 先从所有 RC 文件删除旧的同名变量行（避免重复，覆盖所有可能的写入位置）
for _rc in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zshrc"; do
  if [ -f "$_rc" ]; then
    if grep -qE 'ANTHROPIC_AUTH_TOKEN|ANTHROPIC_API_KEY|ANTHROPIC_BASE_URL' "$_rc" 2>/dev/null; then
      info "在 $_rc 中发现旧 ANTHROPIC 环境变量，正在清除..."
      sed -i '/ANTHROPIC_AUTH_TOKEN/d' "$_rc"
      sed -i '/ANTHROPIC_API_KEY/d' "$_rc"
      sed -i '/ANTHROPIC_BASE_URL/d' "$_rc"
      success "已清除 $_rc 中的旧变量"
    fi
  fi
done

# 清除 OAuth 登录凭证（~/.claude/.credentials.json 存储 accessToken，Claude Code 启动时读取，
# 优先级高于 ANTHROPIC_API_KEY，导致 "Auth conflict: /login managed key" 错误）
CLAUDE_CREDS="$HOME/.claude/.credentials.json"
if [ -f "$CLAUDE_CREDS" ]; then
  info "发现 OAuth 登录凭证 ~/.claude/.credentials.json，正在删除..."
  rm -f "$CLAUDE_CREDS"
  success "已删除 OAuth 登录凭证，将使用 ANTHROPIC_API_KEY"
fi

# 清理 ~/.claude/settings.json 中的第三方 env 配置（优先级高于 shell 环境变量）
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [ -f "$CLAUDE_SETTINGS" ] && command -v python3 &>/dev/null; then
  info "正在清理 ~/.claude/settings.json 中的第三方配置..."
  python3 - "$CLAUDE_SETTINGS" <<'PYEOF'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        d = json.load(f)
    env = d.get('env', {})
    removed_env = [k for k in ['ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_BASE_URL', 'ANTHROPIC_API_KEY'] if k in env]
    env.pop('ANTHROPIC_AUTH_TOKEN', None)
    env.pop('ANTHROPIC_BASE_URL', None)
    env.pop('ANTHROPIC_API_KEY', None)
    if env:
        d['env'] = env
    elif 'env' in d:
        del d['env']
    # 同时清理顶层认证字段
    removed_top = [k for k in ['apiKey', 'authToken', 'sessionToken'] if k in d]
    d.pop('apiKey', None)
    d.pop('authToken', None)
    d.pop('sessionToken', None)
    with open(path, 'w') as f:
        json.dump(d, f, indent=2)
    if removed_env:
        print(f"  [settings.json] 已从 env 块移除: {', '.join(removed_env)}")
    if removed_top:
        print(f"  [settings.json] 已从顶层移除: {', '.join(removed_top)}")
    if not removed_env and not removed_top:
        print("  [settings.json] 无第三方配置，无需清理")
except Exception as e:
    print(f"  [settings.json] 解析失败: {e}")
PYEOF
elif [ -f "$CLAUDE_SETTINGS" ]; then
  warn "~/.claude/settings.json 存在但 python3 不可用，跳过清理（可能存在残留配置）"
fi

# 同样清理 settings.local.json（Claude Code 也会读取此文件）
CLAUDE_SETTINGS_LOCAL="$HOME/.claude/settings.local.json"
if [ -f "$CLAUDE_SETTINGS_LOCAL" ] && command -v python3 &>/dev/null; then
  python3 - "$CLAUDE_SETTINGS_LOCAL" <<'PYEOF'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        d = json.load(f)
    env = d.get('env', {})
    removed = [k for k in ['ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_BASE_URL', 'ANTHROPIC_API_KEY'] if k in env]
    for k in removed:
        env.pop(k)
    if env:
        d['env'] = env
    elif 'env' in d:
        del d['env']
    with open(path, 'w') as f:
        json.dump(d, f, indent=2)
    if removed:
        print(f"  [settings.local.json] 已移除: {', '.join(removed)}")
except Exception:
    pass
PYEOF
fi
# 同时在当前会话 unset，防止旧值（来自 RC 文件或 settings.json）干扰新 export
unset ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL ANTHROPIC_API_KEY 2>/dev/null || true

# 写入新值（用引号包裹 key 值，防止特殊字符导致 bash 解析错误）
echo "export ANTHROPIC_API_KEY=\"${API_KEY}\"" >> "$ENV_RC"
echo "export ANTHROPIC_BASE_URL=\"${API_BASE_URL}\"" >> "$ENV_RC"

# 同时在当前 shell 会话生效
export ANTHROPIC_API_KEY="${API_KEY}"
export ANTHROPIC_BASE_URL="${API_BASE_URL}"

success "环境变量已写入 ${ENV_RC}"

# 同步 Claude Code 全局 settings.json，避免 `curl | bash` 的子 shell export 无法传回父 shell
if command -v python3 &>/dev/null; then
  mkdir -p "$HOME/.claude"
  python3 - "$HOME/.claude/settings.json" "$API_KEY" "$API_BASE_URL" <<'PYEOF'
import json, os, sys
path, api_key, base_url = sys.argv[1], sys.argv[2], sys.argv[3]
data = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        data = {}
env = data.get('env', {})
env['ANTHROPIC_API_KEY'] = api_key
env['ANTHROPIC_BASE_URL'] = base_url
env.pop('ANTHROPIC_AUTH_TOKEN', None)
data['env'] = env
for key in ['apiKey', 'authToken', 'sessionToken']:
    data.pop(key, None)
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
PYEOF
  success "已同步 ~/.claude/settings.json 中的 API 环境"
else
  warn "未检测到 python3，无法同步 ~/.claude/settings.json，直接运行 claude 前请先 source ${ENV_RC}"
fi

# ── 5.6 写入 ~/.claude.json 跳过 Onboarding 登录向导 ─────────
step "初始化 Claude Code 状态"

CLAUDE_JSON="$HOME/.claude.json"
CLAUDE_VERSION=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "2.1.0")

if [ ! -f "$CLAUDE_JSON" ]; then
  cat > "$CLAUDE_JSON" <<CLAUDEJSON
{
  "hasCompletedOnboarding": true,
  "lastOnboardingVersion": "${CLAUDE_VERSION}",
  "primaryApiKey": "${API_KEY}"
}
CLAUDEJSON
  success "已创建 ~/.claude.json，并写入 primaryApiKey"
else
  if command -v python3 &>/dev/null; then
    python3 - "$CLAUDE_JSON" "$CLAUDE_VERSION" "$API_KEY" <<'PYEOF'
import json, sys
path, ver, api_key = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    d = json.load(f)
d['hasCompletedOnboarding'] = True
d['lastOnboardingVersion'] = ver
d['primaryApiKey'] = api_key
d.pop('apiBaseUrl', None)
d.pop('oauthAccount', None)
d.pop('authToken', None)
d.pop('sessionToken', None)
with open(path, 'w') as f:
    json.dump(d, f, indent=2)
PYEOF
    success "已更新 ~/.claude.json（已写入 primaryApiKey）"
  else
    cat > "$CLAUDE_JSON" <<CLAUDEJSON
{
  "hasCompletedOnboarding": true,
  "lastOnboardingVersion": "${CLAUDE_VERSION}",
  "primaryApiKey": "${API_KEY}"
}
CLAUDEJSON
    success "已覆盖写入 ~/.claude.json（已写入 primaryApiKey）"
  fi
fi

# ── 6. 完成 ──────────────────────────────────────────────────
step "完成"

GLOBAL_BIN=$(get_npm_global_bin)

echo ""
echo -e "${GREEN}${BOLD}✅ Claude Code 部署完成！${NC}"
echo ""
echo -e "${CYAN}使用方法:${NC}"
echo "  ccr code          # 推荐：通过 claude-code-router 启动 Claude Code"
echo "  claude            # 直接启动 Claude Code"
echo ""

echo -e "${CYAN}说明:${NC}"
echo "  curl | bash 安装无法把 export 回写到你当前父 shell。"
echo "  已写入 ${ENV_RC}，并同步到 ~/.claude/settings.json。"
echo "  如果直接运行 claude 仍提示未登录，请先执行: source ${ENV_RC}"
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
echo "  如果仍弹出登录界面，请检查 ~/.claude.json 是否包含:"
echo "    \"hasCompletedOnboarding\": true"
echo "    \"primaryApiKey\": \"***\""
echo ""

# 诊断总结：打印当前生效的关键环境变量（API Key 脱敏）
echo -e "${CYAN}${BOLD}── 当前环境变量诊断 ────────────────────────────────${NC}"
_key_display="${ANTHROPIC_API_KEY:0:10}..."
_token_display="${ANTHROPIC_AUTH_TOKEN:-(未设置，正常)}"
echo "  ANTHROPIC_API_KEY  : ${_key_display}"
echo "  ANTHROPIC_BASE_URL : ${ANTHROPIC_BASE_URL}"
echo "  ANTHROPIC_AUTH_TOKEN: ${_token_display}"
if [ -n "$ANTHROPIC_AUTH_TOKEN" ]; then
  warn "ANTHROPIC_AUTH_TOKEN 仍然存在！请检查 ~/.claude/settings.json 或 RC 文件是否有残留"
else
  success "无 Auth Token 冲突，Claude Code 将使用 ANTHROPIC_API_KEY"
fi
echo ""
