#!/bin/bash

# 🔐 Auth Helper v2 - JavaScriptと同じ状態検出ロジック
# エージェントの認証状態確認と認証プロセス支援

set -e

# 共通ライブラリの読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"
setup_directories "$SCRIPT_DIR"

# スクリプトパスの設定
PANE_CONTROLLER="$SCRIPT_DIR/pane_controller.sh"
AUTH_DELEGATOR="$UTILITIES_DIR/auth_delegator.sh"

# ログ関数のエイリアス（後方互換性のため）
log_info() { log "INFO" "$1" "AUTH"; }
log_error() { log "ERROR" "$1" "ERROR"; }
log_success() { log "SUCCESS" "$1" "SUCCESS"; }
log_warn() { log "WARN" "$1" "WARN"; }

# ペイン番号取得は共通ライブラリの関数を使用
# get_pane_number() は utils.sh で定義済み

# エージェント状態を検出（JavaScriptのanalyzeAgentStateと同じロジック）
detect_agent_state() {
    local screen="$1"
    
    # デバッグ用
    # echo "[DEBUG] Screen length: $(echo "$screen" | wc -l) lines" >&2
    # echo "[DEBUG] Raw screen first 100 chars: $(echo "$screen" | head -c 100)" >&2
    
    # 空チェック
    if [ -z "$screen" ] || [ "$(echo "$screen" | grep -v '^$' | wc -l)" -eq 0 ]; then
        echo "stopped|none|停止中"
        return 0
    fi
    
    # =================================================================
    # 前処理: 画面内容を正規化（一度だけ実行）
    # 狭いペインで改行が多い場合でも確実にパターンマッチングできるよう、
    # 全ての改行とスペースを削除した文字列を作成
    # =================================================================
    # ANSIエスケープシーケンスを削除してから正規化
    local clean_screen=$(echo "$screen" | sed -E 's/\x1b\[[0-9;]*[mGKHF]//g' | sed -E 's/\x1b\[?[0-9;]*[a-zA-Z]//g')
    local compact_lower=$(echo "$clean_screen" | tr '[:upper:]' '[:lower:]' | tr -d '\n' | tr -d ' ')
    
    # 優先度0: 最優先 - 画面の最後の有効な行に「$」が含まれていれば停止中
    # 空でない最後の行を取得
    local last_valid_line=""
    local lines_array=()
    while IFS= read -r line; do
        lines_array+=("$line")
    done <<< "$screen"
    
    for ((i=${#lines_array[@]}-1; i>=0; i--)); do
        if [ -n "$(echo "${lines_array[$i]}" | tr -d '[:space:]')" ]; then
            last_valid_line=$(echo "${lines_array[$i]}" | tr '[:upper:]' '[:lower:]')
            break
        fi
    done
    
    # 最後の有効な行がシェルプロンプトで終わっている場合のみ停止中と判定
    if echo "$last_valid_line" | grep -qE '\$[[:space:]]*$'; then
        echo "stopped|none|停止中（シェルプロンプト）"
        return 0
    fi
    
    # =================================================================
    # 以下、全ての検出は正規化済みの compact_lower を使用
    # =================================================================
    
    # 優先度0: Claudeプロンプトが表示されている場合（最優先）
    # プロンプト（>）と「for shortcuts」または「Bypassing」が同時に存在する場合は起動完了
    local has_prompt=$(echo "$screen" | grep -q "> *$" && echo "yes" || echo "no")
    local has_shortcuts=$(echo "$compact_lower" | grep -q "forshortcuts\|bypassingpermissions" && echo "yes" || echo "no")
    # echo "[DEBUG] has_prompt=$has_prompt, has_shortcuts=$has_shortcuts" >&2
    
    if [ "$has_prompt" = "yes" ] && [ "$has_shortcuts" = "yes" ]; then
        echo "running_claude|claude|Claude起動完了"
        return 0
    fi
    
    # プロンプトボックスが表示されている場合も起動完了
    if echo "$screen" | grep -q "╭─.*─╮" && echo "$screen" | grep -q "│ >" && echo "$screen" | grep -q "╰─.*─╯"; then
        echo "running_claude|claude|Claude起動完了"
        return 0
    fi
    
    # 優先度1: Claude実行中の検出
    if echo "$compact_lower" | grep -q "esctointerrupt"; then
        echo "executing_claude|claude|Claude実行中"
        return 0
    fi
    
    # 優先度2: Claude認証中の検出（詳細タイプ付き）
    if echo "$compact_lower" | grep -q "bypasspermissions"; then
        echo "auth_claude|claude|Claude認証中 - 権限確認画面|permission_prompt"
        return 0
    fi
    
    if echo "$compact_lower" | grep -q "pressentertocontinue\|securitynotes"; then
        echo "auth_claude|claude|Claude認証中 - 続行確認画面|continue_prompt"
        return 0
    fi
    
    if echo "$compact_lower" | grep -q "useclaudecode'sterminalsetup\|dangerousmode"; then
        echo "auth_claude|claude|Claude認証中 - Terminal設定画面|terminal_setup"
        return 0
    fi
    
    if echo "$compact_lower" | grep -q "preview\|console\.log\|choosethetextstyle"; then
        echo "auth_claude|claude|Claude認証中 - テーマ選択画面|theme_selection"
        return 0
    fi
    
    if echo "$compact_lower" | grep -q "browserdidn'topen\|waitingforbrowser\|oautherror\|authenticate.*browser"; then
        echo "auth_claude|claude|Claude認証中 - ブラウザ認証待機|browser_auth"
        return 0
    fi
    
    if echo "$compact_lower" | grep -q "pastecodehere.*prompted"; then
        echo "auth_claude|claude|Claude認証中 - コード入力待機|code_input"
        return 0
    fi
    
    if echo "$compact_lower" | grep -q "selectlogin\|claudeaccountwithsubscription\|anthropicconsoleaccount"; then
        echo "auth_claude|claude|Claude認証中 - ログイン方法選択|login_selection"
        return 0
    fi
    
    if echo "$compact_lower" | grep -q "pastecodehere.*prompted"; then
        echo "auth_claude|claude|Claude認証中 - コード入力画面|code_input"
        return 0
    fi
    
    # 優先度3: Claude起動完了の検出
    if echo "$compact_lower" | grep -q "/helpforhelp.*foryourcurrentsetup"; then
        echo "running_claude|claude|Claude起動完了"
        return 0
    fi
    
    # その他のClaude起動完了パターン
    if echo "$compact_lower" | grep -q "howcanihelp\|try\"edit\|tip:" && \
       ! echo "$compact_lower" | grep -q "preview\|console\.log\|pressentertocontinue\|useclaudecode'sterminalsetup"; then
        echo "running_claude|claude|Claude起動完了"
        return 0
    fi
    
    # 優先度4: Gemini起動完了の検出
    if echo "$compact_lower" | grep -q "typeyourmessage" && \
       ! echo "$compact_lower" | grep -q "waitingforauth"; then
        echo "running_gemini|gemini|Gemini起動完了"
        return 0
    fi
    
    # Geminiバージョン検出
    if echo "$compact_lower" | grep -q "gemini-2\.\|gemini-1\.\|gemini-2\.5-pro\|gemini-2\.0-pro\|gemini-1\.5-pro"; then
        echo "running_gemini|gemini|Gemini起動完了"
        return 0
    fi
    
    if echo "$compact_lower" | grep -q "/help.*information" && ! echo "$compact_lower" | grep -q "waitingforauth"; then
        echo "running_gemini|gemini|Gemini起動完了"
        return 0
    fi
    
    # 優先度5: Gemini認証中の検出
    if echo "$compact_lower" | grep -q "waitingforauth\|loginwithgoogle\|vertexai\|geminiapikey"; then
        echo "auth_gemini|gemini|Gemini認証中"
        return 0
    fi
    
    # 優先度6: 停止中（エージェントなし）
    # Bashプロンプトのみの場合
    if (echo "$compact_lower" | grep -q "bash\|sh-") && \
       ! echo "$compact_lower" | grep -q "claude" && \
       ! echo "$compact_lower" | grep -q "gemini" && \
       ! echo "$compact_lower" | grep -q "preview"; then
        echo "stopped|none|停止中"
        return 0
    fi
    
    # 優先度7: その他の起動中状態
    if echo "$compact_lower" | grep -q "claude"; then
        echo "running_claude|claude|Claude起動中（初期化中）"
        return 0
    fi
    
    if echo "$compact_lower" | grep -q "gemini"; then
        echo "running_gemini|gemini|Gemini起動中（初期化中）"
        return 0
    fi
    
    # デフォルト
    echo "stopped|none|不明"
    return 0
}

# 認証状態確認（互換性のため残す）
check_agent_state() {
    local pane_num="$1"
    
    # ペイン番号検証
    pane_num=$(get_pane_number "$pane_num")
    if [ -z "$pane_num" ]; then
        log_error "無効なペイン指定"
        echo "unknown"
        return 1
    fi
    
    # 画面内容取得
    local target=$(get_tmux_target "$pane_num")
    local screen=$(tmux capture-pane -t "$target" -p -S -3000 2>/dev/null || echo "")
    
    # 新しい状態検出を使用
    local result=$(detect_agent_state "$screen")
    local state=$(echo "$result" | cut -d'|' -f1)
    local agent=$(echo "$result" | cut -d'|' -f2)
    local details=$(echo "$result" | cut -d'|' -f3)
    
    # 互換性のため、旧形式の状態名も返す
    case "$state" in
        "executing_claude"|"running_claude")
            echo "authenticated"
            ;;
        "auth_claude")
            # 詳細な認証状態を判定
            if echo "$details" | grep -q "権限確認画面"; then
                echo "permission_prompt"
            elif echo "$details" | grep -q "続行確認画面"; then
                echo "continue_prompt"
            elif echo "$details" | grep -q "Terminal設定画面"; then
                echo "terminal_setup"
            elif echo "$details" | grep -q "テーマ選択画面"; then
                echo "theme_selection"
            elif echo "$details" | grep -q "ブラウザ認証待機"; then
                echo "browser_auth"
            elif echo "$details" | grep -q "コード入力"; then
                echo "code_input"
            else
                echo "starting"
            fi
            ;;
        "running_gemini")
            echo "authenticated"
            ;;
        "auth_gemini")
            echo "browser_auth"
            ;;
        "stopped")
            echo "not_started"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# 新しい詳細状態取得関数
get_detailed_state() {
    local pane_num="$1"
    
    # ペイン番号検証
    pane_num=$(get_pane_number "$pane_num")
    if [ -z "$pane_num" ]; then
        echo "error|none|無効なペイン指定"
        return 1
    fi
    
    # 画面内容取得
    local target=$(get_tmux_target "$pane_num")
    local screen=$(tmux capture-pane -t "$target" -p -S -3000 2>/dev/null || echo "")
    
    # 新しい状態検出を使用
    detect_agent_state "$screen"
}

# その他の関数は元のauth_helper.shから継承...
# （認証待機、認証代行、ステータス表示など）

# ヘルプ表示
show_usage() {
    cat << EOF
🔐 Auth Helper v2 - Claude Code認証支援ツール

使用方法:
  $(basename $0) <command> [options]

コマンド:
  check <pane>              認証状態確認（旧形式）
  state <pane>              詳細状態確認（新形式）
  wait <pane> [timeout]     認証完了待機（デフォルト:150秒）
  delegate <pane>           認証代行依頼
  status                    全ペイン認証状態表示
  
ペイン指定:
  - 番号: 0, 1, 2, ... (実際のペイン数に依存)

状態（新形式）:
  stopped           - 停止中
  executing_claude  - Claude実行中
  running_claude    - Claude起動完了
  auth_claude      - Claude認証中
  running_gemini   - Gemini起動完了
  auth_gemini      - Gemini認証中

例:
  $(basename $0) state 0      # 新形式で詳細状態取得
  $(basename $0) check 0      # 旧形式で状態確認
  $(basename $0) wait 1 180
  $(basename $0) delegate 2
  $(basename $0) status
EOF
}

# ===== 以下は元のauth_helper.shから移植 =====

# Claude起動完了チェック（新しい状態検出を使用）
check_claude_startup() {
    local pane="$1"
    local state_result=$(get_detailed_state "$pane")
    local state=$(echo "$state_result"  < /dev/null |  cut -d'|' -f1)
    
    if [[ "$state" == "running_claude" ]] || [[ "$state" == "executing_claude" ]]; then
        return 0  # 起動完了
    fi
    return 1  # 未完了
}

# Gemini起動完了チェック（新しい状態検出を使用）
check_gemini_startup() {
    local pane="$1"
    local state_result=$(get_detailed_state "$pane")
    local state=$(echo "$state_result" | cut -d'|' -f1)
    
    if [[ "$state" == "running_gemini" ]]; then
        return 0  # 起動完了
    fi
    return 1  # 未完了
}

# エージェント起動待機
wait_for_agent_startup() {
    local pane="$1"
    local timeout="${2:-150}"
    local agent_type="${3:-claude}"
    
    log_info "エージェント起動待機中 (ペイン: $pane, タイプ: $agent_type, タイムアウト: ${timeout}秒)"
    
    local elapsed=0
    local check_interval=1  # チェック間隔を短縮
    
    while [ $elapsed -lt $timeout ]; do
        local state_result=$(get_detailed_state "$pane")
        local state=$(echo "$state_result" | cut -d'|' -f1)
        local detected_agent=$(echo "$state_result" | cut -d'|' -f2)
        local details=$(echo "$state_result" | cut -d'|' -f3)
        # auth_typeは詳細から抽出
        local auth_type=""
        if [[ "$state" == "auth_claude" ]]; then
            # 詳細テキストから認証タイプを判定
            if echo "$details" | grep -q "権限確認画面"; then
                auth_type="permission_prompt"
            elif echo "$details" | grep -q "続行確認画面"; then
                auth_type="continue_prompt"  
            elif echo "$details" | grep -q "Terminal設定画面"; then
                auth_type="terminal_setup"
            elif echo "$details" | grep -q "テーマ選択画面"; then
                auth_type="theme_selection"
            elif echo "$details" | grep -q "ログイン方法選択"; then
                auth_type="login_selection"
            elif echo "$details" | grep -q "ブラウザ認証待機"; then
                auth_type="browser_auth"
            elif echo "$details" | grep -q "コード入力"; then
                auth_type="code_input"
            fi
        fi
        
        # エージェント起動完了チェック
        case "$agent_type" in
            "claude")
                if [[ "$state" == "running_claude" ]] || [[ "$state" == "executing_claude" ]]; then
                    log_success "Claude起動完了"
                    return 0
                elif [[ "$state" == "auth_claude" ]]; then
                    # デバッグログ
                    log_info "[DEBUG] auth_claude detected - details: $details, auth_type: $auth_type"
                    
                    # 認証画面の自動処理（統一されたauth_typeを使用）
                    case "$auth_type" in
                        "permission_prompt")
                            log_info "Bypass Permissions画面検出 - 自動同意"
                            tmux send-keys -t "$(get_tmux_target $pane)" Down
                            sleep 0.5
                            tmux send-keys -t "$(get_tmux_target $pane)" C-m
                            sleep 2
                            ;;
                        "continue_prompt")
                            log_info "続行確認画面検出 - Enter送信"
                            tmux send-keys -t "$(get_tmux_target $pane)" C-m
                            sleep 2
                            ;;
                        "terminal_setup")
                            log_info "Terminal設定画面検出 - Yes選択"
                            tmux send-keys -t "$(get_tmux_target $pane)" C-m
                            sleep 2
                            ;;
                        "theme_selection")
                            log_info "テーマ選択画面検出 - デフォルト選択"
                            tmux send-keys -t "$(get_tmux_target $pane)" C-m
                            sleep 1
                            ;;
                        "login_selection")
                            log_info "ログイン方法選択画面検出 - Claude account選択"
                            tmux send-keys -t "$(get_tmux_target $pane)" C-m
                            sleep 2
                            ;;
                        "browser_auth"|"code_input")
                            if [[ "$auth_type" == "browser_auth" ]]; then
                                log_info "ブラウザ認証画面検出 - 自動認証代行開始"
                            else
                                log_info "コード入力画面検出 - 自動認証代行開始"
                            fi
                            # 認証済みのペインを探す
                            local auth_pane=""
                            local pane_list=$(get_all_panes)
                            for p in $pane_list; do
                                if [ "$p" != "$pane" ]; then
                                    local p_state=$(get_detailed_state "$p" | cut -d'|' -f1)
                                    if [[ "$p_state" == "running_claude" ]] || [[ "$p_state" == "executing_claude" ]]; then
                                        auth_pane="$p"
                                        break
                                    fi
                                fi
                            done
                            
                            if [ -n "$auth_pane" ]; then
                                log_info "認証済みペイン $auth_pane を使用して認証代行"
                                # auth_delegator.shを呼び出し
                                "$SCRIPT_DIR/../utilities/auth_delegator.sh" delegate "$pane"
                            else
                                log_warn "認証済みペインが見つかりません - 手動認証が必要です"
                            fi
                            sleep 3
                            ;;
                        *)
                            log_warn "[DEBUG] Unknown auth_type: '$auth_type' for details: '$details'"
                            ;;
                    esac
                fi
                ;;
            "gemini")
                if [[ "$state" == "running_gemini" ]]; then
                    log_success "Gemini起動完了"
                    return 0
                fi
                ;;
            *)
                # その他のエージェントは起動チェックのみ
                if [[ "$state" != "stopped" ]]; then
                    log_success "$agent_type 起動完了"
                    return 0
                fi
                ;;
        esac
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
        
        # 進捗表示
        if [ $((elapsed % 10)) -eq 0 ]; then
            log_info "待機中... ($elapsed/${timeout}秒) 現在の状態: $state"
        fi
    done
    
    log_error "タイムアウト: エージェント起動が完了しませんでした"
    return 1
}


# メイン処理
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-}" in
        "check")
            if [ -z "$2" ]; then
                echo "エラー: ペイン番号が必要です"
                show_usage
                exit 1
            fi
            check_agent_state "$2"
            ;;
        "state")
            if [ -z "$2" ]; then
                echo "エラー: ペイン番号が必要です"
                show_usage
                exit 1
            fi
            get_detailed_state "$2"
            ;;
        "wait")
            if [ -z "$2" ]; then
                echo "エラー: ペイン番号が必要です"
                show_usage
                exit 1
            fi
            wait_for_agent_startup "$2" "${3:-150}" "${4:-claude}"
            ;;
        "delegate"|"status")
            # TODO: これらの関数も移植する必要がある
            echo "エラー: この機能は元のauth_helper.shを使用してください"
            exit 1
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        *)
            echo "エラー: 不明なコマンド '$1'"
            show_usage
            exit 1
            ;;
    esac
fi

