#!/bin/bash

# 🤖 認証代行システム
# エージェント間での認証代行を管理する汎用ツール

set -e

# 共通ライブラリの読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"
setup_directories "$SCRIPT_DIR"

# ログ関数のエイリアス（後方互換性のため）
log_delegator() { log "INFO" "$1" "DELEGATOR"; }
log_error() { log "ERROR" "$1" "ERROR"; }
log_success() { log "SUCCESS" "$1" "SUCCESS"; }

# スクリプトパスの設定
AUTH_HELPER="$AGENT_TOOLS_DIR/auth_helper.sh"
PANE_CONTROLLER="$AGENT_TOOLS_DIR/pane_controller.sh"
QUICK_SEND_SCRIPT="$MULTIAGENT_DIR/quick_send_with_verify.sh"

# 認証代行機能
request_auth_delegation() {
    local delegator_pane="${1:-}"
    local auth_source_pane="${2:-}"
    
    # 実際に存在するペインを動的に決定
    local pane_count=$(get_pane_count)
    if [ "$pane_count" -lt 2 ]; then
        log_error "セッション '$TMUX_SESSION' に最低2つのペインが必要です"
        return 1
    fi
    
    # ペイン番号が指定されていない場合、自動で選択
    if [ -z "$delegator_pane" ]; then
        delegator_pane=$((pane_count - 2))  # 最後から2番目
    fi
    if [ -z "$auth_source_pane" ]; then
        auth_source_pane=$((pane_count - 1))  # 最後
    fi
    
    local delegator_target=$(get_tmux_target "$delegator_pane")
    local auth_source_target=$(get_tmux_target "$auth_source_pane")
    
    log_delegator "🤖 認証代行依頼開始... (代行者: pane-$delegator_pane, 認証元: pane-$auth_source_pane)"
    
    # 認証URLを検出
    local screen=$(tmux capture-pane -t "$auth_source_target" -p -S - 2>/dev/null || echo "")
    local auth_url=$(echo "$screen" | tr -d '\n' | grep -oE 'https://[^[:space:]"'\'']+' | grep -E 'claude\.ai.*oauth|anthropic\.com.*oauth' | head -1)
    if [ -n "$auth_url" ]; then
        log_delegator "✅ 動的URL検出: $auth_url"
    else
        log_delegator "❌ 認証URL検出失敗 - 自律認証を中止"
        return 1
    fi
    
    # Agent自律認証指示
    local auth_request="あなた自身のClaude認証を完了してください。以下のURLにアクセスして認証を完了してください: $auth_url

Playwright MCPを使用して:
1. URLにアクセス
2. ページの内容を確認  
3. 承認ボタンを見つけてクリック
4. 認証完了まで進める

完了したら「認証完了」と報告してください。"
    
    # 代行者に指示を送信
    if [ -f "$QUICK_SEND_SCRIPT" ]; then
        "$QUICK_SEND_SCRIPT" "$delegator_pane" "$auth_request" --no-verify
    else
        tmux send-keys -t "$delegator_target" "$auth_request" C-m
    fi
    
    log_delegator "✅ 自律認証依頼送信完了"
    
    # 認証完了を待機
    local wait_count=0
    local max_wait=30
    while [ $wait_count -lt $max_wait ]; do
        screen=$(tmux capture-pane -t "$delegator_target" -p -S - 2>/dev/null || echo "")
        
        # 認証完了の報告または状態を検出
        if echo "$screen" | grep -q "認証完了\|authentication.*completed\|login.*successful\|How can I help\|/help for help"; then
            log_success "✅ 認証ヘルパー自律認証完了"
            return 0
        fi
        
        sleep 2
        wait_count=$((wait_count + 2))
        
        if [ $((wait_count % 10)) -eq 0 ]; then
            log_delegator "⏳ 認証ヘルパー自律認証待機中... ($wait_count/$max_wait 秒)"
        fi
    done
    
    log_delegator "⚠️ 認証ヘルパー自律認証タイムアウト"
    return 1
}

# 認証ヘルパー認証済み確認（スキップ機能付き）
check_auth_helper_authenticated() {
    # 実際に存在するペインから auth_helper を動的に決定
    local pane_count=$(get_pane_count)
    if [ "$pane_count" -lt 2 ]; then
        log_error "セッション '$TMUX_SESSION' に最低2つのペインが必要です"
        return 1
    fi
    
    # 最後から2番目をauth_helperとして使用
    local auth_helper_pane=$((pane_count - 2))
    local auth_helper_target=$(get_tmux_target "$auth_helper_pane")
    local max_wait="${1:-30}"
    local enable_auto_approve="${2:-true}"
    
    log_delegator "🔍 認証ヘルパー認証状態確認開始..."    
    
    # 最初に即座に認証完了チェック
    local screen=$(tmux capture-pane -t "$auth_helper_target" -p -S - 2>/dev/null || echo "")
    
    # 既に認証完了している場合は即座に返す
    if echo "$screen" | grep -q "/help for help.*status.*current setup"; then
        log_success "✅ 認証ヘルパー既に認証完了（即座に検出）"
        return 0
    fi
    
    # 改行で分かれている場合も検出
    if echo "$screen" | grep -q "/help for help" && echo "$screen" | grep -q "for your current setup"; then
        log_success "✅ 認証ヘルパー既に認証完了（分割表示検出）"
        return 0
    fi
    
    # その他の起動完了パターン
    if echo "$screen" | grep -i -q "how can i help\|try \"edit\|tip:" && \
       ! echo "$screen" | grep -q "Preview\|console\.log\|Press Enter to continue\|Use Claude Code's terminal setup"; then
        log_success "✅ 認証ヘルパー既に認証完了（UIパターン検出）"
        return 0
    fi
    
    # プロンプトが表示されている状態
    if echo "$screen" | grep -q "^>\|) \$\|~\$\|#\$" && \
       ! echo "$screen" | grep -q "Preview\|console\.log\|Press Enter to continue\|Use Claude Code's terminal setup"; then
        log_success "✅ 認証ヘルパー既に認証完了（プロンプト検出）"
        return 0
    fi
    
    # 認証が必要な場合のみ待機ループに入る
    log_delegator "認証ヘルパー認証待機を開始します（${max_wait}秒）..."
    
    local wait_count=0
    while [ $wait_count -lt $max_wait ]; do
        # 認証ヘルパーの画面内容を取得
        screen=$(tmux capture-pane -t "$delegator_target" -p -S - 2>/dev/null || echo "")
        
        # 起動完了パターンをチェック
        if echo "$screen" | grep -q "/help for help.*status.*current setup"; then
            log_success "✅ 認証ヘルパー認証完了確認（ヘルプメッセージ表示）"
            return 0
        fi
        
        # 改行で分かれている場合も検出
        if echo "$screen" | grep -q "/help for help" && echo "$screen" | grep -q "for your current setup"; then
            log_success "✅ 認証ヘルパー認証完了確認（ヘルプメッセージ分割表示）"
            return 0
        fi
        
        # その他の起動完了パターン
        if echo "$screen" | grep -i -q "how can i help\|try \"edit\|tip:" && \
           ! echo "$screen" | grep -q "Preview\|console\.log\|Press Enter to continue\|Use Claude Code's terminal setup"; then
            log_success "✅ 認証ヘルパー認証完了確認"
            return 0
        fi
        
        # プロンプトが表示されている状態
        if echo "$screen" | grep -q "^>\|) \$\|~\$\|#\$" && \
           ! echo "$screen" | grep -q "Preview\|console\.log\|Press Enter to continue\|Use Claude Code's terminal setup"; then
            log_success "✅ 認証ヘルパー認証完了確認（シェルプロンプト検出）"
            return 0
        fi
        
        # 認証が必要な場合 - 人間による手動認証を待機
        if echo "$screen" | grep -q "Opening.*browser\|Please visit\|authenticate.*browser\|Preview\|console\.log"; then
            log_delegator "⚠️ 認証ヘルパーの認証が必要です - 手動で認証してください"
            sleep 2
        fi
        
        sleep 1
        wait_count=$((wait_count + 1))
        
        if [ $((wait_count % 5)) -eq 0 ]; then
            log_delegator "⏳ 認証ヘルパー認証待機中... ($wait_count/$max_wait 秒)"
        fi
    done
    
    log_error "❌ 認証ヘルパー認証タイムアウト"
    return 1
}


# 認証代行可能なペインを自動検出（MCPと同じロジック使用）
find_auth_helper_pane() {
    
    log_delegator "🔍 認証代行可能なペインを検索中..." >&2
    
    # 実際に存在するペインを動的に取得
    local pane_list=$(get_all_panes)
    if [ -z "$pane_list" ]; then
        log_delegator "⚠️ セッション '$TMUX_SESSION' のペイン一覧を取得できません" >&2
        return 1
    fi
    
    # 存在するペインのみをチェックしてauthenticatedを探す
    for i in $pane_list; do
        # auth_helper.shのcheckコマンドを使用
        local state=$("$AUTH_HELPER" check "$i" 2>/dev/null | grep -o "authenticated")
        
        if [ "$state" = "authenticated" ]; then
            # 追加チェック：シェルプロンプト状態でないことを確認
            local screen=$("$PANE_CONTROLLER" capture "$i" 2>/dev/null || echo "")
            local last_lines=$(echo "$screen" | tail -3 | tr '[:upper:]' '[:lower:]')
            
            # 最下部がシェルプロンプトの場合はスキップ（MCPと同じロジック）
            if echo "$last_lines" | grep -qE '.*[\$#]\s*$' && \
               echo "$last_lines" | grep -qE 'org|worker|boss|auth_helper'; then
                continue  # シェル状態なのでスキップ
            fi
            
            log_delegator "✅ ペイン$i で認証済みClaude検出" >&2
            echo "$i"
            return 0
        fi
    done
    
    log_delegator "⚠️ 認証代行可能なペインが見つかりません" >&2
    return 1
}

# 認証ヘルパーに認証代行を依頼（スキップチェック付き）
delegate_auth_to_auth_helper() {
    local target_pane="$1"
    
    # 実際に存在するペインから auth_helper を動的に決定
    local pane_count=$(get_pane_count)
    if [ "$pane_count" -lt 2 ]; then
        log_error "セッション '$TMUX_SESSION' に最低2つのペインが必要です"
        return 1
    fi
    
    # 最後から2番目をauth_helperとして使用
    local auth_helper_pane=$((pane_count - 2))
    local auth_helper_target=$(get_tmux_target "$auth_helper_pane")
    
    log_delegator "🔧 DEBUG: delegate_auth_to_auth_helper called with args: $@"
    log_delegator "🔧 DEBUG: target_pane='$target_pane'"
    log_delegator "🤖 認証ヘルパーにペイン$target_pane の認証代行を依頼..."
    
    # 認証代行可能なペインを自動検出
    local auth_helper_pane=$(find_auth_helper_pane)
    if [ -z "$auth_helper_pane" ]; then
        log_delegator "❌ 認証代行可能なペインが見つかりません"
        return 1
    fi
    
    local auth_helper_target=$(get_tmux_target "$auth_helper_pane")
    log_delegator "📋 認証代行ペイン: $auth_helper_pane を使用"
    
    # 対象ペインが既に認証完了かチェック
    local target_session=$(get_tmux_target "$target_pane")
    local target_screen=$(tmux capture-pane -t "$target_session" -p -S - 2>/dev/null || echo "")
    
    # Claude Codeが既に起動完了している場合はスキップ
    if echo "$target_screen" | grep -q "/help for help.*status.*current setup"; then
        log_success "✅ ペイン$target_pane 既に認証完了 - 代行をスキップ"
        return 0
    fi
    
    if echo "$target_screen" | grep -q "/help for help" && echo "$target_screen" | grep -q "for your current setup"; then
        log_success "✅ ペイン$target_pane 既に認証完了 - 代行をスキップ"
        return 0
    fi
    
    if echo "$target_screen" | grep -i -q "how can i help\|try \"edit\|tip:" && \
       ! echo "$target_screen" | grep -q "Preview\|console\.log\|Press Enter to continue\|Use Claude Code's terminal setup"; then
        log_success "✅ ペイン$target_pane 既に認証完了 - 代行をスキップ"
        return 0
    fi
    
    
    # 対象ペインの認証URLを取得
    log_delegator "🔍 ペイン$target_pane から認証URL抽出中..."
    log_delegator "🔧 DEBUG: target_pane='$target_pane'"
    local auth_url=$(detect_auth_url_from_pane "$target_pane")
    
    if [ -z "$auth_url" ]; then
        log_delegator "❌ ペイン$target_pane からURL抽出失敗 - 認証代行を中止"
        return 1
    else
        log_delegator "✅ ペイン$target_pane から動的URL抽出成功"
    fi
    
    # 認証専用ペインの状態確認
    local auth_helper_state=$("$AUTH_HELPER" check $auth_helper_pane 2>&1 || echo "not_started")
    log_delegator "認証専用ペインの状態: $auth_helper_state"
    
    # シンプルな認証指示を送信
    log_delegator "🤖 Auth-Helperに認証コード取得指示を送信..."
    
    local auth_instruction="$auth_url でPlaywright MCPを使って承認ボタンをクリックし、認証コードを取得してください。認証コードを取得したら、quick_send_with_verify.shを使ってペイン$target_pane に認証コードを送信してください。送信後の操作は自動で処理されます。"
    
    if [ -f "$QUICK_SEND_SCRIPT" ]; then
        log_delegator "🔍 デバッグ: auth_helper_pane='$auth_helper_pane'"
        "$QUICK_SEND_SCRIPT" "$auth_helper_pane" "$auth_instruction" --verify
        log_delegator "✅ ペイン$auth_helper_pane に認証代行指示送信完了"
    else
        # fallback: tmux send-keys直接送信（確実なEnter送信）
        log_delegator "🔄 fallback: tmux直接送信でEnter確実実行"
        
        # プロンプトクリア
        tmux send-keys -t "$auth_helper_target" C-c
        sleep 0.5
        
        # メッセージ送信
        tmux send-keys -t "$auth_helper_target" "$auth_instruction"
        sleep 0.5
        
        # Enter確実送信
        tmux send-keys -t "$auth_helper_target" C-m
        sleep 0.3
        
        # 送信確認のため再度Enter（念のため）
        tmux send-keys -t "$auth_helper_target" C-m
        
        log_delegator "✅ Auth-HelperにAgent自律認証指示送信完了（fallback）"
    fi
    
    # 認証完了を確認
    log_delegator "⏳ 認証代行完了を待機中..."
    
    # 対象ペインの認証完了を確認
    local target_session=$(get_tmux_target "$target_pane")
    local auth_success=false
    local check_count=0
    local max_wait=120  # 120秒まで待機
    
    # 段階的監視システム
    local phase=1
    local agent_reported=false
    local auth_code_sent=false
    
    while [ $check_count -lt $max_wait ]; do
        local target_screen=$(tmux capture-pane -t "$target_session" -p -S - 2>/dev/null || echo "")
        local auth_helper_screen=$(tmux capture-pane -t "$auth_helper_target" -p -S - 2>/dev/null || echo "")
        
        # Phase 1: Agent認証実行中 (0-60秒)
        if [ $phase -eq 1 ] && [ $check_count -le 60 ]; then
            # 認証方法選択画面が表示された場合、Enterを送信して新しいURLを生成
            if echo "$target_screen" | grep -q "Select login method.*Claude account with subscription"; then
                log_delegator "✅ Phase 1: 認証方法選択画面検出 - Enter送信でURL生成"
                tmux send-keys -t "$target_session" C-m
                sleep 2
                # 新しいURLを取得して認証ヘルパーに送信（detect_auth_url_from_pane関数を使用）
                local new_auth_url=$(detect_auth_url_from_pane "$target_pane" 3)
                if [ -n "$new_auth_url" ] && [ "$new_auth_url" != "https://claude.ai/auth" ]; then
                    log_delegator "✅ Phase 1: 新しいURL検出 - 認証ヘルパーに更新指示送信"
                    if [ -f "$QUICK_SEND_SCRIPT" ]; then
                        "$QUICK_SEND_SCRIPT" "$auth_helper_pane" "新しい認証URLが生成されました。このURLで認証コードを取得してください: $new_auth_url" --no-verify
                    fi
                fi
            fi
            
            # 対象ペインに認証コードが到着した（画面変化）した場合は Phase 2 へ
            # ただし、テーマ選択画面（Choose the text style）は除外
            if echo "$target_screen" | grep -q "Press Enter to continue\|Press Enter to retry\|Security notes\|Use Claude Code's terminal setup\|dangerous.*mode\|No, exit.*Yes, I accept\|Login successful\|Logged in as\|OAuth error"; then
                log_delegator "✅ Phase 1: 対象ペインに認証コード到着検出 - Phase 2へ移行"
                phase=2
                auth_code_sent=true
            fi
            
            # 10秒毎に進捗表示
            if [ $((check_count % 10)) -eq 0 ]; then
                log_delegator "⏳ Phase 1: Agent認証実行中... ($check_count/60 秒)"
            fi
            
        # Phase 2: 認証コード送信・処理中 (60-90秒または認証完了報告後)
        elif [ $phase -eq 2 ] || ([ $phase -eq 1 ] && [ $check_count -gt 60 ]); then
            phase=2
            

            
            # 対象ペインの認証後操作を処理
            if echo "$target_screen" | grep -q "No, exit.*Yes, I accept\|Yes, I accept.*No, exit" || \
               (echo "$target_screen" | grep -q "dangerous" && echo "$target_screen" | grep -q "Yes, I accept"); then
                log_delegator "🔑 Phase 2: Bypass Permissions同意画面検出 - Down + Enter実行"
                tmux send-keys -t "$target_session" Down
                sleep 0.1
                tmux send-keys -t "$target_session" C-m
                sleep 0.5
                
            elif echo "$target_screen" | grep -q "Press Enter to continue\|Press Enter to retry\|Security notes\|Login successful\|Logged in as\|OAuth error"; then
                log_delegator "🔑 Phase 2: 続行画面検出 - Enter実行"
                tmux send-keys -t "$target_session" C-m
                sleep 0.5
                
            elif echo "$target_screen" | grep -q "Use Claude Code's terminal setup\|terminal.*setup\|Shift.*Enter"; then
                log_delegator "🔑 Phase 2: Terminal設定画面検出 - Yes選択（Enter実行）"
                tmux send-keys -t "$target_session" C-m
                sleep 0.5
                
            elif echo "$target_screen" | grep -q "Preview.*console\.log\|Preview.*Dark mode\|Preview.*Light mode"; then
                log_delegator "🔑 Phase 2: Preview画面検出 - テーマ選択スキップ（Enter×2）"
                tmux send-keys -t "$target_session" C-m
                sleep 0.1
                tmux send-keys -t "$target_session" C-m
                sleep 0.5
            elif echo "$target_screen" | grep -q "Choose the text style\|Welcome to Claude Code.*Let's get started"; then
                log_delegator "🔑 Phase 2: テーマ選択画面検出 - スキップ（Enter×2）"
                tmux send-keys -t "$target_session" C-m
                sleep 0.1
                tmux send-keys -t "$target_session" C-m
                sleep 0.5
            fi
            
            # 最終起動完了状態をチェックしてPhase 3へ移行
            if echo "$target_screen" | grep -q "/help for help.*status.*current setup" || \
               (echo "$target_screen" | grep -q "/help for help" && echo "$target_screen" | grep -q "for your current setup") || \
               (echo "$target_screen" | grep -i -q "how can i help\|try \"edit\|tip:" && ! echo "$target_screen" | grep -q "Preview\|console\.log\|Press Enter to continue\|Use Claude Code's terminal setup"); then
                log_delegator "✅ Phase 2: Claude Code起動完了検出 - Phase 3へ移行"
                phase=3
            fi
            
            # 5秒毎に進捗表示
            if [ $((check_count % 5)) -eq 0 ]; then
                log_delegator "⏳ Phase 2: 認証コード処理中... ($check_count/$max_wait 秒)"
            fi
            
        # Phase 3: Claude Code起動完了監視 (90秒以降または中間認証検出後)
        else
            phase=3
            
            # 最終的なClaude Code起動完了状態を監視（人間認証と同じロジック）
            if echo "$target_screen" | grep -q "/help for help.*status.*current setup"; then
                log_success "✅ Phase 3: Claude Code起動完了確認（ヘルプメッセージ表示）"
                auth_success=true
                break
            fi
            
            # 改行で分かれている場合も検出
            if echo "$target_screen" | grep -q "/help for help" && echo "$target_screen" | grep -q "for your current setup"; then
                log_success "✅ Phase 3: Claude Code起動完了確認（ヘルプメッセージ分割表示）"
                auth_success=true
                break
            fi
            
            # その他の起動完了パターン
            if echo "$target_screen" | grep -i -q "how can i help\|try \"edit\|tip:" && \
               ! echo "$target_screen" | grep -q "Preview\|console\.log\|Press Enter to continue\|Use Claude Code's terminal setup"; then
                log_success "✅ Phase 3: Claude Code起動完了確認"
                auth_success=true
                break
            fi
            
            # プロンプトが表示されている状態
            if echo "$target_screen" | grep -q "^>\|) \$\|~\$\|#\$" && \
               ! echo "$target_screen" | grep -q "Preview\|console\.log\|Press Enter to continue\|Use Claude Code's terminal setup"; then
                log_success "✅ Phase 3: Claude Code起動完了確認（シェルプロンプト検出）"
                auth_success=true
                break
            fi
            
            # 2秒毎に進捗表示
            if [ $((check_count % 2)) -eq 0 ]; then
                log_delegator "⏳ Phase 3: Claude Code起動完了監視中... ($check_count/$max_wait 秒)"
            fi
        fi
        
        sleep 1
        check_count=$((check_count + 1))
    done
    
    if [ "$auth_success" = true ]; then
        log_success "🎉 ペイン$target_pane 認証代行完了！（Phase $phase で完了）"
        return 0
    else
        log_error "❌ ペイン$target_pane の認証代行失敗（120秒タイムアウト）"
        return 1
    fi
}

# 対象ペイン状態確認機能（画面変化ベース）
check_target_pane_progress() {
    local target_pane="$1"
    local target_session=$(get_tmux_target "$target_pane")
    
    log_delegator "🔍 対象ペイン$target_pane の状態確認..."
    
    # 対象ペインの現在状態をチェック
    local target_screen=$(tmux capture-pane -t "$target_session" -p -S - 2>/dev/null || echo "")
    
    # 認証コード処理中または完了状態
    if echo "$target_screen" | grep -q "Press Enter to continue\|Security notes\|dangerous.*mode\|Use Claude Code's terminal setup\|How can I help\|/help for help\|Welcome to Claude"; then
        log_delegator "✅ 対象ペインで認証進行中または完了を確認"
        return 0
    fi
    
    return 1
}


# URL検出機能（tmux画面から認証URLを抽出）
detect_auth_url_from_pane() {
    local target_pane="$1"
    local target_session=$(get_tmux_target "$target_pane")
    local max_wait="${2:-10}"
    
    log_delegator "🔍 ペイン$target_pane からURLを検出中..." >&2
    log_delegator "🔧 DEBUG: target_session='$target_session'" >&2
    
    local wait_count=0
    while [ $wait_count -lt $max_wait ]; do
        # より広い範囲でスクリーンキャプチャ（複数行対応）
        local screen=$(tmux capture-pane -t "$target_session" -p -S -30 2>/dev/null || echo "")
        log_delegator "🔧 DEBUG: screen_length=$(echo "$screen" | wc -l) lines" >&2
        
        # より広範囲でURLを検索（認証メッセージがない場合も含む）
        local auth_url=$(echo "$screen" | tr -d '\n' | grep -oE 'https://[^[:space:]"'\'']+' | grep -E 'claude\.ai.*oauth|anthropic\.com.*oauth' | head -1)
        log_delegator "🔧 DEBUG: auth_url='$auth_url'" >&2
        
        # 履歴検索は無効化（古いURLを回避するため）
        # リアルタイム画面検索のみを使用
        
        # URLパターンが発見された場合
        if [ -n "$auth_url" ] || echo "$screen" | grep -q "Browser didn't open\|use the url below\|authenticate.*browser\|Please visit"; then
            log_delegator "🔧 DEBUG: URL pattern detected condition met" >&2
            # oauth URLが見つからない場合は、通常のauth URLを探す
            if [ -z "$auth_url" ]; then
                auth_url=$(echo "$screen" | tr -d '\n' | grep -oE 'https://[^[:space:]"'\'']+' | grep -E 'claude\.ai|anthropic\.com' | head -1)
                log_delegator "🔧 DEBUG: fallback auth_url='$auth_url'" >&2
            fi
            
            if [ -n "$auth_url" ]; then
                log_delegator "✅ ペイン$target_pane からURL抽出成功: $auth_url" >&2
                echo "$auth_url"
                return 0
            fi
        fi
        
        sleep 1
        wait_count=$((wait_count + 1))
    done
    
    log_delegator "❌ ペイン$target_pane からURL抽出失敗" >&2
    return 1
}

# 使用例とヘルプ
show_usage() {
    echo "認証ヘルパー認証代行システム"
    echo ""
    echo "使用法:"
    echo "  $0 check                           # 認証ヘルパー認証状態確認"
    echo "  $0 auto-approve                    # 認証ヘルパー自律認証依頼"
    echo "  $0 delegate <pane_num> [auth_url]  # 認証代行実行"
    echo "  $0 detect <pane_num>               # URL検出"
    echo ""
    echo "例:"
    echo "  $0 check                           # 認証ヘルパー認証確認"
    echo "  $0 auto-approve                    # 認証ヘルパー自律認証依頼実行"
    echo "  $0 delegate 0                      # ペイン0の認証を認証ヘルパーに代行依頼"
    echo "  $0 delegate 5 https://claude.ai/auth  # 特定URLで認証代行"
    echo "  $0 detect 3                        # ペイン3からURL検出"
}

# メイン処理
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-}" in
        "check")
            check_auth_helper_authenticated "$2"
            ;;
        "auto-approve")
            request_auth_auto_delegation
            ;;
        "delegate")
            if [ -z "$2" ]; then
                echo "エラー: ペイン番号が必要です"
                show_usage
                exit 1
            fi
            delegate_auth_to_auth_helper "$2" "$3"
            ;;
        "detect")
            if [ -z "$2" ]; then
                echo "エラー: ペイン番号が必要です"
                show_usage
                exit 1
            fi
            detect_auth_url_from_pane "$2" "$3"
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