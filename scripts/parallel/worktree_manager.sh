#!/bin/bash
# Worktree管理機能

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

source "$(dirname "$0")/../common/config.sh" 2>/dev/null || true
source "$(dirname "$0")/../common/utils.sh" 2>/dev/null || true

# Gitコマンドを呼び出し元のディレクトリで実行するラッパー
run_git_command() {
    local git_cmd="$@"
    
    if [ -n "$CALLER_PWD" ]; then
        log_info "Gitコマンド実行: $git_cmd (ディレクトリ: $CALLER_PWD)"
        (cd "$CALLER_PWD" && eval "$git_cmd")
    else
        log_info "Gitコマンド実行: $git_cmd (ディレクトリ: $(pwd))"
        eval "$git_cmd"
    fi
}

# Worktreeのベースディレクトリ
# 優先順位: 1) 環境変数 2) 呼び出し元のカレントディレクトリ 3) gitリポジトリのルート
if [ -z "$WORKTREE_BASE_DIR" ]; then
    if [ -n "$CALLER_PWD" ]; then
        WORKTREE_BASE_DIR="${CALLER_PWD}/worktrees"
    else
        # Gitリポジトリのルートディレクトリを取得
        GIT_ROOT=$(run_git_command "git rev-parse --show-toplevel 2>/dev/null" || pwd)
        WORKTREE_BASE_DIR="${GIT_ROOT}/worktrees"
    fi
fi

# Worktreeを作成
create_worktree() {
    local branch_name="$1"
    local base_branch="${2:-main}"
    local worktree_path="${WORKTREE_BASE_DIR}/${branch_name}"
    
    log_info "Worktree作成中: $branch_name (ベース: $base_branch)"
    log_info "WORKTREE_BASE_DIR: $WORKTREE_BASE_DIR"
    log_info "CALLER_PWD: ${CALLER_PWD:-未設定}"
    log_info "現在のディレクトリ: $(pwd)"
    
    # Gitリポジトリかどうか確認
    if ! run_git_command "git rev-parse --git-dir" >/dev/null 2>&1; then
        log_error "Gitリポジトリではありません: ${CALLER_PWD:-$(pwd)}"
        log_error "並列実装機能を使用するには、Gitリポジトリ内で実行してください"
        return 1
    fi
    
    # ベースディレクトリを作成
    mkdir -p "$WORKTREE_BASE_DIR"
    
    # 既存のworktreeをチェック
    if run_git_command "git worktree list" | grep -q "$worktree_path"; then
        log_error "Worktree already exists: $branch_name"
        return 1
    fi
    
    # 既存のブランチ（リモート含む）をチェック
    if run_git_command "git branch -a" | grep -q "$branch_name"; then
        log_warn "ブランチが既に存在します: $branch_name"
        # 既存ブランチを削除するか、別の名前を使用
        local new_branch_name="${branch_name}_$(date +%s)"
        log_info "新しいブランチ名を使用: $new_branch_name"
        branch_name="$new_branch_name"
        worktree_path="${WORKTREE_BASE_DIR}/${branch_name}"
    fi
    
    # ベースブランチが存在するか確認
    if ! run_git_command "git rev-parse --verify '$base_branch'" >/dev/null 2>&1; then
        log_error "ベースブランチが存在しません: $base_branch"
        # masterまたはmainを試す
        if run_git_command "git rev-parse --verify 'master'" >/dev/null 2>&1; then
            base_branch="master"
            log_info "masterブランチを使用します"
        elif run_git_command "git rev-parse --verify 'main'" >/dev/null 2>&1; then
            base_branch="main"
            log_info "mainブランチを使用します"
        else
            log_error "有効なベースブランチが見つかりません"
            return 1
        fi
    fi
    
    # ブランチが存在するかチェック
    if run_git_command "git branch --list '$branch_name'" | grep -q "$branch_name"; then
        # 既存ブランチを使用
        run_git_command "git worktree add '$worktree_path' '$branch_name'" >&2
    else
        # 新しいブランチを作成
        run_git_command "git worktree add -b '$branch_name' '$worktree_path' '$base_branch'" >&2
    fi
    
    local result=$?
    
    if [ $result -eq 0 ]; then
        log_success "Worktree作成完了: $worktree_path"
        echo "$worktree_path"
        return 0
    else
        log_error "Worktree作成失敗: $branch_name"
        return 1
    fi
}

# Worktreeリストを取得
list_worktrees() {
    local filter="${1:-}"
    
    if [ -z "$filter" ]; then
        run_git_command "git worktree list"
    else
        run_git_command "git worktree list" | grep "$filter"
    fi
}

# Worktreeをクリーンアップ
cleanup_worktree() {
    local branch_name="$1"
    local worktree_path="${WORKTREE_BASE_DIR}/${branch_name}"
    local force="${2:-false}"
    
    log_info "Worktreeクリーンアップ中: $branch_name"
    
    # Worktreeが存在するかチェック
    if ! run_git_command "git worktree list" | grep -q "$worktree_path"; then
        log_error "Worktree not found: $branch_name"
        return 1
    fi
    
    # 強制削除フラグ
    local remove_flags=""
    if [ "$force" = "true" ]; then
        remove_flags="--force"
    fi
    
    # Worktreeを削除
    if run_git_command "git worktree remove $remove_flags '$worktree_path'" >&2; then
        log_success "Worktree削除完了: $branch_name"
        
        # ブランチも削除するか確認
        if [ "$force" = "true" ]; then
            run_git_command "git branch -D '$branch_name'" >&2 || true
            log_info "ブランチも削除: $branch_name"
        fi
        
        return 0
    else
        log_error "Worktree削除失敗: $branch_name"
        return 1
    fi
}

# Worktreeをマージ
merge_worktree() {
    local source_branch="$1"
    local target_branch="${2:-master}"
    local auto_merge="${3:-false}"
    
    log_info "Worktreeマージ中: $source_branch -> $target_branch"
    
    # 現在のブランチを保存
    local current_branch=$(run_git_command "git branch --show-current")
    
    # ターゲットブランチに切り替え
    run_git_command "git checkout '$target_branch'" >&2
    
    if [ "$auto_merge" = "true" ]; then
        # 自動マージ
        if run_git_command "git merge --no-ff '$source_branch' -m 'Merge parallel implementation: $source_branch'" >&2; then
            log_success "自動マージ完了: $source_branch -> $target_branch"
        else
            log_error "自動マージ失敗 - コンフリクト解決が必要"
            run_git_command "git merge --abort" >&2
            run_git_command "git checkout '$current_branch'" >&2
            return 1
        fi
    else
        # マージプレビュー
        echo "=== マージプレビュー ==="
        run_git_command "git log --oneline '$target_branch'..'$source_branch'"
        echo "======================="
        echo ""
        echo "マージを実行するには以下のコマンドを実行:"
        echo "  git checkout $target_branch"
        echo "  git merge --no-ff $source_branch"
    fi
    
    # 元のブランチに戻る
    run_git_command "git checkout '$current_branch'" >&2
    
    return 0
}

# 並列実装用のWorktreeセットを作成
create_parallel_worktrees() {
    local base_name="$1"
    local worker_count="$2"
    local base_branch="${3:-master}"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local session_id="${base_name}_${timestamp}"
    
    # Bossは親ディレクトリで実行するため、worktreeは作成しない
    
    # Worker用のworktree
    local worker_branches=()
    for i in $(seq 1 "$worker_count"); do
        local worker_branch="worker${i}_${session_id}"
        local worker_path=$(create_worktree "$worker_branch" "$base_branch")
        
        if [ -z "$worker_path" ]; then
            # エラー時は作成済みのWorker worktreeをクリーンアップ
            for wb in "${worker_branches[@]}"; do
                cleanup_worktree "$wb" true
            done
            return 1
        fi
        
        worker_branches+=("$worker_branch")
    done
    
    # 結果を出力
    echo "{\"session_id\":\"$session_id\","
    echo " \"worker_branches\":[$(printf '"%s",' "${worker_branches[@]}" | sed 's/,$//')],"
    echo " \"timestamp\":\"$timestamp\"}"
}

# メイン処理
main() {
    local command="${1:-}"
    shift || true
    
    case "$command" in
        "create")
            create_worktree "$@"
            ;;
        "list")
            list_worktrees "$@"
            ;;
        "cleanup")
            cleanup_worktree "$@"
            ;;
        "merge")
            merge_worktree "$@"
            ;;
        "create-parallel")
            create_parallel_worktrees "$@"
            ;;
        *)
            echo "使用法: $0 {create|list|cleanup|merge|create-parallel} [options]"
            echo ""
            echo "コマンド:"
            echo "  create <branch_name> [base_branch]     - Worktreeを作成"
            echo "  list [filter]                          - Worktreeリストを表示"
            echo "  cleanup <branch_name> [force]          - Worktreeを削除"
            echo "  merge <source> [target] [auto]         - Worktreeをマージ"
            echo "  create-parallel <base_name> <count>    - 並列実装用Worktreeセットを作成"
            exit 1
            ;;
    esac
}

# 実行
main "$@"