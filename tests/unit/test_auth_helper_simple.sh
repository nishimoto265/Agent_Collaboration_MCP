#!/bin/bash
# auth_helper.sh の簡易ユニットテスト

# テスト環境のセットアップ
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# テストユーティリティ
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    
    TEST_COUNT=$((TEST_COUNT + 1))
    
    if echo "$haystack" | grep -q "$needle"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "✅ PASS: $test_name"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "❌ FAIL: $test_name"
        echo "   Expected to contain: $needle"
        echo "   Actual: $haystack"
    fi
}

# テストケース: auth_helper.sh の基本動作
test_auth_helper_basic() {
    echo "=== Testing auth_helper.sh basic functionality ==="
    
    # スクリプトの存在確認
    if [ -f "$PROJECT_ROOT/scripts/agent_tools/auth_helper.sh" ]; then
        echo "✅ auth_helper.sh exists"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "❌ auth_helper.sh not found"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    TEST_COUNT=$((TEST_COUNT + 1))
    
    # スクリプトの実行権限確認
    if [ -x "$PROJECT_ROOT/scripts/agent_tools/auth_helper.sh" ]; then
        echo "✅ auth_helper.sh is executable"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "❌ auth_helper.sh is not executable"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    TEST_COUNT=$((TEST_COUNT + 1))
    
    # ヘルプ表示のテスト
    local help_output=$("$PROJECT_ROOT/scripts/agent_tools/auth_helper.sh" 2>&1)
    assert_contains "$help_output" "使用法:" "Help message displayed"
}

# テストケース: detect_agent_state 関数のソースとテスト
test_detect_function() {
    echo -e "\n=== Testing detect_agent_state function ==="
    
    # auth_helper.shをソース
    source "$PROJECT_ROOT/scripts/common/config.sh"
    source "$PROJECT_ROOT/scripts/common/utils.sh"
    source "$PROJECT_ROOT/scripts/agent_tools/auth_helper.sh"
    
    # 関数の存在確認
    if type -t detect_agent_state >/dev/null; then
        echo "✅ detect_agent_state function exists"
        PASS_COUNT=$((PASS_COUNT + 1))
        
        # Claude プロンプトのテスト
        local result=$(detect_agent_state "> 
For shortcuts and bypassing permissions, see https://claude.ai/shortcuts")
        assert_contains "$result" "running_claude" "Claude prompt detection"
        
        # ログイン選択画面のテスト
        result=$(detect_agent_state "Select login method:
1. Claude account with subscription
2. Anthropic Console account")
        assert_contains "$result" "auth_claude" "Login selection detection"
        
        # コード入力画面のテスト  
        result=$(detect_agent_state "Paste code here if prompted >")
        assert_contains "$result" "auth_claude" "Code input detection"
        assert_contains "$result" "code_input" "Code input type"
        
    else
        echo "❌ detect_agent_state function not found"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    TEST_COUNT=$((TEST_COUNT + 1))
}

# メインテスト実行
main() {
    echo "Running auth_helper.sh simple unit tests..."
    echo "=========================================="
    
    # 各テスト関数を実行
    test_auth_helper_basic
    test_detect_function
    
    # テスト結果サマリー
    echo -e "\n=========================================="
    echo "Test Summary:"
    echo "Total: $TEST_COUNT"
    echo "Pass: $PASS_COUNT"
    echo "Fail: $FAIL_COUNT"
    echo "=========================================="
    
    # 終了コード
    [ $FAIL_COUNT -eq 0 ] && exit 0 || exit 1
}

# テスト実行
main "$@"