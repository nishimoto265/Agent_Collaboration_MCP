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
# 実行元のディレクトリに保存
PARALLEL_SESSION_DIR="${CALLER_PWD:-$(pwd)}/logs/parallel_sessions"
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
    
    # タイムスタンプとセッションID（ミリ秒とランダム値を含む）
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local random_suffix=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 4 | head -n 1)
    local session_id="parallel_${timestamp}_${random_suffix}"
    
    # 新しい端末で専用tmuxセッションを作成
    if [ "$use_new_terminal" = "true" ]; then
        log_info "新しい端末で専用tmuxセッションを作成中..."
        # 実行元のディレクトリを渡す
        local working_dir="${CALLER_PWD:-$(pwd)}"
        log_info "作業ディレクトリ: $working_dir"
        local tmux_session=$("$SCRIPT_DIR/terminal_launcher.sh" create-parallel "impl" "$worker_count" "$working_dir")
        
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
    # CALLER_PWDが設定されていない場合のみpwdを使用
    if [ -z "$CALLER_PWD" ]; then
        export CALLER_PWD="$(pwd)"
    fi
    local worktree_info=$("$SCRIPT_DIR/worktree_manager.sh" create-parallel "$session_id" "$worker_count")
    
    if [ $? -ne 0 ] || [ -z "$worktree_info" ]; then
        log_error "Worktree作成失敗"
        return 1
    fi
    
    # worktree_infoが有効なJSONか確認
    if ! echo "$worktree_info" | jq . >/dev/null 2>&1; then
        log_error "Worktree情報が不正なJSON形式です: $worktree_info"
        return 1
    fi
    
    # Worktree情報を解析
    local boss_branch="boss_${session_id}"
    # Bossは実行元のディレクトリで実行（NPX経由でも正しく動作）
    local boss_path="${CALLER_PWD:-$(pwd)}"
    
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
    # worker_panesの配列を安全に生成
    local worker_panes_json=""
    if [ ${#worker_panes[@]} -gt 0 ]; then
        worker_panes_json=$(printf '"%s",' "${worker_panes[@]}" | sed 's/,$//')
    fi
    
    # worktree_infoを安全にJSON化
    local worktree_info_json="{}"
    if [ -n "$worktree_info" ]; then
        worktree_info_json=$(echo "$worktree_info" | jq -c . 2>/dev/null || echo "{}")
    fi
    
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
    "worker_panes": [$worker_panes_json],
    "worktree_info": $worktree_info_json,
    "tmux_session": "${MULTIAGENT_SESSION}",
    "use_new_terminal": $use_new_terminal,
    "agent_type": "$agent_type",
    "status": "initializing"
}
EOF
    
    # Workerを起動
    log_info "Worker起動中..."
    local worker_branches=()
    if [ -n "$worktree_info" ]; then
        # jqを使って安全に配列を抽出
        local branches_json=$(echo "$worktree_info" | jq -r '.worker_branches[]' 2>/dev/null)
        if [ -n "$branches_json" ]; then
            while IFS= read -r branch; do
                worker_branches+=("$branch")
            done <<< "$branches_json"
        fi
    fi
    
    # worker_branchesが空の場合のフォールバック
    if [ ${#worker_branches[@]} -eq 0 ]; then
        log_error "Worker branches not found in worktree info"
        # デフォルトのブランチ名を生成
        for i in $(seq 1 $worker_count); do
            worker_branches+=("worker${i}_${session_id}")
        done
    fi
    
    for i in "${!worker_panes[@]}"; do
        local pane="${worker_panes[$i]}"
        local branch="${worker_branches[$i]}"
        # Worktreeのパスは実行元ディレクトリからの相対パス
        local base_dir="${CALLER_PWD:-$(pwd)}"
        local worktree_path="${base_dir}/worktrees/${branch}"
        
        log_info "Worker $((i+1)) 起動中 (ペイン: $pane, ブランチ: $branch, エージェント: $agent_type)"
        
        # Workerディレクトリに移動
        tmux send-keys -t "$pane" "cd '$worktree_path'" C-m
        sleep 0.5
        
        # Worker用のプロンプトメッセージを準備
        local worker_prompt="【並列実装タスク - Worker $((i+1))】

$prompt

注意事項:
- 他のWorkerとは独立して実装してください
- このディレクトリ ($worktree_path) で作業してください
- 実装が完了したら、Bashツールで以下のコマンドを実行してBossに報告してください：
  TMUX_SESSION=${MULTIAGENT_SESSION} ${SCRIPT_DIR}/../agent_tools/pane_controller.sh send 0 \"Worker$((i+1)) 実装完了\""
        
        # バックグラウンドでエージェント起動とプロンプト送信
        (
            sleep 1
            # agent_manager.shのパスを正しく設定
            local agent_manager="${SCRIPT_DIR}/../agent_tools/agent_manager.sh"
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
                
                # pane_controller.shのパスを設定
                local pane_controller="${SCRIPT_DIR}/../agent_tools/pane_controller.sh"
                
                # エージェント起動を待つ（最大60秒）
                local wait_count=0
                while [ $wait_count -lt 60 ]; do
                    sleep 1
                    wait_count=$((wait_count + 1))
                    
                    # Claudeプロンプトが表示されているか確認
                    local screen_content=$(tmux capture-pane -t "$pane" -p 2>/dev/null | tail -20)
                    if echo "$screen_content" | grep -q "Bypassing Permissions" || echo "$screen_content" | grep -q "█"; then
                        log_info "Worker $((i+1)) 起動完了確認 - タスクを送信中..."
                        # pane_controller.shを使ってメッセージを送信
                        export TMUX_SESSION="${MULTIAGENT_SESSION}"
                        "$pane_controller" send "$pane_number" "$worker_prompt"
                        break
                    fi
                done
            else
                log_error "agent_manager.shが見つかりません: $agent_manager"
            fi
        ) &
    done
    
    # Bossが必要な場合は準備と起動
    if [ "$needs_boss" = "true" ]; then
        log_info "Boss準備中 (ペイン: $boss_pane)"
        
        # Bossは実行元ディレクトリで実行
        local boss_working_dir="${CALLER_PWD:-$(pwd)}"
        log_info "Boss作業ディレクトリ: $boss_working_dir"
        tmux send-keys -t "$boss_pane" "cd '$boss_working_dir'" C-m
        sleep 0.5
        
        # Boss用のプロンプトメッセージを準備
        local boss_prompt="【並列実装タスク - Boss】

元のタスク:
$prompt

あなたはBossとして以下の役割を担います:
1. 全てのWorkerから「Worker〇 実装完了」のメッセージを受信するまで待機
2. 全Worker完了後、各実装を評価
3. 最良の実装を選択、または良い点を組み合わせて統合
4. 必要に応じてWorkerに改善指示

Worker情報:
$(for i in "${!worker_panes[@]}"; do
    echo "- Worker $((i+1)): ${worker_branches[$i]}"
    echo "  パス: ${boss_working_dir}/worktrees/${worker_branches[$i]}"
done)

重要：
- 全てのWorkerから「実装完了」の報告を受け取るまで評価を開始しないでください
- Workerからの報告は画面に「Worker1 実装完了」「Worker2 実装完了」のような形式で表示されます

評価基準:
- コード品質
- 要件の充足度
- パフォーマンス
- 保守性

"
        # autoMerge設定に応じて統合方法を追加
        if [ "$skip_review" = "true" ]; then
            boss_prompt+="統合方法（自動統合モード）:
【重要】評価完了後、必ず以下の手順でmasterブランチにマージしてください：

1. 各Workerの実装を評価（worktreeパスを使用して直接ファイルを読む）
2. 最良のWorkerブランチを選択
3. 以下のコマンドでマージ（Bashツールを使用）:
   git checkout master
   git merge --no-ff <選択したWorkerブランチ> -m \"自動統合: <選択理由>\"
   git log --oneline -1

注意: 
- あなたは既に${boss_working_dir}にいるので、直接gitコマンドを実行できます
- 統合版を作成する場合は、masterブランチで直接作成してコミットしてください
- マージしないとタスクは完了になりません

"
        else
            boss_prompt+="統合方法（手動統合モード）:
- 評価結果を提示し、どのWorkerの実装が最良かを報告してください
- マージは以下のコマンドで手動実行可能であることを案内:
  git checkout master
  git merge --no-ff <選択したWorkerブランチ>

"
        fi
        
        boss_prompt+="完了時は音を鳴らして通知してください。"
        
        # バックグラウンドでBossのエージェント起動とプロンプト送信
        (
            sleep 1
            local agent_manager="${SCRIPT_DIR}/../agent_tools/agent_manager.sh"
            if [ -f "$agent_manager" ]; then
                local boss_pane_number="${boss_pane##*.}"
                log_info "Boss用$agent_typeを起動中 (セッション: ${MULTIAGENT_SESSION}, ペイン番号: $boss_pane_number)"
                (
                    export TMUX_SESSION="${MULTIAGENT_SESSION}"
                    export CLAUDE_NO_BROWSER=1
                    "$agent_manager" start "$boss_pane_number" "$agent_type"
                )
                
                # pane_controller.shのパスを設定
                local pane_controller="${SCRIPT_DIR}/../agent_tools/pane_controller.sh"
                
                # エージェント起動を待つ（最大60秒）
                local wait_count=0
                while [ $wait_count -lt 60 ]; do
                    sleep 1
                    wait_count=$((wait_count + 1))
                    
                    # Claudeプロンプトが表示されているか確認
                    local screen_content=$(tmux capture-pane -t "$boss_pane" -p 2>/dev/null | tail -20)
                    if echo "$screen_content" | grep -q "Bypassing Permissions" || echo "$screen_content" | grep -q "█"; then
                        log_info "Boss 起動完了確認 - タスクを送信中..."
                        # pane_controller.shを使ってメッセージを送信
                        export TMUX_SESSION="${MULTIAGENT_SESSION}"
                        "$pane_controller" send "$boss_pane_number" "$boss_prompt"
                        break
                    fi
                done
            else
                log_error "agent_manager.shが見つかりません: $agent_manager"
            fi
        ) &
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
    # completed_workersの配列を安全に生成
    local completed_workers_json=""
    if [ ${#completed_workers[@]} -gt 0 ]; then
        completed_workers_json=$(printf '%s,' "${completed_workers[@]}" | sed 's/,$//')
    fi
    
    jq --argjson completed "[$completed_workers_json]" \
       --arg rate "$completion_rate" \
       '.completed_workers = $completed | .completion_rate = $rate' \
       "$session_file" > "${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"
    
    echo "$completion_rate"
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
        "status")
            get_parallel_status "$@"
            ;;
        *)
            echo "使用法: $0 {start|monitor|trigger-boss|status} [options]"
            echo ""
            echo "コマンド:"
            echo "  start <prompt> [worker_count] [complexity] [auto_merge]"
            echo "  monitor <session_id>"
            echo "  status [session_id]"
            exit 1
            ;;
    esac
}

# 実行
main "$@"