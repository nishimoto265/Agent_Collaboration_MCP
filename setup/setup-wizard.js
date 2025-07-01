#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const readline = require('readline');

/**
 * Agent Collaboration MCP セットアップウィザード
 * 他環境・他ユーザーでの簡単導入をサポート
 */

class SetupWizard {
  constructor() {
    this.rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });
    this.config = {
      projectDir: process.cwd(),
      sessionName: 'multiagent',
      layout: 'minimal-8pane',
      agentScripts: false
    };
  }

  async question(query) {
    return new Promise(resolve => this.rl.question(query, resolve));
  }

  log(message, type = 'info') {
    const colors = {
      info: '\x1b[36m',
      success: '\x1b[32m', 
      warn: '\x1b[33m',
      error: '\x1b[31m',
      reset: '\x1b[0m'
    };
    console.log(`${colors[type]}[${type.toUpperCase()}]${colors.reset} ${message}`);
  }

  async welcome() {
    console.log('\n🤖 Agent Collaboration MCP セットアップウィザード');
    console.log('='.repeat(50));
    console.log('このウィザードでは、あなたの環境に最適な設定を作成します。\n');
  }

  async detectEnvironment() {
    this.log('環境検出中...', 'info');
    
    // tmux存在確認
    try {
      execSync('which tmux', { stdio: 'pipe' });
      this.log('✅ tmux が見つかりました', 'success');
    } catch (error) {
      this.log('❌ tmux が見つかりません。先にインストールしてください。', 'error');
      process.exit(1);
    }
    
    // Node.js バージョン確認
    const nodeVersion = process.version;
    this.log(`✅ Node.js ${nodeVersion}`, 'success');
    
    return true;
  }

  async configurePaths() {
    console.log('\n📂 プロジェクト設定');
    console.log('-'.repeat(30));
    
    const currentDir = process.cwd();
    const projectDir = await this.question(
      `プロジェクトディレクトリを入力してください (現在: ${currentDir}): `
    );
    
    this.config.projectDir = projectDir.trim() || currentDir;
    
    const sessionName = await this.question(
      'tmuxセッション名を入力してください (デフォルト: multiagent): '
    );
    
    this.config.sessionName = sessionName.trim() || 'multiagent';
  }

  async configureLayout() {
    console.log('\n🏗️ ペイン構成選択');
    console.log('-'.repeat(30));
    console.log('1. minimal-8pane - 最小構成 (1組織 + 管理ペイン)');
    console.log('2. standard-18pane - 標準構成 (4組織 + 管理ペイン)');
    console.log('3. custom - カスタム構成');
    
    const choice = await this.question('選択してください (1-3): ');
    
    switch (choice.trim()) {
      case '1':
        this.config.layout = 'minimal-8pane';
        break;
      case '2':
        this.config.layout = 'standard-18pane';
        break;
      case '3':
        this.config.layout = await this.configureCustomLayout();
        break;
      default:
        this.log('デフォルト (minimal-8pane) を選択しました', 'warn');
        this.config.layout = 'minimal-8pane';
    }
  }

  async configureCustomLayout() {
    console.log('\n⚙️ カスタム構成設定');
    console.log('-'.repeat(30));
    
    const orgCount = await this.question('組織数を入力してください (1-8): ');
    const workersPerOrg = await this.question('組織あたりのWorker数を入力してください (1-5): ');
    
    return this.generateCustomLayout(
      parseInt(orgCount) || 1,
      parseInt(workersPerOrg) || 3
    );
  }

  generateCustomLayout(orgCount, workersPerOrg) {
    const customLayout = {
      description: `カスタム構成 - ${orgCount}組織, 各${workersPerOrg}Worker`,
      totalPanes: orgCount * (workersPerOrg + 1) + 2, // +1 for boss, +2 for president/auth-helper
      panes: {}
    };

    let paneIndex = 0;
    
    // 組織ペイン生成
    for (let org = 1; org <= orgCount; org++) {
      const orgNum = org.toString().padStart(2, '0');
      
      // Boss
      customLayout.panes[paneIndex] = {
        name: `boss${orgNum}`,
        displayName: `ORG${orgNum}-Boss`,
        organization: `org-${orgNum}`,
        role: 'boss',
        agentType: 'claude',
        workdir: '.',
        description: `組織${orgNum}統括`
      };
      paneIndex++;
      
      // Workers
      for (let worker = 0; worker < workersPerOrg; worker++) {
        const workerLetter = String.fromCharCode(97 + worker); // a, b, c...
        customLayout.panes[paneIndex] = {
          name: `worker-${workerLetter}${orgNum}`,
          displayName: `ORG${orgNum}-Worker-${workerLetter.toUpperCase()}`,
          organization: `org-${orgNum}`,
          role: 'worker',
          agentType: 'claude',
          workdir: '.',
          description: `組織${orgNum}実装${workerLetter.toUpperCase()}`
        };
        paneIndex++;
      }
    }
    
    // 管理ペイン
    customLayout.panes[paneIndex] = {
      name: 'president',
      displayName: 'PRESIDENT',
      organization: 'main',
      role: 'president',
      agentType: 'claude',
      workdir: '.',
      description: 'プロジェクト統括'
    };
    paneIndex++;
    
    customLayout.panes[paneIndex] = {
      name: 'auth-helper',
      displayName: 'AUTH-HELPER', 
      organization: 'main',
      role: 'auth-helper',
      agentType: 'claude',
      workdir: '.',
      description: '認証サポート'
    };
    
    return customLayout;
  }

  async checkAgentScripts() {
    console.log('\n🔧 エージェント管理スクリプト');
    console.log('-'.repeat(30));
    
    const scriptsPath = path.join(this.config.projectDir, 'scripts', 'agent_tools');
    const hasScripts = fs.existsSync(scriptsPath);
    
    if (hasScripts) {
      this.log('✅ エージェント管理スクリプトが見つかりました', 'success');
      this.config.agentScripts = true;
    } else {
      this.log('⚠️ エージェント管理スクリプトが見つかりません', 'warn');
      console.log('MCPサーバーは動作しますが、エージェント起動機能は制限されます。');
      
      const install = await this.question('基本スクリプトを作成しますか？ (y/N): ');
      if (install.toLowerCase() === 'y') {
        await this.createBasicScripts();
        this.config.agentScripts = true;
      }
    }
  }

  async createBasicScripts() {
    const scriptsDir = path.join(this.config.projectDir, 'scripts', 'agent_tools');
    
    // ディレクトリ作成
    fs.mkdirSync(scriptsDir, { recursive: true });
    
    // 基本的なagent_manager.shを作成
    const agentManagerScript = `#!/bin/bash
# 基本的なエージェント管理スクリプト (auto-generated)

PANE_NUM="$1"
AGENT_TYPE="$2"

if [ -z "$PANE_NUM" ] || [ -z "$AGENT_TYPE" ]; then
    echo "Usage: $0 <pane_number> <agent_type>"
    exit 1
fi

case "$AGENT_TYPE" in
    "claude")
        echo "Starting Claude Code in pane $PANE_NUM"
        tmux send-keys -t "${PANE_NUM}" "claude" Enter
        ;;
    "gemini")
        echo "Starting Gemini in pane $PANE_NUM" 
        tmux send-keys -t "${PANE_NUM}" "gemini" Enter
        ;;
    *)
        echo "Unknown agent type: $AGENT_TYPE"
        exit 1
        ;;
esac
`;

    fs.writeFileSync(path.join(scriptsDir, 'agent_manager.sh'), agentManagerScript);
    fs.chmodSync(path.join(scriptsDir, 'agent_manager.sh'), '755');
    
    this.log('✅ 基本スクリプトを作成しました', 'success');
  }

  async generateConfig() {
    this.log('設定ファイル生成中...', 'info');
    
    // config.json作成
    const configPath = path.join(__dirname, '..', 'config.json');
    const config = {
      projectDir: this.config.projectDir,
      sessionName: this.config.sessionName,
      scriptDir: this.config.agentScripts ? 'scripts/agent_tools' : null
    };
    
    fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
    
    // カスタムレイアウトの場合、pane_config.jsonを更新
    if (typeof this.config.layout === 'object') {
      const paneConfigPath = path.join(__dirname, '..', 'pane_config.json');
      const paneConfig = JSON.parse(fs.readFileSync(paneConfigPath, 'utf8'));
      
      paneConfig.layouts['custom'] = this.config.layout;
      paneConfig.defaultLayout = 'custom';
      
      fs.writeFileSync(paneConfigPath, JSON.stringify(paneConfig, null, 2));
    }
    
    this.log('✅ 設定ファイルを生成しました', 'success');
  }

  async generateClaudeConfig() {
    console.log('\n📝 Claude Code設定');
    console.log('-'.repeat(30));
    
    const generateClaude = await this.question(
      '.claude.json設定ファイルを生成しますか？ (Y/n): '
    );
    
    if (generateClaude.toLowerCase() !== 'n') {
      const claudeConfig = {
        mcpServers: {
          "agent-collaboration": {
            command: "node",
            args: [path.join(__dirname, '..', 'index.js')],
            env: {
              PROJECT_DIR: this.config.projectDir
            }
          }
        }
      };
      
      const claudeConfigPath = path.join(this.config.projectDir, '.claude.json');
      fs.writeFileSync(claudeConfigPath, JSON.stringify(claudeConfig, null, 2));
      
      this.log(`✅ .claude.json を作成しました: ${claudeConfigPath}`, 'success');
    }
  }

  async showSummary() {
    console.log('\n🎉 セットアップ完了!');
    console.log('='.repeat(50));
    console.log(`プロジェクトディレクトリ: ${this.config.projectDir}`);
    console.log(`tmuxセッション名: ${this.config.sessionName}`);
    console.log(`ペイン構成: ${typeof this.config.layout === 'string' ? this.config.layout : 'custom'}`);
    console.log(`エージェントスクリプト: ${this.config.agentScripts ? '✅' : '❌'}`);
    
    console.log('\n📋 次のステップ:');
    console.log('1. Claude Codeを再起動');
    console.log('2. tmuxセッションを作成:');
    console.log(`   tmux new-session -d -s ${this.config.sessionName}`);
    console.log('3. MCPツールをテスト:');
    console.log('   detect_panes() でペイン検出を試してください');
    
    if (!this.config.agentScripts) {
      console.log('\n⚠️ 注意: エージェント管理スクリプトが不完全です。');
      console.log('完全な機能を使用するには、適切なスクリプトを配置してください。');
    }
  }

  async run() {
    try {
      await this.welcome();
      await this.detectEnvironment();
      await this.configurePaths();
      await this.configureLayout();
      await this.checkAgentScripts();
      await this.generateConfig();
      await this.generateClaudeConfig();
      await this.showSummary();
    } catch (error) {
      this.log(`セットアップエラー: ${error.message}`, 'error');
    } finally {
      this.rl.close();
    }
  }
}

// スクリプト実行
if (require.main === module) {
  const wizard = new SetupWizard();
  wizard.run();
}

module.exports = { SetupWizard };