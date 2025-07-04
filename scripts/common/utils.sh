#!/bin/bash

# 🛠️ 共通ユーティリティ関数
# 全スクリプトで使用される共通関数を一元管理

# 設定ファイルの読み込み
COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$COMMON_DIR/config.sh"

# カラー定義
export COLOR_RESET="\033[0m"
export COLOR_RED="\033[1;31m"
export COLOR_GREEN="\033[1;32m"
export COLOR_YELLOW="\033[1;33m"
export COLOR_BLUE="\033[1;34m"
export COLOR_PURPLE="\033[1;35m"
export COLOR_CYAN="\033[1;36m"

# ログ関数の統一
log() {
    local level="$1"
    local message="$2"
    local prefix="$3"
    
    case "$level" in
        "ERROR")
            echo -e "${COLOR_RED}[${prefix:-ERROR}]${COLOR_RESET} $message" >&2
            ;;
        "SUCCESS")
            echo -e "${COLOR_GREEN}[${prefix:-SUCCESS}]${COLOR_RESET} $message"
            ;;
        "WARN")
            echo -e "${COLOR_YELLOW}[${prefix:-WARN}]${COLOR_RESET} $message"
            ;;
        "INFO")
            echo -e "${COLOR_BLUE}[${prefix:-INFO}]${COLOR_RESET} $message"
            ;;
        "DEBUG")
            [ "${DEBUG:-false}" = "true" ] && echo -e "${COLOR_PURPLE}[${prefix:-DEBUG}]${COLOR_RESET} $message"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# ペイン番号取得（汎用的）
get_pane_number() {
    local input="$1"
    local pane_count=$(tmux list-panes -t "$TMUX_SESSION" -F "#{pane_index}" 2>/dev/null | wc -l)
    
    # 数値チェック
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        # 有効範囲チェック
        if [ "$input" -lt "$pane_count" ]; then
            echo "$input"
        else
            echo ""
        fi
        return
    fi
    
    # 名前は使用しない（ペイン番号のみ使用）
    echo ""
}

# セッションの存在確認
check_session_exists() {
    local session="${1:-$TMUX_SESSION}"
    tmux has-session -t "$session" 2>/dev/null
}

# ペインの存在確認
check_pane_exists() {
    local pane="$1"
    local session="${2:-$TMUX_SESSION}"
    
    if [ -z "$pane" ]; then
        return 1
    fi
    
    tmux list-panes -t "$session" -F "#{pane_index}" 2>/dev/null | grep -q "^${pane}$"
}

# tmuxターゲット形式の生成
get_tmux_target() {
    local pane="$1"
    local window="${2:-$TMUX_WINDOW}"
    local session="${3:-$TMUX_SESSION}"
    
    echo "${session}:${window}.${pane}"
}

# ペイン数の取得
get_pane_count() {
    local session="${1:-$TMUX_SESSION}"
    tmux list-panes -t "$session" -F "#{pane_index}" 2>/dev/null | wc -l
}

# 全ペインのリスト取得
get_all_panes() {
    local session="${1:-$TMUX_SESSION}"
    tmux list-panes -t "$session" -F "#{pane_index}" 2>/dev/null | sort -n
}


# ペイン名取得（tmuxペインタイトルから動的に取得）
get_pane_name() {
    local pane_num="${1:-}"
    local session="${2:-$TMUX_SESSION}"
    local window="${3:-$TMUX_WINDOW}"
    
    if [ -z "$pane_num" ]; then
        echo ""
        return 1
    fi
    
    # tmuxのペインタイトルを取得
    local pane_title=$(tmux display-message -t "${session}:${window}.${pane_num}" -p '#{pane_title}' 2>/dev/null || echo "")
    
    # デフォルトのシェル名（bash, zsh等）の場合は空文字列を返す
    if [ -z "$pane_title" ] || [ "$pane_title" = "bash" ] || [ "$pane_title" = "zsh" ] || [ "$pane_title" = "sh" ]; then
        echo ""
    else
        echo "$pane_title"
    fi
}

# 遅延実行
delay() {
    local delay_time="${1:-$SHORT_DELAY}"
    sleep "$delay_time"
}

# 画面内容の取得（エラーハンドリング付き）
capture_pane_content() {
    local pane="$1"
    local lines="${2:--S -}"  # デフォルトは全履歴
    local target=$(get_tmux_target "$pane")
    
    tmux capture-pane -t "$target" -p $lines 2>/dev/null || echo ""
}




