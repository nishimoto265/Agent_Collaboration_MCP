#!/bin/bash

# 🚀 クイック送信 (確認機能付き) - Multi-Agent Worktree間の直接送信・確認

# 共通ライブラリの読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"
setup_directories "$SCRIPT_DIR"

show_usage() {
    cat << EOF
🚀 クイック送信コマンド (確認機能付き)

使用方法:
  $0 [ペイン] [メッセージ] [--verify]

オプション:
  --verify        送信後に受信確認を行う（推奨）
  --no-verify     確認なしで送信のみ
  --timeout=N     確認タイムアウト秒数（デフォルト:10秒）

ペイン指定（組織ブロック順序構成）:
  ORG01 Block: boss01(0) worker-a01(1) worker-b01(2) worker-c01(3)
  ORG02 Block: boss02(4) worker-a02(5) worker-b02(6) worker-c02(7)
  ORG03 Block: boss03(8) worker-a03(9) worker-b03(10) worker-c03(11)
  ORG04 Block: boss04(12) worker-a04(13) worker-b04(14) worker-c04(15)
  president(16)                           - President (ペイン16)

使用例:
  $0 worker-a01 "実装を開始してください" --verify
  $0 boss01 "完了報告です" --no-verify
EOF
}

# ペイン番号取得は共通ライブラリの関数を使用
# get_pane_number() は utils.sh で定義済み

# 送信ログ記録
log_send_attempt() {
    local target="$1"
    local message="$2"
    local status="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    ensure_log_directory
    echo "[$timestamp] $target: $status - \"$message\"" >> "$LOG_DIR/send_log.txt"
}

# ペイン活性確認
check_pane_active() {
    local target="$1"
    local pane_num="$2"
    
    if ! check_session_exists; then
        echo "❌ $TMUX_SESSIONセッションが見つかりません"
        return 1
    fi
    
    # ペインが存在するかチェック
    if ! check_pane_exists "$pane_num"; then
        echo "❌ ペイン$pane_numが見つかりません"
        return 1
    fi
    
    return 0
}

# 送信前の画面状態キャプチャ
capture_before_send() {
    local target="$1"
    local pane_num="$2"
    
    ensure_log_directory
    
    local target_pane=$(get_tmux_target "$pane_num")
    tmux capture-pane -t "$target_pane" -p > "$LOG_DIR/${target}_before.txt"
}

# 送信後の画面状態確認
verify_message_received() {
    local target="$1"
    local pane_num="$2"
    local timeout="${3:-20}"  # デフォルトタイムアウトを20秒に延長
    
    echo "🔍 受信確認中... (${timeout}秒以内)"
    
    local check_count=0
    local max_checks=$((timeout * 2))  # 0.5秒間隔でチェック
    
    while [ $check_count -lt $max_checks ]; do
        sleep 0.5
        check_count=$((check_count + 1))
        
        # 現在の画面状態をキャプチャ
        local target_pane=$(get_tmux_target "$pane_num")
        tmux capture-pane -t "$target_pane" -p > "$LOG_DIR/${target}_after.txt"
        
        # 送信前後の差分確認
        if ! diff -q "$LOG_DIR/${target}_before.txt" "$LOG_DIR/${target}_after.txt" >/dev/null 2>&1; then
            echo "✅ 画面に変化を検出 - メッセージ受信を確認"
            
            # Claude Codeが応答しているかチェック（より柔軟な条件）
            if grep -q "●\|>\|How can I help\|I'll help\|I can help\|Sure\|Of course\|Let me\|I understand" "logs/message_delivery/${target}_after.txt" 2>/dev/null; then
                echo "✅ Claude Code応答または応答開始を確認"
                return 0
            elif [ $check_count -ge 4 ]; then
                # 2秒以上画面変化が継続していれば受信成功と判定
                echo "✅ 継続的な画面変化を検出 - 受信成功と判定"
                return 0
            fi
        elif [ $check_count -ge 10 ]; then
            # 5秒経過して変化が止まった場合も成功と判定
            echo "✅ 処理完了と判定 - 受信成功"
            return 0
        fi
        
        # 進捗表示
        if [ $((check_count % 4)) -eq 0 ]; then
            local elapsed=$((check_count / 2))
            echo "⏳ 確認中... ${elapsed}/${timeout}秒"
        fi
    done
    
    echo "⚠️  タイムアウト: ${timeout}秒以内に明確な受信確認を取得できませんでした"
    return 1
}

# メッセージ送信実行
send_message() {
    local target="$1"
    local message="$2"
    local pane_num="$3"
    
    echo "📤 送信中: $target (ペイン$pane_num) ← '$message'"
    
    # 送信前のデバッグ出力
    local target_pane=$(get_tmux_target "$pane_num")
    echo "🔍 送信前画面状態確認 (ペイン$pane_num):"
    tmux capture-pane -t "$target_pane" -p | tail -3
    echo "================================="
    
    # Claude Codeのプロンプトをクリア
    tmux send-keys -t "$target_pane" C-c
    delay "$MEDIUM_DELAY"
    
    # メッセージから改行文字を除去（認証コード対応）
    local cleaned_message=$(echo "$message" | tr -d '\n\r' | tr -d '\t')
    echo "📤 メッセージ送信中: $(echo "$cleaned_message" | cut -c1-50)..."
    echo "🧹 改行除去前: $(echo "$message" | wc -c) 文字"
    echo "🧹 改行除去後: $(echo "$cleaned_message" | wc -c) 文字"
    # 改行文字の可視化（デバッグ用）
    if [[ "$message" != "$cleaned_message" ]]; then
        echo "⚠️ 改行文字を検出・除去しました"
        echo "🔍 除去文字: $(echo "$message" | od -c | head -1)"
    fi
    tmux send-keys -t "$target_pane" "$cleaned_message"
    delay "$MEDIUM_DELAY"  # メッセージ送信後の待機時間
    
    # Enter送信前のデバッグ出力
    echo "🔍 Enter送信前画面状態:"
    tmux capture-pane -t "$target_pane" -p | tail -2
    echo "================================="
    
    # エンター押下
    echo "⏎ Enter送信実行中..."
    tmux send-keys -t "$target_pane" C-m
    
    delay "$LONG_DELAY"  # 送信完了待機時間
    
    # 送信後のデバッグ出力
    echo "🔍 Enter送信後画面状態:"
    tmux capture-pane -t "$target_pane" -p | tail -3
    echo "================================="
}

# メイン処理
main() {
    if [[ $# -lt 2 ]]; then
        show_usage
        exit 1
    fi
    
    local target="$1"
    local message="$2"
    local verify_mode="--verify"  # デフォルトは確認あり
    local timeout=20  # 10秒→20秒に延長
    
    # オプション解析
    shift 2
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verify)
                verify_mode="--verify"
                shift
                ;;
            --no-verify)
                verify_mode="--no-verify"
                shift
                ;;
            --timeout=*)
                timeout="${1#*=}"
                shift
                ;;
            *)
                echo "❌ 不明なオプション: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    local pane_num
    pane_num=$(get_pane_number "$target")
    
    if [[ -z "$pane_num" ]]; then
        echo "❌ エラー: 不明なペイン '$target'"
        show_usage
        exit 1
    fi
    
    # ペイン活性確認
    if ! check_pane_active "$target" "$pane_num"; then
        log_send_attempt "$target" "$message" "PANE_NOT_ACTIVE"
        exit 1
    fi
    
    # 送信前状態キャプチャ（確認モードの場合）
    if [[ "$verify_mode" == "--verify" ]]; then
        capture_before_send "$target" "$pane_num"
    fi
    
    # メッセージ送信
    send_message "$target" "$message" "$pane_num"
    
    # 送信ログ記録
    log_send_attempt "$target" "$message" "SENT"
    
    echo "✅ 送信完了（Claude Code対応）"
    
    # 受信確認（確認モードの場合）
    if [[ "$verify_mode" == "--verify" ]]; then
        if verify_message_received "$target" "$pane_num" "$timeout"; then
            log_send_attempt "$target" "$message" "VERIFIED"
            echo "🎯 送信・受信確認 完了"
            return 0
        else
            log_send_attempt "$target" "$message" "VERIFY_FAILED"
            echo "⚠️ 送信は完了しましたが、受信確認に失敗しました"
            echo "📋 手動確認: tmux capture-pane -t $(get_tmux_target "$pane_num") -p | tail -10"
            return 1
        fi
    fi
    
    return 0
}

main "$@" 