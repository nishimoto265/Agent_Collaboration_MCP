#!/bin/bash

# 🎮 Pane Controller - tmuxペイン制御ツール
# Presidentが各エージェントペインを制御するための基本ツール

set -e

# MCPディレクトリ内で完全に完結する設定
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# MCPディレクトリ内のスクリプトを使用
PROJECT_DIR="$(cd "$MCP_DIR/../.." && pwd)"  # MCPの2つ上がプロジェクトルート
QUICK_SEND_SCRIPT="$MCP_DIR/scripts/multiagent/quick_send_with_verify.sh"

# ログ関数
log_info() {
    echo -e "\033[1;32m[INFO]\033[0m $1"
}

log_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
}

log_success() {
    echo -e "\033[1;34m[SUCCESS]\033[0m $1"
}

# ペイン番号マッピング（組織ブロック順序構成）
get_pane_number() {
    case "$1" in
        "boss01") echo "0" ;;
        "worker-a01") echo "1" ;;
        "worker-b01") echo "2" ;;
        "worker-c01") echo "3" ;;
        "boss02") echo "4" ;;
        "worker-a02") echo "5" ;;
        "worker-b02") echo "6" ;;
        "worker-c02") echo "7" ;;
        "boss03") echo "8" ;;
        "worker-a03") echo "9" ;;
        "worker-b03") echo "10" ;;
        "worker-c03") echo "11" ;;
        "boss04") echo "12" ;;
        "worker-a04") echo "13" ;;
        "worker-b04") echo "14" ;;
        "worker-c04") echo "15" ;;
        "president") echo "16" ;;
        "auth-helper") echo "17" ;;
        [0-9]|1[0-7]) echo "$1" ;;  # 数値の場合はそのまま
        *) echo "" ;;
    esac
}

# ペイン番号→名前変換
get_pane_name() {
    case "$1" in
        0) echo "boss01" ;;
        1) echo "worker-a01" ;;
        2) echo "worker-b01" ;;
        3) echo "worker-c01" ;;
        4) echo "boss02" ;;
        5) echo "worker-a02" ;;
        6) echo "worker-b02" ;;
        7) echo "worker-c02" ;;
        8) echo "boss03" ;;
        9) echo "worker-a03" ;;
        10) echo "worker-b03" ;;
        11) echo "worker-c03" ;;
        12) echo "boss04" ;;
        13) echo "worker-a04" ;;
        14) echo "worker-b04" ;;
        15) echo "worker-c04" ;;
        16) echo "president" ;;
        17) echo "auth-helper" ;;
        *) echo "unknown" ;;
    esac
}

# tmuxセッション存在確認
check_tmux_session() {
    if ! tmux has-session -t multiagent 2>/dev/null; then
        log_error "tmuxセッション 'multiagent' が存在しません"
        echo "セッションを作成するには以下を実行してください:"
        echo "  scripts/multiagent/create_multiagent_tmux.sh"
        return 1
    fi
    return 0
}

# ペイン存在確認
check_pane_exists() {
    local pane_num="$1"
    if ! tmux list-panes -t "multiagent:0" -F "#{pane_index}" 2>/dev/null | grep -q "^${pane_num}$"; then
        log_error "ペイン $pane_num が存在しません"
        return 1
    fi
    return 0
}

# メッセージ送信
send_message() {
    local pane="$1"
    local message="$2"
    local enter="${3:-true}"  # デフォルトはEnter送信あり
    
    local pane_num=$(get_pane_number "$pane")
    if [ -z "$pane_num" ]; then
        log_error "無効なペイン指定: $pane"
        return 1
    fi
    
    check_tmux_session || return 1
    check_pane_exists "$pane_num" || return 1
    
    log_info "ペイン $pane (番号: $pane_num) にメッセージ送信中..."
    
    # quick_send_with_verify.shが存在する場合は使用
    if [ -f "$QUICK_SEND_SCRIPT" ]; then
        "$QUICK_SEND_SCRIPT" "$pane" "$message" --no-verify
    else
        # 直接tmux send-keys使用
        tmux send-keys -t "multiagent:0.$pane_num" "$message"
        if [ "$enter" = "true" ]; then
            tmux send-keys -t "multiagent:0.$pane_num" C-m
        fi
    fi
    
    log_success "メッセージ送信完了"
}

# 画面キャプチャ
capture_screen() {
    local pane="$1"
    local lines="$2"  # 行数指定（オプション）
    
    local pane_num=$(get_pane_number "$pane")
    if [ -z "$pane_num" ]; then
        log_error "無効なペイン指定: $pane"
        return 1
    fi
    
    check_tmux_session || return 1
    check_pane_exists "$pane_num" || return 1
    
    # 行数指定がある場合は -S オプションを使用
    if [ -n "$lines" ] && [[ "$lines" =~ ^-?[0-9]+$ ]]; then
        if [[ "$lines" =~ ^- ]]; then
            # 負の数の場合（例: -5 = 最後の5行）
            tmux capture-pane -t "multiagent:0.$pane_num" -p -S "$lines" 2>/dev/null || {
                log_error "画面キャプチャ失敗"
                return 1
            }
        else
            # 正の数の場合（例: 5 = 最初の5行）
            tmux capture-pane -t "multiagent:0.$pane_num" -p -E "$lines" 2>/dev/null || {
                log_error "画面キャプチャ失敗"
                return 1
            }
        fi
    else
        # 行数指定なしの場合は全履歴
        tmux capture-pane -t "multiagent:0.$pane_num" -p -S - 2>/dev/null || {
            log_error "画面キャプチャ失敗"
            return 1
        }
    fi
}

# ペインクリア
clear_pane() {
    local pane="$1"
    
    local pane_num=$(get_pane_number "$pane")
    if [ -z "$pane_num" ]; then
        log_error "無効なペイン指定: $pane"
        return 1
    fi
    
    check_tmux_session || return 1
    check_pane_exists "$pane_num" || return 1
    
    log_info "ペイン $pane (番号: $pane_num) をクリア中..."
    
    # Ctrl+L でクリア
    tmux send-keys -t "multiagent:0.$pane_num" C-l
    
    log_success "ペインクリア完了"
}

# コマンド実行
execute_command() {
    local pane="$1"
    local command="$2"
    
    local pane_num=$(get_pane_number "$pane")
    if [ -z "$pane_num" ]; then
        log_error "無効なペイン指定: $pane"
        return 1
    fi
    
    check_tmux_session || return 1
    check_pane_exists "$pane_num" || return 1
    
    log_info "ペイン $pane (番号: $pane_num) でコマンド実行中: $command"
    
    # Ctrl+C を2回送信して現在のプロセスを確実に中断
    tmux send-keys -t "multiagent:0.$pane_num" C-c
    sleep 0.2
    tmux send-keys -t "multiagent:0.$pane_num" C-c
    sleep 0.5
    
    # コマンド送信
    tmux send-keys -t "multiagent:0.$pane_num" "$command" C-m
    
    log_success "コマンド実行開始"
}

# プロセス停止
stop_process() {
    local pane="$1"
    local force="${2:-false}"
    
    local pane_num=$(get_pane_number "$pane")
    if [ -z "$pane_num" ]; then
        log_error "無効なペイン指定: $pane"
        return 1
    fi
    
    check_tmux_session || return 1
    check_pane_exists "$pane_num" || return 1
    
    log_info "ペイン $pane (番号: $pane_num) のプロセスを停止中..."
    
    # Ctrl+C を2回送信（デフォルト）
    tmux send-keys -t "multiagent:0.$pane_num" C-c
    sleep 0.2
    tmux send-keys -t "multiagent:0.$pane_num" C-c
    sleep 0.2
    
    if [ "$force" = "true" ]; then
        # 強制停止の場合は追加でCtrl+Cを送信
        tmux send-keys -t "multiagent:0.$pane_num" C-c
        sleep 0.2
    fi
    
    log_success "プロセス停止シグナル送信完了"
}

# ペイン状態確認
check_status() {
    local pane="$1"
    
    if [ -z "$pane" ]; then
        # 全ペイン状態表示
        log_info "全ペイン状態:"
        echo "=================================="
        for i in {0..16}; do
            local name=$(get_pane_name $i)
            local last_line=$(capture_screen $i "-1" 2>/dev/null | tail -1 | sed 's/[[:space:]]*$//')
            printf "%-12s (pane %2d): %s\n" "$name" "$i" "${last_line:-(empty)}"
        done
    else
        # 特定ペイン状態
        local pane_num=$(get_pane_number "$pane")
        if [ -z "$pane_num" ]; then
            log_error "無効なペイン指定: $pane"
            return 1
        fi
        
        check_tmux_session || return 1
        check_pane_exists "$pane_num" || return 1
        
        echo "ペイン $pane (番号: $pane_num) の状態:"
        echo "=================================="
        capture_screen "$pane" "-10" | cat -n
    fi
}

# ヘルプ表示
show_usage() {
    cat << EOF
🎮 Pane Controller - tmuxペイン制御ツール

使用方法:
  $(basename $0) <command> [options]

コマンド:
  send <pane> <message>     メッセージ送信
  capture <pane> [lines]    画面内容取得（デフォルト:全履歴）
  clear <pane>              ペインクリア
  exec <pane> <command>     コマンド実行
  stop <pane> [force]       プロセス停止
  status [pane]             状態確認（省略時:全ペイン）
  
ペイン指定:
  - 名前: boss01, worker-a01, ..., president
  - 番号: 0-16

例:
  $(basename $0) send worker-a01 "タスクを開始してください"
  $(basename $0) capture boss01 -20
  $(basename $0) exec worker-b02 "claude --dangerously-skip-permissions"
  $(basename $0) stop worker-a01 force
  $(basename $0) status
EOF
}

# メイン処理
main() {
    case "${1:-}" in
        "send")
            shift
            if [ $# -lt 2 ]; then
                log_error "使用法: send <pane> <message>"
                exit 1
            fi
            send_message "$@"
            ;;
        "capture")
            shift
            if [ $# -lt 1 ]; then
                log_error "使用法: capture <pane> [lines]"
                exit 1
            fi
            capture_screen "$@"
            ;;
        "clear")
            shift
            if [ $# -lt 1 ]; then
                log_error "使用法: clear <pane>"
                exit 1
            fi
            clear_pane "$@"
            ;;
        "exec")
            shift
            if [ $# -lt 2 ]; then
                log_error "使用法: exec <pane> <command>"
                exit 1
            fi
            execute_command "$@"
            ;;
        "stop")
            shift
            if [ $# -lt 1 ]; then
                log_error "使用法: stop <pane> [force]"
                exit 1
            fi
            stop_process "$@"
            ;;
        "status")
            shift
            check_status "$@"
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        *)
            log_error "不明なコマンド: $1"
            show_usage
            exit 1
            ;;
    esac
}

# スクリプト実行
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi