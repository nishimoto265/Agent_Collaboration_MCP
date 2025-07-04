#!/bin/bash

# 🔧 共通設定ファイル
# 全スクリプトで使用される設定値を一元管理

# セッション設定
export TMUX_SESSION="${TMUX_SESSION:-multiagent}"
export TMUX_WINDOW="${TMUX_WINDOW:-0}"

# ログ設定
export LOG_DIR="${LOG_DIR:-logs/message_delivery}"
export LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-7}"

# タイムアウト設定（秒）
export DEFAULT_WAIT_TIMEOUT="${DEFAULT_WAIT_TIMEOUT:-20}"
export AUTH_WAIT_TIMEOUT="${AUTH_WAIT_TIMEOUT:-150}"
export DELEGATOR_WAIT_TIMEOUT="${DELEGATOR_WAIT_TIMEOUT:-120}"
export AGENT_START_TIMEOUT="${AGENT_START_TIMEOUT:-300}"

# リトライ設定
export MAX_RETRY_COUNT="${MAX_RETRY_COUNT:-3}"
export RETRY_DELAY="${RETRY_DELAY:-1}"

# 待機時間設定（秒）
export SHORT_DELAY="${SHORT_DELAY:-0.1}"
export MEDIUM_DELAY="${MEDIUM_DELAY:-0.5}"
export LONG_DELAY="${LONG_DELAY:-2}"

# エージェントコマンド設定
declare -gA AGENT_COMMANDS
AGENT_COMMANDS["claude"]="${CLAUDE_COMMAND:-claude --dangerously-skip-permissions}"
AGENT_COMMANDS["gemini"]="${GEMINI_COMMAND:-gemini}"
AGENT_COMMANDS["gpt"]="${GPT_COMMAND:-gpt}"
AGENT_COMMANDS["python"]="${PYTHON_COMMAND:-python3}"
AGENT_COMMANDS["bash"]="${BASH_COMMAND:-bash}"

# エージェント説明
declare -gA AGENT_DESCRIPTIONS
AGENT_DESCRIPTIONS["claude"]="Claude Code - 汎用AI開発環境"
AGENT_DESCRIPTIONS["gemini"]="Gemini CLI - 画像生成・マルチモーダル"
AGENT_DESCRIPTIONS["gpt"]="GPT CLI - OpenAI モデル"
AGENT_DESCRIPTIONS["python"]="Python インタープリタ"
AGENT_DESCRIPTIONS["bash"]="Bash シェル"

# ディレクトリ設定の初期化
setup_directories() {
    # スクリプトディレクトリから相対的にMCPディレクトリを計算
    local script_dir="$1"
    export MCP_DIR="$(cd "$script_dir/../.." && pwd)"
    export PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
    
    # スクリプトパス
    export SCRIPTS_DIR="$MCP_DIR/scripts"
    export AGENT_TOOLS_DIR="$SCRIPTS_DIR/agent_tools"
    export MULTIAGENT_DIR="$SCRIPTS_DIR/multiagent"
    export UTILITIES_DIR="$SCRIPTS_DIR/utilities"
    export COMMON_DIR="$SCRIPTS_DIR/common"
}

# ログディレクトリの作成
ensure_log_directory() {
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
    fi
}

# 古いログの削除
cleanup_old_logs() {
    if [ -d "$LOG_DIR" ]; then
        find "$LOG_DIR" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null || true
    fi
}