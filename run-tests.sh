#!/bin/bash
# 全テストを実行するスクリプト

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 結果カウンター
TOTAL_TESTS=0
TOTAL_PASS=0
TOTAL_FAIL=0

echo -e "${BLUE}=================================${NC}"
echo -e "${BLUE}Agent Collaboration MCP Test Suite${NC}"
echo -e "${BLUE}=================================${NC}"

# 環境チェック
check_environment() {
    echo -e "\n${YELLOW}Checking environment...${NC}"
    
    # Node.jsチェック
    if command -v node >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Node.js: $(node --version)"
    else
        echo -e "${RED}✗${NC} Node.js not found"
        exit 1
    fi
    
    # tmuxチェック
    if command -v tmux >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} tmux: $(tmux -V)"
    else
        echo -e "${RED}✗${NC} tmux not found"
        exit 1
    fi
    
    # bashバージョンチェック
    echo -e "${GREEN}✓${NC} Bash: ${BASH_VERSION}"
}

# ユニットテストの実行
run_unit_tests() {
    echo -e "\n${YELLOW}Running Unit Tests...${NC}"
    echo "============================="
    
    for test_file in tests/unit/*.sh; do
        if [ -f "$test_file" ]; then
            echo -e "\n${BLUE}Running: $(basename "$test_file")${NC}"
            
            if bash "$test_file"; then
                TOTAL_PASS=$((TOTAL_PASS + 1))
                echo -e "${GREEN}✓ $(basename "$test_file") passed${NC}"
            else
                TOTAL_FAIL=$((TOTAL_FAIL + 1))
                echo -e "${RED}✗ $(basename "$test_file") failed${NC}"
            fi
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
        fi
    done
}

# 統合テストの実行
run_integration_tests() {
    echo -e "\n${YELLOW}Running Integration Tests...${NC}"
    echo "================================"
    
    # CI環境チェック
    if [ -n "$CI" ]; then
        echo "Running in CI environment - some tests may be skipped"
    fi
    
    for test_file in tests/integration/*.sh; do
        if [ -f "$test_file" ]; then
            echo -e "\n${BLUE}Running: $(basename "$test_file")${NC}"
            
            if bash "$test_file"; then
                TOTAL_PASS=$((TOTAL_PASS + 1))
                echo -e "${GREEN}✓ $(basename "$test_file") passed${NC}"
            else
                TOTAL_FAIL=$((TOTAL_FAIL + 1))
                echo -e "${RED}✗ $(basename "$test_file") failed${NC}"
            fi
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
        fi
    done
}

# スクリプトの構文チェック
check_script_syntax() {
    echo -e "\n${YELLOW}Checking Script Syntax...${NC}"
    echo "=========================="
    
    local syntax_errors=0
    
    # Bashスクリプトの構文チェック
    for script in scripts/**/*.sh tests/**/*.sh; do
        if [ -f "$script" ]; then
            if bash -n "$script" 2>/dev/null; then
                echo -e "${GREEN}✓${NC} $script"
            else
                echo -e "${RED}✗${NC} $script has syntax errors"
                syntax_errors=$((syntax_errors + 1))
            fi
        fi
    done
    
    if [ $syntax_errors -eq 0 ]; then
        echo -e "${GREEN}All scripts have valid syntax${NC}"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo -e "${RED}Found $syntax_errors scripts with syntax errors${NC}"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# JavaScriptのリント
lint_javascript() {
    echo -e "\n${YELLOW}Linting JavaScript...${NC}"
    echo "====================="
    
    # ESLintがインストールされているか確認
    if npm list eslint >/dev/null 2>&1 || [ -f node_modules/.bin/eslint ]; then
        if npx eslint index.js src/**/*.js; then
            echo -e "${GREEN}✓ JavaScript linting passed${NC}"
            TOTAL_PASS=$((TOTAL_PASS + 1))
        else
            echo -e "${YELLOW}⚠ JavaScript linting warnings${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ ESLint not installed - skipping JavaScript linting${NC}"
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# パッケージ検証
verify_package() {
    echo -e "\n${YELLOW}Verifying Package...${NC}"
    echo "===================="
    
    # package.jsonの検証
    if node -e "JSON.parse(require('fs').readFileSync('package.json'))"; then
        echo -e "${GREEN}✓${NC} package.json is valid JSON"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo -e "${RED}✗${NC} package.json is invalid"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # 必要なファイルの存在確認
    local required_files=(
        "index.js"
        "package.json"
        "README.md"
        "scripts/agent_tools/agent_manager.sh"
        "scripts/agent_tools/auth_helper.sh"
    )
    
    local missing_files=0
    for file in "${required_files[@]}"; do
        if [ -f "$file" ]; then
            echo -e "${GREEN}✓${NC} $file exists"
        else
            echo -e "${RED}✗${NC} $file is missing"
            missing_files=$((missing_files + 1))
        fi
    done
    
    if [ $missing_files -eq 0 ]; then
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# レポート生成
generate_report() {
    echo -e "\n${BLUE}=================================${NC}"
    echo -e "${BLUE}Test Summary${NC}"
    echo -e "${BLUE}=================================${NC}"
    echo "Total Tests: $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$TOTAL_PASS${NC}"
    echo -e "Failed: ${RED}$TOTAL_FAIL${NC}"
    
    if [ $TOTAL_FAIL -eq 0 ]; then
        echo -e "\n${GREEN}✅ All tests passed!${NC}"
        return 0
    else
        echo -e "\n${RED}❌ Some tests failed${NC}"
        return 1
    fi
}

# メイン実行
main() {
    # 引数処理
    case "${1:-all}" in
        unit)
            check_environment
            run_unit_tests
            ;;
        integration)
            check_environment
            run_integration_tests
            ;;
        lint)
            check_script_syntax
            lint_javascript
            ;;
        all)
            check_environment
            run_unit_tests
            run_integration_tests
            check_script_syntax
            lint_javascript
            verify_package
            ;;
        *)
            echo "Usage: $0 [all|unit|integration|lint]"
            exit 1
            ;;
    esac
    
    generate_report
}

# 実行
main "$@"