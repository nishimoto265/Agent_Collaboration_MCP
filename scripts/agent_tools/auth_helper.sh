#!/bin/bash

# 🔐 Auth Helper - Claude Code認証支援ツール
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

# Claude Code起動状態確認（精度向上版）
check_claude_startup() {
    local pane="$1"
    local pane_num=$(get_pane_number "$pane")
    
    if [ -z "$pane_num" ]; then
        log_error "無効なペイン指定: $pane"
        return 1
    fi
    
    # 画面内容取得（複数回試行で精度向上）
    local screen=$("$PANE_CONTROLLER" capture "$pane" 2>/dev/null || echo "")
    
    # 画面が空の場合、再取得を試行
    if [ -z "$screen" ]; then
        sleep 0.5
        screen=$("$PANE_CONTROLLER" capture "$pane" 2>/dev/null || echo "")
    fi
    
    # 画面内容を正規化（改行をスペースに置換して連続スペースを単一に）
    local normalized_screen=$(echo "$screen" | tr '\n' ' ' | tr -s ' ')
    
    # 認証が必要な画面パターンチェック（起動完了ではない）
    if echo "$screen" | grep -q "Select login method\|Choose the text style\|Welcome to Claude Code"; then
        return 1  # 認証/設定が必要
    fi
    
    # ログイン選択画面（認証未完了）
    if echo "$screen" | grep -q "Claude account with.*subscription\|Anthropic Console.*account\|API usage billing"; then
        return 1  # ログイン方法選択中
    fi
    
    # テーマ選択画面（認証後の設定）
    if echo "$screen" | grep -q "Dark mode\|Light mode.*colorblind.*friendly\|Preview.*function.*greet"; then
        return 1  # テーマ選択中
    fi
    
    # 起動完了パターンチェック（精度向上版）
    # /help for helpパターン（完全一致）
    if echo "$screen" | grep -q "/help for help.*status.*current setup"; then
        return 0  # 起動完了
    fi
    
    # 改行で分かれている場合（精密チェック）
    if echo "$screen" | grep -q "/help for help" && echo "$screen" | grep -q "for your current setup"; then
        return 0  # 起動完了（改行版）
    fi
    
    # 新しいClaude Code UIパターン（狭いペイン対応）
    if echo "$screen" | grep -q "Try \"edit" && echo "$screen" | grep -q "help\|tip"; then
        return 0  # 起動完了
    fi
    
    # 狭いペイン用：個別キーワード検出
    if echo "$screen" | grep -q "/help" && echo "$screen" | grep -q "help" && echo "$screen" | grep -q "setup"; then
        return 0  # 起動完了（キーワード分散版）
    fi
    
    # 正規化版でのパターン検出
    if echo "$normalized_screen" | grep -q "/help for help.*current setup"; then
        return 0  # 起動完了（正規化版）
    fi
    
    # その他の起動完了パターン（精密チェック）
    if echo "$screen" | grep -i -q "how can i help\|try \"edit\|tip:" && \
       ! echo "$screen" | grep -q "Preview\|console\.log\|Press Enter to continue\|Use Claude Code's terminal setup\|Opening.*browser\|Please visit"; then
        return 0  # 起動完了
    fi
    
    # Bypassing Permissionsパターン（起動完了後の状態）
    if echo "$screen" | grep -q "Bypassing.*Permissions" && \
       ! echo "$screen" | grep -q "Yes, I accept\|No, exit"; then
        return 0  # 起動完了
    fi
    
    # 特徴的なClaude UIキーワード
    if echo "$screen" | grep -q "Try \"edit\|Bypassing.*Permissions"; then
        return 0  # 起動完了
    fi
    
    # Bypassing Permissionsの別パターン（改行で分割されている場合）
    if echo "$screen" | grep -q "Bypassing" && echo "$screen" | grep -q "Permission"; then
        return 0  # 起動完了
    fi
    
    # プロンプト表示（認証中でないことを確認）
    if echo "$screen" | grep -q "^>\|) \$\|~\$\|#\$" && \
       ! echo "$screen" | grep -q "Preview\|console\.log\|Press Enter to continue\|Use Claude Code's terminal setup\|Opening.*browser\|Please visit"; then
        return 0  # 起動完了
    fi
    
    # 特定のClaudeコマンドプロンプトが表示されている場合
    if echo "$screen" | grep -q "Type a message\|What would you like" && \
       ! echo "$screen" | grep -q "Preview\|console\.log\|Opening.*browser"; then
        return 0  # 起動完了
    fi
    
    return 1  # 未起動または認証中
}

# Gemini起動状態確認
check_gemini_startup() {
    local pane="$1"
    local pane_num=$(get_pane_number "$pane")
    
    if [ -z "$pane_num" ]; then
        log_error "無効なペイン指定: $pane"
        return 1
    fi
    
    # 画面内容取得
    local screen=$("$PANE_CONTROLLER" capture "$pane" 2>/dev/null || echo "")
    
    # 画面内容を正規化（改行をスペースに置換して連続スペースを単一に）
    local normalized_screen=$(echo "$screen" | tr '\n' ' ' | tr -s ' ')
    
    # 認証画面が表示されている場合は起動中とみなす
    if echo "$screen" | grep -qF "Waiting for auth" || echo "$screen" | grep -qE "Login with Google|Gemini API Key|Vertex AI"; then
        return 3  # 認証待機中
    fi
    
    # Gemini起動完了パターン（改行対応版）
    # 新しいGemini CLIのUIパターン - 部分的なマッチングで対応
    if echo "$screen" | grep -q "Type your message" || echo "$normalized_screen" | grep -q "Type your message.*@path/to/file"; then
        # ただし認証画面が同時に表示されていないことを確認
        if ! echo "$screen" | grep -qE "Waiting for auth|Login with Google|Press ESC to cancel"; then
            return 0  # 起動完了
        fi
    fi
    
    # MCPサーバー使用中のパターン（改行対応）
    if echo "$screen" | grep -q "Using.*MCP" || echo "$screen" | grep -q "MCP servers"; then
        # ただし認証画面が同時に表示されていないことを確認
        if ! echo "$screen" | grep -qE "Waiting for auth|Login with Google|Press ESC to cancel"; then
            return 0  # 起動完了
        fi
    fi
    
    # gemini-2.5-proなどのモデル表示（認証完了後）
    if echo "$screen" | grep -qi "gemini.*[0-9]\|gemini-[0-9]"; then
        # ただし認証画面が同時に表示されていないことを確認
        if ! echo "$screen" | grep -qE "Waiting for auth|Login with Google|Press ESC to cancel"; then
            return 0  # 起動完了
        fi
    fi
    
    # /help for more informationパターン（改行対応）
    if echo "$screen" | grep -q "/help" && echo "$screen" | grep -q "information"; then
        return 0  # 起動完了
    fi
    
    # 特徴的なGemini UIキーワードの検出
    if echo "$screen" | grep -q "@path/to/file\|@file\|Type a message"; then
        if ! echo "$screen" | grep -qE "Waiting for auth|Login with Google|Press ESC to cancel"; then
            return 0  # 起動完了
        fi
    fi
    
    # プロンプトが表示されている場合
    if echo "$screen" | grep -q "^>\|) \$\|~\$\|#\$"; then
        # ただし認証画面が同時に表示されていないことを確認
        if ! echo "$screen" | grep -qE "Waiting for auth|Login with Google|Press ESC to cancel"; then
            return 0  # 起動完了
        fi
    fi
    
    # エラーチェック
    if echo "$screen" | grep -q "API key.*not found\|Authentication.*failed\|GOOGLE_API_KEY"; then
        return 2  # 認証エラー
    fi
    
    return 1  # 未起動
}

# 汎用エージェント起動状態確認
check_agent_startup() {
    local pane="$1"
    local agent_type="$2"
    
    case "$agent_type" in
        "claude")
            check_claude_startup "$pane"
            ;;
        "gemini")
            check_gemini_startup "$pane"
            ;;
        "python"|"bash")
            # PythonやBashは即座に起動完了とみなす
            return 0
            ;;
        *)
            # その他のエージェントは画面にプロンプトがあれば起動完了
            local screen=$(timeout 2 "$PANE_CONTROLLER" capture "$pane" 2>/dev/null || echo "")
            if echo "$screen" | grep -q "^>\|) \$\|~\$\|#\$\|>>>\|\.\.\."; then
                return 0
            fi
            return 1
            ;;
    esac
}

# 認証状態詳細確認（スキップ機能付き）
get_auth_state() {
    local pane="$1"
    local pane_num=$(get_pane_number "$pane")
    
    if [ -z "$pane_num" ]; then
        echo "invalid"
        return 1
    fi
    
    # 画面内容取得（複数回試行）
    local screen=$("$PANE_CONTROLLER" capture "$pane" 2>/dev/null || echo "")
    
    # 画面が空の場合、再取得を試行
    if [ -z "$screen" ]; then
        sleep 0.5
        screen=$("$PANE_CONTROLLER" capture "$pane" 2>/dev/null || echo "")
    fi
    
    # 最優先: シェルプロンプト状態の検出（認証画面残骸を無視）
    local last_lines=$(echo "$screen" | tail -5 | tr '\n' ' ' | tr '[:upper:]' '[:lower:]')
    if echo "$last_lines" | grep -qE '.*[\$#]\s*' && \
       (echo "$last_lines" | grep -q "agent_collaboration\|org-\|pane-\|agent-"); then
        echo "not_started"
        return 0
    fi
    
    # 認証完了パターンをチェック（狭いペイン対応強化版）
    # 画面内容を正規化（改行をスペースに変換）
    local normalized_screen=$(echo "$screen" | tr '\n' ' ' | tr -s ' ')
    
    # Claude Codeの確実な起動完了パターン（狭いペイン対応）
    if echo "$screen" | grep -q "/help for help.*status.*current setup" || \
       echo "$normalized_screen" | grep -q "/help for help.*status.*current setup"; then
        echo "authenticated"
        return 0
    fi
    
    if (echo "$screen" | grep -q "/help for help" && echo "$screen" | grep -q "for your current setup") || \
       echo "$normalized_screen" | grep -q "/help for help.*for your current setup"; then
        echo "authenticated"
        return 0
    fi
    
    # その他の確実な認証完了パターン（狭いペイン対応）
    if (echo "$screen" | grep -i -q "how can i help\|try \"edit\|tip:" || \
        echo "$normalized_screen" | grep -i -q "how can i help\|try.*edit\|tip:") && \
       ! echo "$screen" | grep -q "Preview\|console\.log\|Press Enter to continue\|Use Claude Code's terminal setup\|Opening.*browser\|Please visit"; then
        echo "authenticated"
        return 0
    fi
    
    # 起動完了チェック（エージェントタイプを推測）
    local agent_type="claude"  # デフォルト
    if echo "$screen" | grep -q "gemini\|Gemini"; then
        agent_type="gemini"
    fi
    
    if [ "$agent_type" = "claude" ] && check_claude_startup "$pane"; then
        echo "authenticated"
        return 0
    elif [ "$agent_type" = "gemini" ]; then
        check_gemini_startup "$pane"
        local status=$?
        if [ $status -eq 0 ]; then
            echo "authenticated"
            return 0
        elif [ $status -eq 3 ]; then
            echo "auth_required"
            return 0
        fi
    fi
    
    # 各認証段階をチェック
    if echo "$screen" | grep -q "No, exit.*Yes, I accept\|Yes, I accept.*No, exit" || \
       (echo "$screen" | grep -q "dangerous" && echo "$screen" | grep -q "Yes, I accept"); then
        echo "permission_prompt"  # Bypass Permissions同意画面
        return 0
    fi
    
    if echo "$screen" | grep -q "Press Enter to continue\|Press Enter to retry\|Security notes\|Login successful\|Logged in as\|OAuth error"; then
        echo "continue_prompt"  # 続行画面
        return 0
    fi
    
    if echo "$screen" | grep -q "Use Claude Code's terminal setup\|terminal.*setup\|Shift.*Enter"; then
        echo "terminal_setup"  # Terminal設定画面
        return 0
    fi
    
    # テーマ選択画面（狭いペイン対応）
    if echo "$screen" | grep -q "Preview" && echo "$screen" | grep -q "console\.log\|Dark mode\|Light mode"; then
        echo "theme_selection"  # テーマ選択画面
        return 0
    fi
    
    # テーマ選択画面（Choose the text styleパターン）
    if echo "$screen" | grep -q "Choose the text style\|Dark mode\|Light mode" && echo "$screen" | grep -q "Preview"; then
        echo "theme_selection"  # テーマ選択画面
        return 0
    fi
    
    if echo "$screen" | grep -q "Opening.*browser\|Please visit\|authenticate.*browser\|Browser didn't open\|use the url below"; then
        echo "browser_auth"  # ブラウザ認証必要
        return 0
    fi
    
    # 認証方法選択画面（狭いペイン対応 - 改善版）
    # 画面内容を正規化（改行をスペースに変換）
    local normalized_screen=$(echo "$screen" | tr '\n' ' ' | tr -s ' ')
    
    # 複数の認証方法選択画面パターンを組み合わせて検出（狭いペイン対応）
    if echo "$screen" | grep -qE "Select login method|Claude account with|Anthropic Console" || \
       echo "$normalized_screen" | grep -qE "Select login method|Claude account with.*subscription|Anthropic Console.*account" || \
       (echo "$screen" | grep -q "subscription" && echo "$screen" | grep -q "Starting at.*\$") || \
       (echo "$screen" | grep -q "API usage billing" && echo "$screen" | grep -q "Console"); then
        echo "login_method_selection"  # ログイン方法選択画面
        return 0
    fi
    
    if echo "$screen" | grep -q "Starting\|Loading\|Initializing\|claude.*starting"; then
        echo "starting"  # 起動中
        return 0
    fi
    
    # Claude Codeが起動していない
    if ! echo "$screen" | grep -q "claude\|Claude"; then
        echo "not_started"
        return 0
    fi
    
    echo "unknown"
}

# 認証プロセス自動処理
handle_auth_prompt() {
    local pane="$1"
    local state="$2"
    local pane_num=$(get_pane_number "$pane")
    
    case "$state" in
        "permission_prompt")
            log_info "Bypass Permissions同意画面 - Down + Enter実行"
            local target=$(get_tmux_target "$pane_num")
            tmux send-keys -t "$target" Down
            delay "$SHORT_DELAY"
            tmux send-keys -t "$target" C-m
            ;;
        "continue_prompt")
            log_info "続行画面 - Enter実行"
            local target=$(get_tmux_target "$pane_num")
            tmux send-keys -t "$target" C-m
            ;;
        "terminal_setup")
            log_info "Terminal設定画面 - Yes選択（Enter実行）"
            local target=$(get_tmux_target "$pane_num")
            tmux send-keys -t "$target" C-m
            ;;
        "theme_selection")
            log_info "テーマ選択画面 - スキップ（Enter×2）"
            local target=$(get_tmux_target "$pane_num")
            tmux send-keys -t "$target" C-m
            delay "$SHORT_DELAY"
            tmux send-keys -t "$target" C-m
            ;;
        "browser_auth")
            log_warn "ブラウザ認証が必要です"
            return 1
            ;;
        *)
            return 1
            ;;
    esac
    
    sleep 0.5
    return 0
}

# 認証完了待機（スキップ機能付き）
wait_for_auth() {
    local pane="$1"
    local timeout="${2:-150}"  # デフォルト150秒
    local agent_type="${3:-claude}"  # エージェントタイプ
    local use_delegator="${4:-true}"  # デフォルトでPresident代行を使用
    
    local pane_num=$(get_pane_number "$pane")
    if [ -z "$pane_num" ]; then
        log_error "無効なペイン指定: $pane"
        return 1
    fi
    
    # 最初に認証状態を確認してスキップ判定
    log_info "🔍 ペイン $pane の認証状態を確認中..."
    
    if [ "$agent_type" = "claude" ] && check_claude_startup "$pane"; then
        log_success "✅ ペイン $pane 既に認証完了 - 待機をスキップ"
        return 0
    fi
    
    if [ "$agent_type" = "gemini" ]; then
        check_gemini_startup "$pane"
        local status=$?
        if [ $status -eq 0 ]; then
            log_success "✅ ペイン $pane 既に認証完了 - 待機をスキップ"
            return 0
        fi
    fi
    
    log_info "ペイン $pane の $agent_type 起動/認証完了を待機中... (最大 $timeout 秒)"
    
    # Geminiの認証処理
    if [ "$agent_type" = "gemini" ]; then
        local elapsed=0
        local auth_complete=false
        local manual_auth_timeout=600  # 手動認証用の長いタイムアウト（10分）
        local effective_timeout=$timeout  # 実効タイムアウト
        
        log_info "Gemini起動中..."
        
        while [ $elapsed -lt $effective_timeout ]; do
            # 画面内容取得（一度だけ）
            local screen=$(timeout 2 "$PANE_CONTROLLER" capture "$pane" 2>/dev/null || echo "")
            
            # Gemini起動状態を画面内容から判定
            local startup_status=1  # デフォルトは未起動
            
            # 画面内容を正規化（改行をスペースに置換）
            local normalized_screen=$(echo "$screen" | tr '\n' ' ' | tr -s ' ')
            
            # 認証待機パターンチェック
            if echo "$screen" | grep -qF "Waiting for auth" || echo "$screen" | grep -qE "Login with Google|Gemini API Key|Vertex AI"; then
                startup_status=3  # 認証待機中
            # 起動完了パターンチェック（改行対応）
            elif echo "$screen" | grep -q "Type your message" && ! echo "$screen" | grep -qF "Waiting for auth"; then
                startup_status=0  # 起動完了
            elif echo "$normalized_screen" | grep -q "Type your message.*@path/to/file" && ! echo "$screen" | grep -qF "Waiting for auth"; then
                startup_status=0  # 起動完了
            elif echo "$screen" | grep -q "/help" && echo "$screen" | grep -q "information" && ! echo "$screen" | grep -qF "Waiting for auth"; then
                startup_status=0  # 起動完了
            # Geminiモデル名が表示されている場合（例: gemini-2.5-pro）
            elif echo "$screen" | grep -qi "gemini.*[0-9]\|gemini-[0-9]" && ! echo "$screen" | grep -qF "Waiting for auth"; then
                startup_status=0  # 起動完了
            # 特徴的なGemini UIキーワード
            elif echo "$screen" | grep -q "@path/to/file\|@file\|Type a message" && ! echo "$screen" | grep -qF "Waiting for auth"; then
                startup_status=0  # 起動完了
            # プロンプトが表示されている場合
            elif echo "$screen" | grep -q "^>\|) \$\|~\$\|#\$" && ! echo "$screen" | grep -qF "Waiting for auth"; then
                startup_status=0  # 起動完了
            # エラーチェック
            elif echo "$screen" | grep -q "API key.*not found\|Authentication.*failed\|GOOGLE_API_KEY"; then
                startup_status=2  # 認証エラー
            fi
            
            if [ $startup_status -eq 0 ]; then
                # 起動完了
                echo ""  # 改行
                log_success "$agent_type 起動完了!"
                return 0
            elif [ $startup_status -eq 3 ]; then
                # 認証待機中（check_gemini_startup から）
                if [ "$auth_complete" = false ]; then
                    log_warn "Gemini認証が必要です - 手動で認証を完了してください"
                    echo "📋 認証手順:"
                    echo "  1. 対象ペインで認証方法を選択（矢印キーで移動、Enterで選択）"
                    echo "     - Login with Google: ブラウザ認証"
                    echo "     - Gemini API Key: APIキー入力"
                    echo "     - Vertex AI: Vertex AI認証"
                    echo "  2. 選択した方法で認証を完了"
                    echo ""
                    echo "⏱️  手動認証のため、タイムアウトを${manual_auth_timeout}秒に延長します"
                    auth_complete=true
                    # タイムアウトを延長（残り時間を考慮）
                    local remaining=$((effective_timeout - elapsed))
                    if [ $remaining -lt $manual_auth_timeout ]; then
                        effective_timeout=$((elapsed + manual_auth_timeout))
                        log_info "タイムアウトを ${effective_timeout}秒 に延長しました"
                    fi
                fi
            else
                # startup_statusが3でない場合、画面パターンを再確認
                if [ -z "$screen" ]; then
                    screen=$(timeout 2 "$PANE_CONTROLLER" capture "$pane" 2>/dev/null || echo "")
                fi
                
                if echo "$screen" | grep -qF "Waiting for auth"; then
                    # 認証待機中（画面パターンから直接）
                    if [ "$auth_complete" = false ]; then
                    log_warn "Gemini認証が必要です (画面検出) - 手動で認証を完了してください"
                    echo "📋 認証手順:"
                    echo "  1. 対象ペインで認証方法を選択（矢印キーで移動、Enterで選択）"
                    echo "     - Login with Google: ブラウザ認証"
                    echo "     - Gemini API Key: APIキー入力"
                    echo "     - Vertex AI: Vertex AI認証"
                    echo "  2. 選択した方法で認証を完了"
                    echo ""
                    echo "⏱️  手動認証のため、タイムアウトを${manual_auth_timeout}秒に延長します"
                    auth_complete=true
                    # タイムアウトを延長（残り時間を考慮）
                    local remaining=$((effective_timeout - elapsed))
                    if [ $remaining -lt $manual_auth_timeout ]; then
                        effective_timeout=$((elapsed + manual_auth_timeout))
                        log_info "タイムアウトを ${effective_timeout}秒 に延長しました"
                    fi
                fi
                # 手動認証を待機
                if [ $((elapsed % 10)) -eq 0 ] && [ $elapsed -gt 0 ]; then
                    printf "\r⏳ 認証待機中... (%d/%d秒)" "$elapsed" "$effective_timeout"
                fi
                
                # 1分ごとにリマインダー
                if [ $((elapsed % 60)) -eq 0 ] && [ $elapsed -gt 60 ]; then
                    echo ""  # 改行
                    log_info "まだ認証を待機しています。必要に応じて対象ペインで認証を完了してください。"
                fi
                else
                    # 起動中
                    if [ $((elapsed % 5)) -eq 0 ]; then
                        log_info "Gemini起動待機中... (${elapsed}秒経過)"
                    fi
                fi
            fi
            
            # APIキーエラーチェック
            if echo "$screen" | grep -q "API key.*not found\|Authentication.*failed\|GOOGLE_API_KEY.*not set"; then
                log_error "Gemini API認証エラー - 環境変数またはAPIキーを確認してください"
                echo "💡 ヒント:"
                echo "  export GOOGLE_API_KEY='your-api-key'"
                echo "  または .env ファイルに GOOGLE_API_KEY を設定"
                return 1
            fi
            
            sleep 1
            elapsed=$((elapsed + 1))
        done
        
        echo ""  # 改行
        log_error "Gemini起動/認証タイムアウト (${elapsed}秒経過)"
        return 1
    fi
    
    # Python, Bashなどは即座に完了
    if [[ "$agent_type" =~ ^(python|bash|sh)$ ]]; then
        sleep 2
        log_success "$agent_type 起動完了!"
        return 0
    fi
    
    # Claude Codeの認証フロー（スキップ機能付き）
    if [ "$agent_type" = "claude" ]; then
        local elapsed=0
        local last_state=""
        local method_selection_count=0  # 無限ループ防止カウンター
        
        while [ $elapsed -lt $timeout ]; do
            # 現在の状態取得
            local state=$(get_auth_state "$pane")
            
            # 状態が変わった場合のみログ出力
            if [ "$state" != "$last_state" ]; then
                log_info "状態: $state"
                last_state="$state"
            fi
            
            # 認証完了（スキップ機能で既にチェック済みだがループ内で再確認）
            if [ "$state" = "authenticated" ]; then
                log_success "認証完了!"
                return 0
            fi
            
            # 認証方法選択画面
            if [ "$state" = "login_method_selection" ]; then
                # 無限ループ防止：同じ状態が3回続いた場合は手動介入を要求
                method_selection_count=$((method_selection_count + 1))
                if [ "$method_selection_count" -ge 3 ]; then
                    log_warn "認証方法選択画面が3回続いています - 手動介入が必要です"
                    log_info "手動で「1」を入力してEnterを押してください"
                    log_info "画面内容が狭いペインで分割されている可能性があります"
                    break
                fi
                
                log_info "認証方法選択画面 - デフォルト選択でEnterを送信 [$method_selection_count/3]"
                
                # Enterのみ送信（デフォルトのOption 1が自動選択される）
                local target=$(get_tmux_target "$pane_num")
                tmux send-keys -t "$target" "Enter"
                sleep 4  # 画面遷移待機
                continue
            fi
            
            # 自動処理可能な認証プロンプト
            if [[ "$state" =~ ^(permission_prompt|continue_prompt|terminal_setup|theme_selection)$ ]]; then
                if handle_auth_prompt "$pane" "$state"; then
                    # 処理後、少し待機
                    sleep 2
                    continue
                fi
            fi
            
            # ブラウザ認証が必要な場合
            if [ "$state" = "browser_auth" ]; then
                # President代行を試行
                if [ "$use_delegator" = "true" ] && [ "$pane_num" != "16" ] && [ -x "$AUTH_DELEGATOR" ]; then
                    log_info "認証代行を試行中..."
                    if "$AUTH_DELEGATOR" delegate "$pane_num" 2>/dev/null; then
                        log_success "President認証代行完了"
                        # 代行後も引き続き監視
                        sleep 5
                        continue
                    else
                        log_warn "President認証代行失敗 - 手動認証が必要です"
                    fi
                else
                    log_warn "ブラウザで手動認証を完了してください"
                    # 手動認証を待つ
                    sleep 5
                fi
            fi
            
            # 進捗表示
            if [ $((elapsed % 10)) -eq 0 ] && [ $elapsed -gt 0 ]; then
                printf "\r⏳ 待機中... (%d/%d秒)" "$elapsed" "$timeout"
            fi
            
            sleep 1
            elapsed=$((elapsed + 1))
        done
        
        echo ""  # 改行
        log_error "認証タイムアウト"
        return 1
    fi
    
    # その他のエージェント
    sleep 3
    if check_agent_startup "$pane" "$agent_type"; then
        log_success "$agent_type 起動完了!"
        return 0
    else
        log_error "$agent_type 起動失敗"
        return 1
    fi
}

# President経由認証
delegate_auth() {
    local pane="$1"
    local pane_num=$(get_pane_number "$pane")
    
    if [ -z "$pane_num" ]; then
        log_error "無効なペイン指定: $pane"
        return 1
    fi
    
    if [ ! -x "$AUTH_DELEGATOR" ]; then
        log_error "認証代行ツールが見つかりません"
        return 1
    fi
    
    log_info "認証代行を依頼中..."
    "$AUTH_DELEGATOR" delegate "$pane_num"
}

# 認証状態一括確認
check_all_status() {
    log_info "全ペイン認証状態:"
    echo "=================================="
    
    local authenticated=0
    local total=0
    
    # 実際に存在するペインを動的に取得
    local pane_list=$(get_all_panes)
    if [ -z "$pane_list" ]; then
        log_error "セッション '$TMUX_SESSION' のペイン一覧を取得できません"
        return 1
    fi
    
    for i in $pane_list; do
        local name="pane-$i"
        
        local state=$(get_auth_state $i 2>/dev/null || echo "error")
        local status_icon="❌"
        
        if [ "$state" = "authenticated" ]; then
            status_icon="✅"
            authenticated=$((authenticated + 1))
        elif [ "$state" = "not_started" ]; then
            status_icon="⚫"
        elif [[ "$state" =~ ^(browser_auth|permission_prompt|continue_prompt|terminal_setup|theme_selection)$ ]]; then
            status_icon="🔄"
        elif [ "$state" = "starting" ]; then
            status_icon="⏳"
        fi
        
        printf "%-12s (pane %2d): %s %s\n" "$name" "$i" "$status_icon" "$state"
        total=$((total + 1))
    done
    
    echo "=================================="
    echo "認証済み: $authenticated/$total"
}

# ヘルプ表示
show_usage() {
    cat << EOF
🔐 Auth Helper - Claude Code認証支援ツール

使用方法:
  $(basename $0) <command> [options]

コマンド:
  check <pane>              認証状態確認
  wait <pane> [timeout]     認証完了待機（デフォルト:150秒）
  delegate <pane>           認証代行依頼
  status                    全ペイン認証状態表示
  
ペイン指定:
  - 番号: 0, 1, 2, ... (実際のペイン数に依存)

認証状態:
  authenticated     - 認証完了
  browser_auth      - ブラウザ認証必要
  permission_prompt - 権限確認画面
  continue_prompt   - 続行確認画面
  terminal_setup    - Terminal設定画面
  theme_selection   - テーマ選択画面
  starting          - 起動中
  not_started       - 未起動
  unknown           - 不明

例:
  $(basename $0) check 0
  $(basename $0) wait 1 180
  $(basename $0) delegate 2
  $(basename $0) status
EOF
}

# メイン処理
main() {
    case "${1:-}" in
        "check")
            shift
            if [ $# -lt 1 ]; then
                log_error "使用法: check <pane>"
                exit 1
            fi
            state=$(get_auth_state "$1")
            echo "認証状態: $state"
            [ "$state" = "authenticated" ]
            ;;
        "wait")
            shift
            if [ $# -lt 1 ]; then
                log_error "使用法: wait <pane> [timeout]"
                exit 1
            fi
            wait_for_auth "$@"
            ;;
        "delegate")
            shift
            if [ $# -lt 1 ]; then
                log_error "使用法: delegate <pane>"
                exit 1
            fi
            delegate_auth "$@"
            ;;
        "status")
            check_all_status
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