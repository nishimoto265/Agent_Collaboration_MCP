#!/bin/bash

# 🤖 Agent Manager - エージェント管理ツール
# 各ペインのエージェントを動的に管理

set -e

# 共通ライブラリの読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"
setup_directories "$SCRIPT_DIR"

# スクリプトパスの設定
PANE_CONTROLLER="$SCRIPT_DIR/pane_controller.sh"
AUTH_HELPER="$SCRIPT_DIR/auth_helper.sh"

# エージェント設定ファイル
AGENT_AUTH_CONFIG="$PROJECT_DIR/.agent_auth_config.json"

# ログ関数のエイリアス（後方互換性のため）
log_info() { log "INFO" "$1" "AGENT"; }
log_error() { log "ERROR" "$1" "ERROR"; }
log_success() { log "SUCCESS" "$1" "SUCCESS"; }
log_warn() { log "WARN" "$1" "WARN"; }

# エージェントタイプ定義は共通設定から取得
# AGENT_COMMANDS と AGENT_DESCRIPTIONS は config.sh で定義済み

# ペイン番号取得（汎用的）
get_pane_number() {
    local input="$1"
    local pane_count=$(get_pane_count)
    
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

# 画面から直接エージェント状態を取得
get_agent_state() {
    local pane="$1"
    local pane_num=$(get_pane_number "$pane")
    
    if [ -z "$pane_num" ]; then
        echo "stopped"
        return 1
    fi
    
    # 画面内容から状態を判定
    local auth_state=$("$AUTH_HELPER" check "$pane" 2>/dev/null || echo "stopped")
    
    case "$auth_state" in
        "authenticated")
            echo "running"
            ;;
        "auth_required"|"browser_auth"|"theme_selection"|"permission_prompt"|"continue_prompt"|"terminal_setup")
            echo "auth_pending"
            ;;
        *)
            echo "stopped"
            ;;
    esac
}

# エージェント起動
start_agent() {
    local pane="$1"
    local agent_type="${2:-claude}"
    shift 2
    local additional_args="$@"
    
    local pane_num=$(get_pane_number "$pane")
    if [ -z "$pane_num" ]; then
        log_error "無効なペイン指定: $pane"
        return 1
    fi
    
    # エージェントタイプ確認
    if [ -z "${AGENT_COMMANDS[$agent_type]}" ] && [ "$agent_type" != "custom" ]; then
        log_error "不明なエージェントタイプ: $agent_type"
        log_info "利用可能: ${!AGENT_COMMANDS[@]}"
        return 1
    fi
    
    # 現在の状態確認
    local current_status=$(get_agent_state "$pane")
    
    if [ "$current_status" = "running" ]; then
        log_warn "ペイン $pane でエージェントが実行中です - 停止して新しいエージェントを起動します"
        stop_agent "$pane"
        sleep 1
    fi
    
    # コマンド決定
    local command
    if [ "$agent_type" = "custom" ]; then
        command="$additional_args"
        log_info "カスタムコマンド起動: $command"
    else
        command="${AGENT_COMMANDS[$agent_type]} $additional_args"
        log_info "$agent_type 起動中 (ペイン $pane)"
    fi
    
    # エージェント起動
    "$PANE_CONTROLLER" exec "$pane" "$command"
    
    # エージェントタイプ別の認証・起動確認
    log_info "$agent_type 認証/起動プロセスを監視中..."
    
    # Geminiの場合は認証状態を定期的にチェック
    if [ "$agent_type" = "gemini" ]; then
        # 一旦認証待機状態をチェック
        sleep 3
        local auth_state=$("$AUTH_HELPER" check "$pane" 2>&1 | grep -o "auth_required\|authenticated" || echo "unknown")
        if [ "$auth_state" = "auth_required" ]; then
            log_warn "Gemini認証待機中 - 手動で認証を完了してください"
        fi
    fi
    
    if "$AUTH_HELPER" wait "$pane" 300 "$agent_type"; then
        log_success "$agent_type 起動・認証完了"
    else
        log_error "$agent_type 認証/起動失敗"
        return 1
    fi
    
    return 0
}

# エージェント停止
stop_agent() {
    local pane="$1"
    local force="${2:-false}"
    
    local pane_num=$(get_pane_number "$pane")
    if [ -z "$pane_num" ]; then
        log_error "無効なペイン指定: $pane"
        return 1
    fi
    
    log_info "エージェント停止中 (ペイン $pane)"
    
    # プロセス停止
    "$PANE_CONTROLLER" stop "$pane" "$force"
    
    log_success "エージェント停止完了"
}

# エージェント再起動
restart_agent() {
    local pane="$1"
    local new_agent_type="$2"
    shift 2
    local additional_args="$@"
    
    # 新しいタイプが指定されていない場合はclaudeを使用
    if [ -z "$new_agent_type" ]; then
        new_agent_type="claude"
    fi
    
    log_info "エージェント再起動: → $new_agent_type"
    
    # 停止
    stop_agent "$pane" true
    sleep 2
    
    # 起動
    start_agent "$pane" "$new_agent_type" $additional_args
}

# エージェント状態確認
check_agent_status() {
    local pane="$1"
    
    if [ -z "$pane" ]; then
        # 全ペイン状態表示
        log_info "全エージェント状態:"
        echo "============================================"
        printf "%-12s %-10s %-10s %s\n" "ペイン" "タイプ" "状態" "最終更新"
        echo "--------------------------------------------"
        
        # 実際に存在するペインを動的に取得
        local pane_list=$(get_all_panes)
        local pane_count=$(echo "$pane_list" | wc -w)
        
        for i in $pane_list; do
            local name="pane-$i"
            
            # 画面から直接状態を取得
            local status=$(get_agent_state $i)
            local auth_detail=$("$AUTH_HELPER" check "$i" 2>/dev/null || echo "stopped")
            local agent_type="unknown"
            
            # エージェントタイプを画面から推定
            local screen=$("$PANE_CONTROLLER" capture "$i" 2>/dev/null || echo "")
            if echo "$screen" | grep -q "claude\|Claude"; then
                agent_type="claude"
            elif echo "$screen" | grep -q "gemini\|Gemini"; then
                agent_type="gemini"
            elif echo "$screen" | grep -q "python\|Python\|>>>"; then
                agent_type="python"
            elif echo "$screen" | grep -q "bash\|\$"; then
                agent_type="bash"
            fi
            
            # 状態アイコン
            local status_icon
            case "$status" in
                "running") status_icon="🟢" ;;
                "auth_pending") status_icon="🔄" ;;
                "stopped") status_icon="⚫" ;;
                *) status_icon="❓" ;;
            esac
            
            local timestamp=$(date +"%H:%M:%S")
            printf "%-12s %-10s %s %-12s %s\n" "$name" "$agent_type" "$status_icon" "$status" "$timestamp"
        done
        
        # サマリー
        echo "============================================"
        local running=0
        local auth_pending=0
        local total=$pane_count
        
        for i in $pane_list; do
            local status=$(get_agent_state $i)
            case "$status" in
                "running") running=$((running + 1)) ;;
                "auth_pending") auth_pending=$((auth_pending + 1)) ;;
            esac
        done
        
        echo "実行中: $running/$total"
        if [ $auth_pending -gt 0 ]; then
            echo "認証待機中: $auth_pending"
        fi
        
    else
        # 特定ペイン状態
        local status=$(get_agent_state "$pane")
        local auth_detail=$("$AUTH_HELPER" check "$pane" 2>/dev/null || echo "stopped")
        
        echo "ペイン: $pane"
        echo "状態: $status"
        echo "詳細: $auth_detail"
        echo "タイムスタンプ: $(date)"
        
        # 画面の最新状態も表示
        echo ""
        echo "画面状態:"
        echo "=================================="
        "$PANE_CONTROLLER" capture "$pane" "-5" | tail -5
    fi
}

# 利用可能なエージェントタイプ一覧
list_agent_types() {
    log_info "利用可能なエージェントタイプ:"
    echo "=================================="
    
    for agent_type in "${!AGENT_COMMANDS[@]}"; do
        printf "%-10s : %s\n" "$agent_type" "${AGENT_DESCRIPTIONS[$agent_type]}"
        printf "           コマンド: %s\n" "${AGENT_COMMANDS[$agent_type]}"
        
        # 認証情報を表示
        if [ -f "$AGENT_AUTH_CONFIG" ] && command -v jq >/dev/null 2>&1; then
            local auth_method=$(jq -r ".$agent_type.auth_method // \"unknown\"" "$AGENT_AUTH_CONFIG")
            local auth_desc=$(jq -r ".$agent_type.description // \"\"" "$AGENT_AUTH_CONFIG")
            printf "           認証: %s\n" "$auth_method"
            if [ -n "$auth_desc" ]; then
                printf "           %s\n" "$auth_desc"
            fi
        fi
        echo ""
    done
    
    echo "custom     : カスタムコマンド実行"
    echo "           使用例: agent_manager.sh start worker-a01 custom 'python script.py'"
    
    # 認証設定ファイルの状態
    echo ""
    echo "認証設定:"
    if [ -f "$AGENT_AUTH_CONFIG" ]; then
        echo "  設定ファイル: $AGENT_AUTH_CONFIG"
        if command -v jq >/dev/null 2>&1; then
            echo "  設定済みエージェント: $(jq -r 'keys | join(", ")' "$AGENT_AUTH_CONFIG")"
        fi
    else
        echo "  設定ファイルなし"
    fi
}

# バッチ起動（並列処理対応）
batch_start() {
    local agent_type="${1:-claude}"
    local panes="${2:-all}"
    local parallel="${3:-true}"  # デフォルトは並列処理
    
    log_info "バッチ起動開始: $agent_type (並列=$parallel)"
    
    local target_panes=()
    if [ "$panes" = "all" ]; then
        # 全てのペインを番号で指定（汎用的）
        local pane_count=$(get_pane_count)
        for ((i=0; i<pane_count; i++)); do
            target_panes+=("$i")
        done
    else
        # カンマ区切りのペイン指定（番号のみ）
        IFS=',' read -ra target_panes <<< "$panes"
    fi
    
    if [ "$parallel" = "true" ] && [ "$agent_type" != "claude" ]; then
        # 並列起動（Claude以外）
        log_info "並列起動モード: ${#target_panes[@]} エージェント"
        
        local pids=()
        local temp_dir=$(mktemp -d)
        
        # バックグラウンドで起動
        for pane in "${target_panes[@]}"; do
            (
                log_info "起動開始: $pane"
                if start_agent "$pane" "$agent_type"; then
                    echo "success" > "$temp_dir/$pane.result"
                else
                    echo "failed" > "$temp_dir/$pane.result"
                fi
            ) &
            pids+=($!)
            
            # 少し間隔を空ける（同時アクセス回避）
            sleep 0.2
        done
        
        # 全プロセス完了待機
        log_info "全エージェント起動待機中..."
        for pid in "${pids[@]}"; do
            wait $pid
        done
        
        # 結果集計
        local success=0
        local failed=0
        for pane in "${target_panes[@]}"; do
            if [ -f "$temp_dir/$pane.result" ]; then
                result=$(cat "$temp_dir/$pane.result")
                if [ "$result" = "success" ]; then
                    success=$((success + 1))
                else
                    failed=$((failed + 1))
                fi
            fi
        done
        
        rm -rf "$temp_dir"
        log_info "並列バッチ起動完了: 成功=$success, 失敗=$failed"
        
    else
        # 順次起動（Claudeまたは非並列モード）
        log_info "順次起動モード: ${#target_panes[@]} エージェント"
        
        local success=0
        local failed=0
        
        for pane in "${target_panes[@]}"; do
            log_info "起動中: $pane"
            if start_agent "$pane" "$agent_type"; then
                success=$((success + 1))
            else
                failed=$((failed + 1))
            fi
            sleep 1
        done
        
        log_info "順次バッチ起動完了: 成功=$success, 失敗=$failed"
    fi
}

# 認証待機中のエージェント状態を更新
update_auth_pending() {
    log_info "認証待機中のエージェントを確認中..."
    
    local updated=0
    local still_pending=0
    
    # 実際に存在するペインを動的に取得
    local pane_list=$(tmux list-panes -t multiagent -F "#{pane_index}" 2>/dev/null | sort -n)
    local pane_count=$(echo "$pane_list" | wc -w)
    
    # 全エージェントの状態を確認
    for i in $pane_list; do
        local status=$(get_agent_state $i)
        
        if [ "$status" = "auth_pending" ]; then
            # 認証状態を再確認
            local auth_state=$("$AUTH_HELPER" check "$i" 2>&1 | grep -o "authenticated" || echo "")
            
            if [ "$auth_state" = "authenticated" ]; then
                log_success "pane-$i 認証完了 → running"
                updated=$((updated + 1))
            else
                still_pending=$((still_pending + 1))
            fi
        fi
    done
    
    log_info "更新結果: 認証完了=$updated, 認証待機中=$still_pending"
}

# ヘルプ表示
show_usage() {
    cat << EOF
🤖 Agent Manager - エージェント管理ツール

使用方法:
  $(basename $0) <command> [options]

コマンド:
  start <pane> [type] [args]   エージェント起動
  stop <pane> [force]          エージェント停止
  restart <pane> [type] [args] エージェント再起動
  status [pane]                状態確認
  list                         利用可能なエージェントタイプ
  batch <type> [target]        バッチ起動
  update-auth                  認証待機中の状態を更新

エージェントタイプ:
  claude    - Claude Code (デフォルト)
  gemini    - Gemini CLI
  gpt       - GPT CLI
  python    - Python インタープリタ
  bash      - Bash シェル
  custom    - カスタムコマンド

バッチターゲット:
  all       - 全ペイン
  <list>    - カンマ区切りペイン番号

バッチオプション:
  第3引数にfalseを指定すると順次起動
  (デフォルトは並列起動、Claudeは常に順次)

例:
  $(basename $0) start 0 claude
  $(basename $0) start 1 gemini
  $(basename $0) start 2 custom "python main.py"
  $(basename $0) stop 3
  $(basename $0) restart 4 claude
  $(basename $0) batch claude all            # Claudeを全ペインで順次起動
  $(basename $0) batch gemini all            # Geminiを全ペインで並列起動
  $(basename $0) batch python all false      # Pythonを順次起動
  $(basename $0) batch gemini "0,1,2"
  $(basename $0) status
EOF
}

# メイン処理
main() {
    # 依存ツール確認
    if [ ! -x "$PANE_CONTROLLER" ]; then
        log_error "pane_controller.sh が見つかりません"
        exit 1
    fi
    
    if [ ! -x "$AUTH_HELPER" ]; then
        log_error "auth_helper.sh が見つかりません"
        exit 1
    fi
    
    case "${1:-}" in
        "start")
            shift
            if [ $# -lt 1 ]; then
                log_error "使用法: start <pane> [type] [args]"
                exit 1
            fi
            start_agent "$@"
            ;;
        "stop")
            shift
            if [ $# -lt 1 ]; then
                log_error "使用法: stop <pane> [force]"
                exit 1
            fi
            stop_agent "$@"
            ;;
        "restart")
            shift
            if [ $# -lt 1 ]; then
                log_error "使用法: restart <pane> [type] [args]"
                exit 1
            fi
            restart_agent "$@"
            ;;
        "status")
            shift
            check_agent_status "$@"
            ;;
        "list")
            list_agent_types
            ;;
        "batch")
            shift
            if [ $# -lt 1 ]; then
                log_error "使用法: batch <type> [target]"
                exit 1
            fi
            batch_start "$@"
            ;;
        "update-auth")
            update_auth_pending
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