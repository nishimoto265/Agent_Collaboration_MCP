#!/bin/bash

# 🎮 Pane Controller - tmuxペイン制御ツール
# 各エージェントペインを制御するための基本ツール

set -e

# 共通ライブラリの読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"
setup_directories "$SCRIPT_DIR"

QUICK_SEND_SCRIPT="$MULTIAGENT_DIR/quick_send_with_verify.sh"

# ログ関数のエイリアス（後方互換性のため）
log_info() { log "INFO" "$1" "INFO"; }
log_error() { log "ERROR" "$1" "ERROR"; }
log_success() { log "SUCCESS" "$1" "SUCCESS"; }

# ペイン番号取得は共通ライブラリの関数を使用
# get_pane_number() は utils.sh で定義済み

# ペイン番号→名前変換（utils.shで定義済みのため削除）
# get_pane_name() は common/utils.sh で定義されています

# tmuxセッション存在確認
check_tmux_session() {
    if ! check_session_exists; then
        log_error "tmuxセッション '$TMUX_SESSION' が存在しません"
        echo "セッションを作成するには以下を実行してください:"
        echo "  scripts/multiagent/create_multiagent_tmux.sh"
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
        local target=$(get_tmux_target "$pane_num")
        tmux send-keys -t "$target" "$message"
        if [ "$enter" = "true" ]; then
            tmux send-keys -t "$target" C-m
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
    local target=$(get_tmux_target "$pane_num")
    tmux send-keys -t "$target" C-l
    
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
    local target=$(get_tmux_target "$pane_num")
    tmux send-keys -t "$target" C-c
    delay "$MEDIUM_DELAY"
    tmux send-keys -t "$target" C-c
    delay "$MEDIUM_DELAY"
    
    # コマンド送信
    tmux send-keys -t "$target" "$command" C-m
    
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
    local target=$(get_tmux_target "$pane_num")
    tmux send-keys -t "$target" C-c
    delay "$MEDIUM_DELAY"
    tmux send-keys -t "$target" C-c
    delay "$MEDIUM_DELAY"
    
    if [ "$force" = "true" ]; then
        # 強制停止の場合は追加でCtrl+Cを送信
        tmux send-keys -t "$target" C-c
        delay "$MEDIUM_DELAY"
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
        local panes=$(get_all_panes)
        for i in $panes; do
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