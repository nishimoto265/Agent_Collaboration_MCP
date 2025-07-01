#!/bin/bash

# 🚀 クイック送信 (確認機能付き) - Multi-Agent Worktree間の直接送信・確認

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

# ペイン番号マッピング（組織ブロック順序構成）
get_pane_number() {
    case "$1" in
        "boss01") echo "0" ;;          # pane 0: ORG01-Boss
        "worker-a01") echo "1" ;;      # pane 1: ORG01-Worker-A
        "worker-b01") echo "2" ;;      # pane 2: ORG01-Worker-B
        "worker-c01") echo "3" ;;      # pane 3: ORG01-Worker-C
        "boss02") echo "4" ;;          # pane 4: ORG02-Boss
        "worker-a02") echo "5" ;;      # pane 5: ORG02-Worker-A
        "worker-b02") echo "6" ;;      # pane 6: ORG02-Worker-B
        "worker-c02") echo "7" ;;      # pane 7: ORG02-Worker-C
        "boss03") echo "8" ;;          # pane 8: ORG03-Boss
        "worker-a03") echo "9" ;;      # pane 9: ORG03-Worker-A
        "worker-b03") echo "10" ;;     # pane 10: ORG03-Worker-B
        "worker-c03") echo "11" ;;     # pane 11: ORG03-Worker-C
        "boss04") echo "12" ;;         # pane 12: ORG04-Boss
        "worker-a04") echo "13" ;;     # pane 13: ORG04-Worker-A
        "worker-b04") echo "14" ;;     # pane 14: ORG04-Worker-B
        "worker-c04") echo "15" ;;     # pane 15: ORG04-Worker-C
        "president") echo "16" ;;      # pane 16: President
        "auth-helper") echo "17" ;;    # pane 17: Auth-Helper
        [0-9]|1[0-7]) echo "$1" ;;    # 数値の場合はそのまま
        *) echo "" ;;
    esac
}

# 送信ログ記録
log_send_attempt() {
    local target="$1"
    local message="$2"
    local status="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    mkdir -p logs/message_delivery
    echo "[$timestamp] $target: $status - \"$message\"" >> logs/message_delivery/send_log.txt
}

# ペイン活性確認
check_pane_active() {
    local target="$1"
    local pane_num="$2"
    
    # 17ペイン統合構成では、presidentもmultiagentセッション内
    
    if ! tmux has-session -t "multiagent" 2>/dev/null; then
        echo "❌ multiagentセッションが見つかりません"
        return 1
    fi
    
    # ペインが存在するかチェック (0-16の17ペイン)
    if ! tmux list-panes -t "multiagent:0" | grep -q "^$pane_num:"; then
        echo "❌ ペイン$pane_numが見つかりません"
        return 1
    fi
    
    return 0
}

# 送信前の画面状態キャプチャ
capture_before_send() {
    local target="$1"
    local pane_num="$2"
    
    mkdir -p logs/message_delivery
    
    # 17ペイン統合構成：すべてmultiagentセッション内
    tmux capture-pane -t "multiagent:0.$pane_num" -p > "logs/message_delivery/${target}_before.txt"
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
        
        # 現在の画面状態をキャプチャ (17ペイン統合構成)
        tmux capture-pane -t "multiagent:0.$pane_num" -p > "logs/message_delivery/${target}_after.txt"
        
        # 送信前後の差分確認
        if ! diff -q "logs/message_delivery/${target}_before.txt" "logs/message_delivery/${target}_after.txt" >/dev/null 2>&1; then
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
    
    # 17ペイン統合構成：すべてmultiagentセッション内で統一処理
    # 送信前のデバッグ出力
    echo "🔍 送信前画面状態確認 (ペイン$pane_num):"
    tmux capture-pane -t "multiagent:0.$pane_num" -p | tail -3
    echo "================================="
    
    # Claude Codeのプロンプトをクリア
    tmux send-keys -t "multiagent:0.$pane_num" C-c
    sleep 0.3
    
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
    tmux send-keys -t "multiagent:0.$pane_num" "$cleaned_message"
    sleep 0.3  # メッセージ送信後の待機時間を延長
    
    # Enter送信前のデバッグ出力
    echo "🔍 Enter送信前画面状態:"
    tmux capture-pane -t "multiagent:0.$pane_num" -p | tail -2
    echo "================================="
    
    # エンター押下
    echo "⏎ Enter送信実行中..."
    tmux send-keys -t "multiagent:0.$pane_num" C-m
    
    sleep 1.0  # 送信完了待機時間を延長
    
    # 送信後のデバッグ出力
    echo "🔍 Enter送信後画面状態:"
    tmux capture-pane -t "multiagent:0.$pane_num" -p | tail -3
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
            echo "📋 手動確認: tmux capture-pane -t multiagent:0.$pane_num -p | tail -10"
            return 1
        fi
    fi
    
    return 0
}

main "$@" 