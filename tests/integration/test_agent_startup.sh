#!/bin/bash
# エージェント起動と認証フローの統合テスト

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# テスト用の設定
export PROJECT_DIR="$PROJECT_ROOT"
export MULTIAGENT_SESSION="test_multiagent_$$"
export TEST_MODE=1

source "$PROJECT_ROOT/scripts/common/config.sh"
source "$PROJECT_ROOT/scripts/common/utils.sh"

# テスト結果カウンター
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# テストユーティリティ関数
test_start() {
    local test_name="$1"
    echo -e "\n${YELLOW}▶ Testing: $test_name${NC}"
    TEST_COUNT=$((TEST_COUNT + 1))
}

test_pass() {
    local message="$1"
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "${GREEN}✅ PASS: $message${NC}"
}

test_fail() {
    local message="$1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo -e "${RED}❌ FAIL: $message${NC}"
}

# テスト用tmuxセッションのセットアップ
setup_test_session() {
    # 既存のテストセッションを削除
    tmux kill-session -t "$MULTIAGENT_SESSION" 2>/dev/null || true
    
    # 新しいテストセッションを作成
    tmux new-session -d -s "$MULTIAGENT_SESSION" -x 80 -y 24
    
    # テスト用のペインを作成（最小構成）
    tmux split-window -t "$MULTIAGENT_SESSION:0" -h
    tmux split-window -t "$MULTIAGENT_SESSION:0" -v
    
    sleep 1
}

# テストセッションのクリーンアップ
cleanup_test_session() {
    tmux kill-session -t "$MULTIAGENT_SESSION" 2>/dev/null || true
}

# テスト1: agent_manager.sh の基本機能
test_agent_manager_basics() {
    test_start "agent_manager.sh basic functionality"
    
    # スクリプトの存在確認
    if [ -f "$PROJECT_ROOT/scripts/agent_tools/agent_manager.sh" ]; then
        test_pass "agent_manager.sh exists"
    else
        test_fail "agent_manager.sh not found"
        return 1
    fi
    
    # スクリプトの実行権限確認
    if [ -x "$PROJECT_ROOT/scripts/agent_tools/agent_manager.sh" ]; then
        test_pass "agent_manager.sh is executable"
    else
        test_fail "agent_manager.sh is not executable"
    fi
    
    # ヘルプ表示テスト
    local help_output=$("$PROJECT_ROOT/scripts/agent_tools/agent_manager.sh" 2>&1)
    if echo "$help_output" | grep -q "使用法:"; then
        test_pass "Help message displayed correctly"
    else
        test_fail "Help message not found"
    fi
}

# テスト2: auth_helper.sh の状態検出
test_auth_state_detection() {
    test_start "auth_helper.sh state detection"
    
    # モックスクリーンデータをペインに送信
    local test_pane="${MULTIAGENT_SESSION}:0.0"
    
    # テストケース1: シェルプロンプト
    tmux send-keys -t "$test_pane" "user@host:~$ " C-m
    sleep 0.5
    
    local state=$("$PROJECT_ROOT/scripts/agent_tools/auth_helper.sh" state 0 2>/dev/null | cut -d'|' -f1)
    if [ "$state" = "stopped" ]; then
        test_pass "Shell prompt detected as stopped"
    else
        test_fail "Shell prompt detection failed (got: $state)"
    fi
    
    # ペインをクリア
    tmux send-keys -t "$test_pane" C-l
    sleep 0.5
}

# テスト3: MCP サーバーの起動テスト
test_mcp_server() {
    test_start "MCP server startup"
    
    # MCPサーバーを起動（バックグラウンド）
    local mcp_output=$(timeout 3 node "$PROJECT_ROOT/index.js" 2>&1)
    
    if echo "$mcp_output" | grep -q "Agent Collaboration MCP Server"; then
        test_pass "MCP server starts successfully"
    else
        test_fail "MCP server startup failed"
    fi
    
    # ツール登録の確認
    if echo "$mcp_output" | grep -q "Available tools:"; then
        test_pass "MCP tools registered"
    else
        test_fail "MCP tools not registered"
    fi
}

# テスト4: JavaScript ツールのテスト
test_js_tools() {
    test_start "JavaScript tools functionality"
    
    # agentManager.js のテスト
    if node -e "require('$PROJECT_ROOT/src/tools/agentManager.js')" 2>/dev/null; then
        test_pass "agentManager.js loads successfully"
    else
        test_fail "agentManager.js failed to load"
    fi
    
    # paneController.js のテスト
    if node -e "require('$PROJECT_ROOT/src/tools/paneController.js')" 2>/dev/null; then
        test_pass "paneController.js loads successfully"
    else
        test_fail "paneController.js failed to load"
    fi
}

# テスト5: 認証フローのモックテスト
test_auth_flow_mock() {
    test_start "Authentication flow (mock)"
    
    # テスト用のモックスクリプトを作成
    local mock_script="$PROJECT_ROOT/tests/fixtures/mock_claude.sh"
    mkdir -p "$(dirname "$mock_script")"
    
    cat > "$mock_script" << 'EOF'
#!/bin/bash
# Mock Claude script for testing
echo "Select login method:"
echo "1. Claude account with subscription"
sleep 2
echo "To continue, you'll need to authenticate in your browser"
sleep 2
echo "> "
echo "For shortcuts and bypassing permissions, see https://claude.ai/shortcuts"
EOF
    
    chmod +x "$mock_script"
    
    # モックスクリプトを実行
    tmux send-keys -t "${MULTIAGENT_SESSION}:0.1" "$mock_script" C-m
    sleep 3
    
    # 認証状態の遷移を確認
    local state=$("$PROJECT_ROOT/scripts/agent_tools/auth_helper.sh" state 1 2>/dev/null | cut -d'|' -f1)
    
    if [ "$state" = "auth_claude" ] || [ "$state" = "running_claude" ]; then
        test_pass "Authentication flow detected"
    else
        test_fail "Authentication flow not detected (state: $state)"
    fi
    
    # クリーンアップ
    tmux send-keys -t "${MULTIAGENT_SESSION}:0.1" C-c
}

# テスト6: tmux ペイン操作テスト
test_tmux_operations() {
    test_start "tmux pane operations"
    
    # ペインコントローラーのテスト
    local pane_info=$("$PROJECT_ROOT/scripts/agent_tools/pane_controller.sh" info "${MULTIAGENT_SESSION}:0.0" 2>/dev/null)
    
    if [ -n "$pane_info" ]; then
        test_pass "Pane info retrieval successful"
    else
        test_fail "Pane info retrieval failed"
    fi
    
    # ペイン一覧の取得
    local pane_list=$(tmux list-panes -t "$MULTIAGENT_SESSION" -F "#{pane_index}" 2>/dev/null)
    local pane_count=$(echo "$pane_list" | wc -l)
    
    if [ "$pane_count" -ge 3 ]; then
        test_pass "Test session has $pane_count panes"
    else
        test_fail "Insufficient test panes (found: $pane_count)"
    fi
}

# メイン実行関数
main() {
    echo "================================="
    echo "Running Integration Tests"
    echo "================================="
    
    # テストセッションのセットアップ
    echo "Setting up test environment..."
    setup_test_session
    
    # 各テストを実行
    test_agent_manager_basics
    test_auth_state_detection
    test_mcp_server
    test_js_tools
    test_auth_flow_mock
    test_tmux_operations
    
    # クリーンアップ
    echo -e "\nCleaning up test environment..."
    cleanup_test_session
    
    # 結果サマリー
    echo -e "\n================================="
    echo "Test Summary:"
    echo "Total: $TEST_COUNT"
    echo -e "Pass: ${GREEN}$PASS_COUNT${NC}"
    echo -e "Fail: ${RED}$FAIL_COUNT${NC}"
    echo "================================="
    
    # 終了コード
    [ $FAIL_COUNT -eq 0 ] && exit 0 || exit 1
}

# トラップ設定（エラー時のクリーンアップ）
trap cleanup_test_session EXIT

# テスト実行
main "$@"