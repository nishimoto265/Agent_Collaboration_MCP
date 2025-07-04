const { exec } = require('child_process');
const { promisify } = require('util');
const execAsync = promisify(exec);
const path = require('path');
const fs = require('fs');

class AgentManager {
  constructor(config = {}) {
    // Use provided config or defaults
    this.projectDir = config.projectDir || process.cwd();
    const scriptDir = config.scriptDir || 'scripts/agent_tools';
    
    // Build script paths - prioritize internal scripts if available
    const mcpDir = path.dirname(path.dirname(__dirname)); // Get MCP root directory
    const internalScriptPath = path.join(mcpDir, 'scripts', 'agent_tools', 'agent_manager.sh');
    const internalPaneControllerPath = path.join(mcpDir, 'scripts', 'agent_tools', 'pane_controller.sh');
    const internalAuthHelperPath = path.join(mcpDir, 'scripts', 'agent_tools', 'auth_helper.sh');
    
    // Use internal scripts if they exist, otherwise fallback to project scripts
    if (fs.existsSync(internalScriptPath)) {
      this.scriptPath = internalScriptPath;
      this.paneControllerPath = internalPaneControllerPath;
      this.authHelperPath = internalAuthHelperPath;
      console.error(`Using internal MCP scripts: ${internalScriptPath}`);
    } else {
      this.scriptPath = path.join(this.projectDir, scriptDir, 'agent_manager.sh');
      this.paneControllerPath = path.join(this.projectDir, scriptDir, 'pane_controller.sh');
      this.authHelperPath = path.join(this.projectDir, scriptDir, 'auth_helper.sh');
      console.error(`Using external project scripts: ${this.scriptPath}`);
    }
  }

  // tmux target文字列を解析
  parseTarget(target) {
    const match = target.match(/^([^:]+):([^.]+)\.(.+)$/);
    if (!match) {
      throw new Error(`Invalid tmux target format: "${target}". Expected format: "session:window.pane" (e.g., "multiagent:0.5")`);
    }
    
    const [_, sessionName, windowNumber, paneNumber] = match;
    return {
      sessionName,
      windowNumber,
      paneNumber,
      fullTarget: target
    };
  }


  async startAgent(target, agentType = 'claude', additionalArgs = '') {
    try {
      const { paneNumber } = this.parseTarget(target);
      const cmd = `${this.scriptPath} start ${paneNumber} ${agentType} ${additionalArgs}`.trim();
      const { stdout, stderr } = await execAsync(cmd, { 
        cwd: this.projectDir,
        timeout: 350000 // 350秒（約6分）- agent_manager.shの300秒待機 + 余裕
      });
      return this.formatOutput(stdout, stderr);
    } catch (error) {
      throw new Error(`Failed to start agent: ${error.message}`);
    }
  }



  // 🔍 改善されたgetStatus - tmux target対応
  async getStatus(target = '') {
    try {
      let result = '';
      
      if (target && !target.includes('*')) {
        // 特定ペインの詳細状態
        const { sessionName, windowNumber, paneNumber, fullTarget } = this.parseTarget(target);
        
        // ペイン画面内容をキャプチャ（pane_controller.sh経由）
        let screenContent = '';
        try {
          const { stdout } = await execAsync(`${this.paneControllerPath} capture ${paneNumber} -3000`, { 
            cwd: this.projectDir,
            timeout: 5000
          });
          screenContent = stdout;
        } catch (captureError) {
          screenContent = `キャプチャエラー: ${captureError.message}`;
        }

        // auth_helper.shを使って状態を取得
        console.error(`[DEBUG] Getting state for pane ${paneNumber}`);
        let analysis;
        try {
          const { stdout: stateResult } = await execAsync(`${this.authHelperPath} state ${paneNumber}`, {
            cwd: this.projectDir,
            timeout: 3000
          });
          
          // 結果をパース: "state|agent|details"
          const [state, agent, details] = stateResult.trim().split('|');
          analysis = { state, agent, details };
        } catch (stateError) {
          analysis = { state: 'unknown', agent: 'none', details: `状態取得エラー: ${stateError.message}` };
        }
        console.error(`[DEBUG] Analysis result for ${fullTarget}:`, analysis);
        
        result = `🔍 Target ${fullTarget} の詳細状態:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 状態: ${this.getStateIcon(analysis.state)} ${analysis.state}
🤖 エージェント: ${analysis.agent}
📝 詳細: ${analysis.details}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📺 画面内容 (最新20行):
${screenContent.split('\n').slice(-20).join('\n')}`;

      } else {
        // セッション内全ペイン状態一覧
        let sessionName = 'multiagent'; // デフォルト
        if (target && target.includes('*')) {
          sessionName = target.split(':')[0];
        }
        
        result = `🌐 セッション "${sessionName}" 全ペイン状態一覧:\n`;
        result += '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n';
        
        const stateSummary = { running_claude: 0, running_gemini: 0, auth_claude: 0, auth_gemini: 0, executing_claude: 0, stopped: 0 };
        
        // ペイン一覧を取得（共通ライブラリの関数を使用）
        try {
          // get_all_panes関数を呼び出し（MCPディレクトリを考慮）
          const mcpDir = path.dirname(path.dirname(__dirname)); // MCP root directory
          const utilsPath = fs.existsSync(path.join(mcpDir, 'scripts', 'common', 'utils.sh')) 
            ? path.join(mcpDir, 'scripts', 'common', 'utils.sh')
            : path.join(this.projectDir, 'scripts', 'common', 'utils.sh');
          const { stdout: paneList } = await execAsync(`bash -c 'source "${utilsPath}" && setup_directories "." >&2 && get_all_panes "${sessionName}"'`, {
            cwd: this.projectDir,
            timeout: 5000
          });
          
          const paneNumbers = paneList.trim().split('\n').filter(p => p.trim());
          
          for (const paneNum of paneNumbers) {
            const currentTarget = `${sessionName}:0.${paneNum}`;
            
            try {
              // auth_helper.shを使って状態を取得
              const { stdout: stateResult } = await execAsync(`${this.authHelperPath} state ${paneNum}`, {
                cwd: this.projectDir,
                timeout: 3000
              });
              
              // 結果をパース: "state|agent|details"
              const [state, agent, details] = stateResult.trim().split('|');
              const analysis = { state, agent, details };
              stateSummary[analysis.state] = (stateSummary[analysis.state] || 0) + 1;
              
              // ペイン名を取得（共通ライブラリの関数を使用）
              let paneName = '';
              try {
                const { stdout: nameResult } = await execAsync(`bash -c 'source "${utilsPath}" && get_pane_name ${paneNum}'`, {
                  cwd: this.projectDir,
                  timeout: 1000
                });
                paneName = nameResult.trim();
              } catch (nameErr) {
                // エラーの場合は空文字列のまま
              }
              
              const targetDisplay = paneName ? `${currentTarget} (${paneName})` : currentTarget;
              
              result += `${this.getStateIcon(analysis.state)} ${targetDisplay.padEnd(40)} | ${analysis.agent.padEnd(8)} | ${analysis.state.padEnd(12)}\n`;
              
            } catch (error) {
              stateSummary.stopped++;
              result += `❌ ${currentTarget.padEnd(40)} | error    | capture_fail\n`;
            }
          }
        } catch (sessionError) {
          return `❌ エラー: セッション "${sessionName}" が見つかりません: ${sessionError.message}`;
        }
        
        result += '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n';
        result += '📊 状態サマリー:\n';
        result += `   ✅ Claude起動完了: ${stateSummary.running_claude}個\n`;
        result += `   💎 Gemini起動完了: ${stateSummary.running_gemini}個\n`;
        result += `   🔐 Claude認証中: ${stateSummary.auth_claude}個\n`;
        result += `   🔑 Gemini認証中: ${stateSummary.auth_gemini}個\n`;
        result += `   ⚡ Claude実行中: ${stateSummary.executing_claude}個\n`;
        result += `   ⚫ 停止中: ${stateSummary.stopped}個\n`;
      }
      
      return result;
      
    } catch (error) {
      throw new Error(`Failed to get status: ${error.message}`);
    }
  }

  // ペイン番号→名前変換
  async getPaneName(sessionName, windowNumber, paneNumber) {
    try {
      // pane_controller.shのstatus機能を使用してペイン名を取得
      // 現在はペインタイトルを使用していないため、空文字列を返す
      // 将来的にペイン名機能を追加する場合はここで実装
      return '';
    } catch (error) {
      // エラーの場合は空文字列を返す
      return '';
    }
  }

  // 状態アイコン取得
  getStateIcon(state) {
    const icons = {
      'running_claude': '✅',
      'running_gemini': '💎',
      'auth_claude': '🔐', 
      'auth_gemini': '🔑',
      'executing_claude': '⚡',
      'stopped': '⚫'
    };
    return icons[state] || '❓';
  }


  formatOutput(stdout, stderr) {
    // Remove ANSI color codes for cleaner output in Claude
    const cleanOutput = (str) => str.replace(/\x1b\[[0-9;]*m/g, '');
    
    let output = '';
    if (stdout) {
      output += cleanOutput(stdout);
    }
    if (stderr && !stderr.includes('[INFO]') && !stderr.includes('[SUCCESS]')) {
      output += '\n' + cleanOutput(stderr);
    }
    return output.trim();
  }
}

module.exports = { AgentManager };