#!/bin/bash

# 並列実装機能の起動テストスクリプト

echo "並列実装機能の起動テストを開始します..."

# テスト用のGitリポジトリ作成
TEST_DIR="/tmp/parallel_test_$(date +%s)"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

echo "テスト用Gitリポジトリを作成中..."
git init
echo "# Test Project" > README.md
git add README.md
git commit -m "Initial commit"

echo ""
echo "テストディレクトリ: $TEST_DIR"
echo ""

# 簡単なタスクで並列実装をテスト
WORKER_COUNT=5
echo "並列実装を開始します（ワーカー数: $WORKER_COUNT）"
echo "タスク: 'Hello Worldを出力する簡単なスクリプトを作成してください'"
echo ""

# 環境変数を設定
export CALLER_PWD="$TEST_DIR"

# parallel_implementコマンドを実行
/media/thithilab/volume/MCP_server/agent-collaboration-mcp/scripts/parallel/parallel_impl_manager.sh start \
    "Hello Worldを出力する簡単なスクリプトを作成してください" \
    $WORKER_COUNT \
    "complex" \
    "false" \
    "true" \
    "claude"

echo ""
echo "テスト完了"
echo "結果を確認するには、開いた端末を確認してください"
echo ""
echo "クリーンアップするには: rm -rf $TEST_DIR"