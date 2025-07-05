#!/bin/bash
# 並列実装マネージャー

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

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# プロジェクトディレクトリを設定（scriptsの2階層上）
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
export PROJECT_DIR

source "$SCRIPT_DIR/../common/config.sh" 2>/dev/null || true
source "$SCRIPT_DIR/../common/utils.sh" 2>/dev/null || true

# 並列実装セッション情報を保存するディレクトリ
PARALLEL_SESSION_DIR="${PROJECT_DIR}/logs/parallel_sessions"
mkdir -p "$PARALLEL_SESSION_DIR"

# 複雑度に基づいてワーカー数を決定
determine_worker_count() {
    local complexity="$1"
    local requested_count="${2:-0}"
    
    # リクエストされた数が指定されていればそれを使用
    if [ "$requested_count" -gt 0 ]; then
        echo "$requested_count"
        return
    fi
    
    # 複雑度に基づいてデフォルト数を決定
    case "$complexity" in
        "simple")
            echo "1"  # Bossなし、Worker1体のみ
            ;;
        "medium")
            echo "3"  # Boss + Worker3体
            ;;
        "complex")
            echo "5"  # Boss + Worker5体
            ;;
        *)
            echo "3"  # デフォルト
            ;;
    esac
}

# 並列実装セッションを開始
start_parallel_implementation() {
    local prompt="$1"
    local worker_count="${2:-3}"
    local complexity="${3:-medium}"
    local skip_review="${4:-false}"  # skipオプション: trueで自動マージ
    local use_new_terminal="${5:-true}"
    local agent_type="${6:-claude}"  # エージェントタイプ: claudeまたはgemini
    
    log_info "並列実装開始: ワーカー数=$worker_count, 複雑度=$complexity"
    
    # ワーカー数を決定
    worker_count=$(determine_worker_count "$complexity" "$worker_count")
    
    # タイムスタンプとセッションID
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local session_id="parallel_${timestamp}"
    
    # 新しい端末で専用tmuxセッションを作成
    if [ "$use_new_terminal" = "true" ]; then
        log_info "新しい端末で専用tmuxセッションを作成中..."
        local tmux_session=$("$SCRIPT_DIR/terminal_launcher.sh" create-parallel "impl" "$worker_count")
        
        if [ -z "$tmux_session" ]; then
            log_error "tmuxセッションの作成に失敗しました"
            return 1
        fi
        
        # 新しいセッション名を使用
        MULTIAGENT_SESSION="$tmux_session"
        export MULTIAGENT_SESSION
        
        # セッションが完全に起動するまで待機
        sleep 2
    fi
    
    # セッション情報を保存
    local session_file="${PARALLEL_SESSION_DIR}/${session_id}.json"
    
    # Worktreeを作成
    log_info "Worktree作成中..."
    local worktree_info=$("$SCRIPT_DIR/worktree_manager.sh" create-parallel "$session_id" "$worker_count")
    
    if [ $? -ne 0 ]; then
        log_error "Worktree作成失敗"
        return 1
    fi
    
    # Worktree情報を解析
    local boss_branch=$(echo "$worktree_info" | grep -o '"boss_branch":"[^"]*"' | cut -d'"' -f4)
    local boss_path=$(echo "$worktree_info" | grep -o '"boss_path":"[^"]*"' | cut -d'"' -f4)
    
    # Bossが必要かどうか判定
    local needs_boss=true
    if [ "$complexity" = "simple" ] && [ "$worker_count" -eq 1 ]; then
        needs_boss=false
    fi
    
    # ペインを準備
    local boss_pane=""
    local worker_panes=()
    local start_pane=0
    
    if [ "$needs_boss" = "true" ]; then
        boss_pane="${MULTIAGENT_SESSION}:0.0"
        start_pane=1
    fi
    
    # Workerペインを割り当て
    if [ "$needs_boss" = "true" ]; then
        for i in $(seq 1 $worker_count); do
            worker_panes+=("${MULTIAGENT_SESSION}:0.$i")
        done
    else
        worker_panes+=("${MULTIAGENT_SESSION}:0.0")
    fi
    
    # セッション情報を保存
    cat > "$session_file" <<EOF
{
    "session_id": "$session_id",
    "timestamp": "$timestamp",
    "prompt": $(echo "$prompt" | jq -R -s .),
    "worker_count": $worker_count,
    "complexity": "$complexity",
    "skip_review": $skip_review,
    "needs_boss": $needs_boss,
    "boss_pane": "$boss_pane",
    "boss_branch": "$boss_branch",
    "boss_path": "$boss_path",
    "worker_panes": [$(printf '"%s",' "${worker_panes[@]}" | sed 's/,$//')],
    "worktree_info": $(echo "$worktree_info" | jq -c .),
    "tmux_session": "${MULTIAGENT_SESSION}",
    "use_new_terminal": $use_new_terminal,
    "agent_type": "$agent_type",
    "status": "initializing"
}
EOF
    
    # Workerを起動
    log_info "Worker起動中..."
    local worker_branches=($(echo "$worktree_info" | grep -o '"worker_branches":\[[^]]*\]' | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' ' ' | tr -d '"'))
    
    for i in "${!worker_panes[@]}"; do
        local pane="${worker_panes[$i]}"
        local branch="${worker_branches[$i]}"
        local worktree_path="${PROJECT_DIR}/worktrees/${branch}"
        
        log_info "Worker $((i+1)) 起動中 (ペイン: $pane, ブランチ: $branch, エージェント: $agent_type)"
        
        # Workerディレクトリに移動
        tmux send-keys -t "$pane" "cd '$worktree_path'" C-m
        sleep 0.5
        
        # プロンプトファイルを作成
        local prompt_file="${worktree_path}/.parallel_prompt.txt"
        cat > "$prompt_file" <<EOF
【並列実装タスク - Worker $((i+1))】

$prompt

注意事項:
- 他のWorkerとは独立して実装してください
- 完成したら「実装完了」と報告してください
- このディレクトリ ($worktree_path) で作業してください
EOF
        
        # エージェントを起動
        sleep 1
        # agent_manager.shのパスを正しく設定
        local agent_manager="${PROJECT_DIR}/scripts/agent_tools/agent_manager.sh"
        if [ -f "$agent_manager" ]; then
            # ペイン番号を抽出 (例: "parallel_impl_20250705_142530:0.1" -> "1")
            local pane_number="${pane##*.}"
            log_info "$agent_type を起動中 (セッション: ${MULTIAGENT_SESSION}, ペイン番号: $pane_number)"
            # 並列実装セッションで実行
            (
                export TMUX_SESSION="${MULTIAGENT_SESSION}"
                export CLAUDE_NO_BROWSER=1
                "$agent_manager" start "$pane_number" "$agent_type"
            )
            
            # バックグラウンドでプロンプト送信を待機
            (
                # エージェント起動を待つ（最大60秒）
                local wait_count=0
                while [ $wait_count -lt 60 ]; do
                    sleep 1
                    wait_count=$((wait_count + 1))
                    
                    # Claudeプロンプトが表示されているか確認
                    local screen_content=$(tmux capture-pane -t "$pane" -p 2>/dev/null | tail -20)
                    if echo "$screen_content" | grep -q "Bypassing Permissions" || echo "$screen_content" | grep -q "█"; then
                        log_info "Worker $((i+1)) 起動完了確認 - タスクを送信中..."
                        tmux send-keys -t "$pane" "cat '$prompt_file'" C-m
                        break
                    fi
                done
            ) &
        else
            log_error "agent_manager.shが見つかりません: $agent_manager"
        fi
    done
    
    # Bossが必要な場合は準備と起動
    if [ "$needs_boss" = "true" ]; then
        log_info "Boss準備中 (ペイン: $boss_pane, ブランチ: $boss_branch)"
        
        # Bossディレクトリに移動
        local boss_worktree_path="${PROJECT_DIR}/worktrees/${boss_branch}"
        tmux send-keys -t "$boss_pane" "cd '$boss_worktree_path'" C-m
        sleep 0.5
        
        # Boss用のプロンプトを準備
        local boss_prompt_file="${boss_worktree_path}/.boss_prompt.txt"
        cat > "$boss_prompt_file" <<EOF
【並列実装タスク - Boss】

元のタスク:
$prompt

あなたはBossとして以下の役割を担います:
1. 各Workerの実装を評価
2. 最良の実装を選択、または良い点を組み合わせて統合
3. 必要に応じてWorkerに改善指示

Worker情報:
$(for i in "${!worker_panes[@]}"; do
    echo "- Worker $((i+1)): ${worker_branches[$i]}"
done)

評価基準:
- コード品質
- 要件の充足度
- パフォーマンス
- 保守性

完了時は音を鳴らして通知してください。
EOF
        
        # Bossのエージェントを起動
        sleep 1
        local agent_manager="${PROJECT_DIR}/scripts/agent_tools/agent_manager.sh"
        if [ -f "$agent_manager" ]; then
            local boss_pane_number="${boss_pane##*.}"
            log_info "Boss用$agent_typeを起動中 (セッション: ${MULTIAGENT_SESSION}, ペイン番号: $boss_pane_number)"
            (
                export TMUX_SESSION="${MULTIAGENT_SESSION}"
                export CLAUDE_NO_BROWSER=1
                "$agent_manager" start "$boss_pane_number" "$agent_type"
            )
            
            # バックグラウンドでプロンプト送信を待機
            (
                # エージェント起動を待つ（最大60秒）
                local wait_count=0
                while [ $wait_count -lt 60 ]; do
                    sleep 1
                    wait_count=$((wait_count + 1))
                    
                    # Claudeプロンプトが表示されているか確認
                    local screen_content=$(tmux capture-pane -t "$boss_pane" -p 2>/dev/null | tail -20)
                    if echo "$screen_content" | grep -q "Bypassing Permissions" || echo "$screen_content" | grep -q "█"; then
                        log_info "Boss 起動完了確認 - タスクを送信中..."
                        tmux send-keys -t "$boss_pane" "cat '$boss_prompt_file'" C-m
                        break
                    fi
                done
            ) &
        else
            log_error "agent_manager.shが見つかりません: $agent_manager"
        fi
    fi
    
    # ステータスを更新
    jq '.status = "workers_started"' "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"
    
    # セッションIDを返す
    echo "$session_id"
    
    log_success "並列実装セッション開始: $session_id"
    return 0
}

# Worker完了を監視
monitor_worker_completion() {
    local session_id="$1"
    local session_file="${PARALLEL_SESSION_DIR}/${session_id}.json"
    
    if [ ! -f "$session_file" ]; then
        log_error "セッションファイルが見つかりません: $session_id"
        return 1
    fi
    
    # セッション情報を読み込み
    local worker_panes=($(jq -r '.worker_panes[]' "$session_file"))
    local completed_workers=()
    
    log_info "Worker完了を監視中..."
    
    # 各Workerの状態をチェック
    for pane in "${worker_panes[@]}"; do
        local screen_content=$(tmux capture-pane -t "${MULTIAGENT_SESSION}:0.$pane" -p)
        
        # 完了判定（"実装完了"というキーワードを探す）
        if echo "$screen_content" | grep -q "実装完了"; then
            completed_workers+=("$pane")
            log_info "Worker (ペイン $pane) 完了検出"
        fi
    done
    
    # 完了率を計算
    local completion_rate=$((${#completed_workers[@]} * 100 / ${#worker_panes[@]}))
    
    # ステータスを更新
    jq --argjson completed "[$(printf '%s,' "${completed_workers[@]}" | sed 's/,$//')]" \
       --arg rate "$completion_rate" \
       '.completed_workers = $completed | .completion_rate = $rate' \
       "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"
    
    echo "$completion_rate"
}

# Bossを起動して評価開始
# 注意: この関数は後方互換性のために残していますが、
# 現在はstart_parallel_implementation内でBossも自動起動されるため不要です
trigger_boss_evaluation() {
    local session_id="$1"
    local session_file="${PARALLEL_SESSION_DIR}/${session_id}.json"
    
    if [ ! -f "$session_file" ]; then
        log_error "セッションファイルが見つかりません: $session_id"
        return 1
    fi
    
    # セッション情報を読み込み
    local needs_boss=$(jq -r '.needs_boss' "$session_file")
    
    if [ "$needs_boss" != "true" ]; then
        log_info "Bossは不要です（シンプルタスク）"
        return 0
    fi
    
    log_info "Bossは既に起動済みです"
    return 0
}

# 並列実装ステータスを取得
get_parallel_status() {
    local session_id="$1"
    
    if [ -z "$session_id" ]; then
        # 全セッションをリスト
        ls -1 "$PARALLEL_SESSION_DIR"/*.json 2>/dev/null | while read session_file; do
            local sid=$(basename "$session_file" .json)
            local status=$(jq -r '.status' "$session_file")
            local timestamp=$(jq -r '.timestamp' "$session_file")
            local completion=$(jq -r '.completion_rate // 0' "$session_file")
            
            echo "$sid | Status: $status | Completion: ${completion}% | Time: $timestamp"
        done
    else
        # 特定セッションの詳細
        local session_file="${PARALLEL_SESSION_DIR}/${session_id}.json"
        
        if [ -f "$session_file" ]; then
            jq . "$session_file"
        else
            echo "Session not found: $session_id"
            return 1
        fi
    fi
}

# メイン処理
main() {
    local command="${1:-}"
    shift || true
    
    case "$command" in
        "start")
            start_parallel_implementation "$@"
            ;;
        "monitor")
            monitor_worker_completion "$@"
            ;;
        "trigger-boss")
            trigger_boss_evaluation "$@"
            ;;
        "status")
            get_parallel_status "$@"
            ;;
        *)
            echo "使用法: $0 {start|monitor|trigger-boss|status} [options]"
            echo ""
            echo "コマンド:"
            echo "  start <prompt> [worker_count] [complexity] [auto_merge]"
            echo "  monitor <session_id>"
            echo "  trigger-boss <session_id>"
            echo "  status [session_id]"
            exit 1
            ;;
    esac
}

# 実行
main "$@"