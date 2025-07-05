#!/bin/bash
# 端末とtmuxセッションの自動起動（修正版）

# ログ関数の定義
log_info() {
    echo "[INFO] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_success() {
    echo "[SUCCESS] $*" >&2
}

# サポートされる端末エミュレータを検出
detect_terminal() {
    if command -v gnome-terminal >/dev/null 2>&1; then
        echo "gnome-terminal"
    elif command -v konsole >/dev/null 2>&1; then
        echo "konsole"
    elif command -v xterm >/dev/null 2>&1; then
        echo "xterm"
    elif command -v alacritty >/dev/null 2>&1; then
        echo "alacritty"
    elif command -v kitty >/dev/null 2>&1; then
        echo "kitty"
    elif command -v wezterm >/dev/null 2>&1; then
        echo "wezterm"
    elif [ "$(uname)" = "Darwin" ]; then
        echo "terminal"
    else
        echo "none"
    fi
}

# 新しい端末でtmuxセッションを起動
launch_terminal_with_tmux() {
    local session_name="$1"
    local worker_count="$2"
    local working_dir="${3:-$(pwd)}"
    local terminal_type=$(detect_terminal)
    
    log_info "端末タイプ: $terminal_type"
    log_info "tmuxセッション作成: $session_name (ワーカー数: $worker_count)"
    
    # tmuxセッションが既に存在する場合は削除
    tmux kill-session -t "$session_name" 2>/dev/null || true
    
    # tmuxコマンドを直接実行
    local tmux_cmd="tmux new-session -d -s '$session_name' -c '$working_dir' && "
    
    # Boss + Worker構成の場合
    if [ "$worker_count" -gt 1 ]; then
        tmux_cmd+="tmux rename-window -t '${session_name}:0' 'Boss' && "
        
        # Worker用のペインを追加（Boss + worker_count個のペインを作成）
        for i in $(seq 1 $worker_count); do
            tmux_cmd+="tmux split-window -t '${session_name}:0' -h -c '$working_dir' && "
            tmux_cmd+="tmux select-layout -t '${session_name}:0' even-horizontal && "
        done
        
        # ペインにラベルを設定
        tmux_cmd+="tmux select-pane -t '${session_name}:0.0' -T 'Boss' && "
        for i in $(seq 1 $worker_count); do
            tmux_cmd+="tmux select-pane -t '${session_name}:0.$i' -T 'Worker$i' && "
        done
    else
        # Worker1つのみの場合
        tmux_cmd+="tmux rename-window -t '${session_name}:0' 'Worker1' && "
        tmux_cmd+="tmux select-pane -t '${session_name}:0.0' -T 'Worker1' && "
    fi
    
    # ステータスバー設定
    tmux_cmd+="tmux set-option -t '$session_name' status-left '[Parallel] ' && "
    tmux_cmd+="tmux set-option -t '$session_name' status-right '#[fg=green]Workers: $worker_count #[default]| %H:%M' && "
    
    # ペインタイトル表示設定
    tmux_cmd+="tmux set-option -t '$session_name' pane-border-status top && "
    tmux_cmd+="tmux set-option -t '$session_name' pane-border-format ' #{pane_index}: #{pane_title} ' && "
    tmux_cmd+="tmux set-option -t '$session_name' pane-border-style fg=blue && "
    tmux_cmd+="tmux set-option -t '$session_name' pane-active-border-style fg=red,bold && "
    
    # 最後にアタッチ
    tmux_cmd+="tmux attach-session -t '$session_name'"
    
    # 端末タイプに応じて起動
    case "$terminal_type" in
        "gnome-terminal")
            gnome-terminal --title="Parallel Implementation: $session_name" \
                          --geometry=200x50 \
                          -- bash -c "$tmux_cmd"
            ;;
        "konsole")
            konsole --title "Parallel Implementation: $session_name" \
                    --geometry 200x50 \
                    -e bash -c "$tmux_cmd"
            ;;
        "xterm")
            xterm -title "Parallel Implementation: $session_name" \
                  -geometry 200x50 \
                  -e bash -c "$tmux_cmd" &
            ;;
        "alacritty")
            alacritty --title "Parallel Implementation: $session_name" \
                      --dimensions 200 50 \
                      -e bash -c "$tmux_cmd" &
            ;;
        "kitty")
            kitty --title "Parallel Implementation: $session_name" \
                  --override initial_window_width=200 \
                  --override initial_window_height=50 \
                  bash -c "$tmux_cmd" &
            ;;
        "wezterm")
            wezterm start --cwd "$working_dir" \
                    -- bash -c "$tmux_cmd" &
            ;;
        "terminal")
            # macOS Terminal.app
            osascript <<EOF
tell application "Terminal"
    do script "$tmux_cmd"
    set current settings of front window to settings set "Pro"
    set bounds of front window to {100, 100, 1400, 900}
end tell
EOF
            ;;
        *)
            log_error "サポートされている端末が見つかりません"
            return 1
            ;;
    esac
    
    # tmuxセッションが起動するまで待機
    local max_wait=30
    local count=0
    while [ $count -lt $max_wait ]; do
        if tmux has-session -t "$session_name" 2>/dev/null; then
            log_success "tmuxセッション起動完了: $session_name"
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    
    log_error "tmuxセッション起動タイムアウト"
    return 1
}

# 並列実装用の専用セッションを作成
create_parallel_session() {
    local base_name="$1"
    local worker_count="$2"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local session_name="parallel_${base_name}_${timestamp}"
    
    # 新しい端末でtmuxセッションを起動
    if launch_terminal_with_tmux "$session_name" "$worker_count"; then
        echo "$session_name"
        return 0
    else
        return 1
    fi
}

# メイン処理
main() {
    local command="${1:-}"
    shift || true
    
    case "$command" in
        "launch")
            launch_terminal_with_tmux "$@"
            ;;
        "create-parallel")
            create_parallel_session "$@"
            ;;
        "detect")
            detect_terminal
            ;;
        *)
            echo "使用法: $0 {launch|create-parallel|detect} [options]"
            echo ""
            echo "コマンド:"
            echo "  launch <session_name> <worker_count> [working_dir]"
            echo "  create-parallel <base_name> <worker_count>"
            echo "  detect"
            exit 1
            ;;
    esac
}

# 実行
main "$@"