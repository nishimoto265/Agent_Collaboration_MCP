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
    
    // Use internal scripts if they exist, otherwise fallback to project scripts
    if (fs.existsSync(internalScriptPath)) {
      this.scriptPath = internalScriptPath;
      this.paneControllerPath = internalPaneControllerPath;
      console.error(`Using internal MCP scripts: ${internalScriptPath}`);
    } else {
      this.scriptPath = path.join(this.projectDir, scriptDir, 'agent_manager.sh');
      this.paneControllerPath = path.join(this.projectDir, scriptDir, 'pane_controller.sh');
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

  // 画面内容からエージェント状態を判定（auth_helper.shのロジックを流用）
  analyzeAgentState(screenContent) {
    console.error('[DEBUG] ===== analyzeAgentState CALLED =====');
    if (!screenContent || screenContent.trim() === '') {
      console.error('[DEBUG] Empty screen content, returning stopped');
      return { state: 'stopped', agent: 'none', details: '停止中' };
    }

    // 画面内容を正規化（改行をスペースに置換して連続スペースを単一に）
    const normalizedContent = screenContent.replace(/\n/g, ' ').replace(/\s+/g, ' ');
    const content = screenContent.toLowerCase();
    const normalizedLower = normalizedContent.toLowerCase();
    
    console.error('[DEBUG] Screen content (first 200 chars):', screenContent.slice(0, 200));
    console.error('[DEBUG] Screen content (last 200 chars):', screenContent.slice(-200));

    // 🔍 優先度0: 最優先 - 画面の最後の有効な行に「$」が含まれていれば停止中
    // 空でない最後の行を取得
    const lines = screenContent.split('\n');
    let lastValidLine = '';
    for (let i = lines.length - 1; i >= 0; i--) {
      if (lines[i].trim()) {
        lastValidLine = lines[i].toLowerCase();
        break;
      }
    }
    
    console.error('[DEBUG] Last valid line:', lastValidLine);
    console.error('[DEBUG] Last valid line includes $:', lastValidLine.includes('$'));
    
    // 最後の有効な行がシェルプロンプトで終わっている場合のみ停止中と判定
    if (lastValidLine.match(/\$\s*$/)) {
      console.error('[DEBUG] $ at end of last line detected! Returning stopped state');
      return { state: 'stopped', agent: 'none', details: '停止中（シェルプロンプト）' };
    }

    // 🔍 優先度1: Claude実行中（ESC to interrupt表示）
    if (content.includes('esc to interrupt') || content.includes('escape to interrupt')) {
      return { state: 'executing_claude', agent: 'claude', details: 'Claude実行中' };
    }

    // 🔍 優先度2: ログアウト済み（停止状態）
    if (normalizedLower.includes('successfully logged out') ||
        (content.includes('$') && normalizedLower.includes('logged out')) ||
        (content.includes('Successfully logged out') && content.includes('$'))) {
      return { state: 'stopped', agent: 'none', details: '停止中（ログアウト済み）' };
    }
    
    // 🔍 優先度2.5: AUTH-HELPERプロンプト（停止状態）
    if (content.includes('(auth-helper)') || content.includes('(AUTH-HELPER)')) {
      return { state: 'stopped', agent: 'none', details: '停止中（AUTH-HELPER）' };
    }

    // 🔍 優先度3: Claude起動完了（複合条件で判定）
    // /help for helpとBypassing Permissionsが同時に表示されている場合（ターミナル設定画面があっても）
    if ((content.includes('/help for help') || normalizedLower.includes('/help for help')) &&
        ((content.includes('bypassing') && content.includes('permissions')) || 
         (content.includes('Bypassing') && content.includes('Permissions')))) {
      console.error('[DEBUG] Claude起動完了と判定: /help for help + Bypassing Permissions');
      return { state: 'running_claude', agent: 'claude', details: 'Claude起動完了' };
    }

    // /help for helpパターン（認証URLが無い場合は起動完了）
    if ((content.includes('/help for help') && content.includes('current setup')) ||
        (content.includes('/help for help') && content.includes('for your current setup')) ||
        (normalizedLower.includes('/help for help') && normalizedLower.includes('current setup'))) {
      // 認証関連のURLやプロンプトが表示されていない場合
      if (!content.includes('claude.ai/oauth/authorize') && 
          !content.includes('paste code here') &&
          !content.includes('oauth error') &&
          !content.includes('browser didn\'t open')) {
        return { state: 'running_claude', agent: 'claude', details: 'Claude起動完了' };
      }
    }
    
    // その他のClaude起動完了パターン
    if ((content.includes('how can i help') || content.includes('try "edit') || content.includes('tip:')) && 
        !content.includes('preview') && 
        !content.includes('console.log') && 
        !content.includes('press enter to continue') && 
        !content.includes('esc to interrupt') &&
        !content.includes('(auth-helper)') && !content.includes('(AUTH-HELPER)')) {
      return { state: 'running_claude', agent: 'claude', details: 'Claude起動完了' };
    }

    // Bypassing Permissionsパターン（単独で表示されている場合のみ）
    if (((content.includes('bypassing') && content.includes('permissions')) ||
         (content.includes('Bypassing') && content.includes('Permissions'))) &&
        content.includes('>') &&
        !content.includes('paste code here') &&
        !content.includes('esc to interrupt')) {
      return { state: 'running_claude', agent: 'claude', details: 'Claude起動完了' };
    }

    // 🔍 優先度4: Claude認証中
    if (content.includes('select login method') || 
        content.includes('claude account with subscription') ||
        content.includes('anthropic console account') ||
        content.includes('paste code here if prompted') ||
        content.includes('browser didn\'t open') ||
        content.includes('use the url below') ||
        content.includes('claude.ai/oauth/authorize') ||
        content.includes('press enter to continue') ||
        content.includes('press enter to retry') ||
        content.includes('security notes') ||
        content.includes('login successful') ||
        content.includes('logged in as') ||
        content.includes('oauth error') ||
        content.includes('paste code here') ||
        (content.includes('dangerous') && content.includes('yes, i accept')) ||
        (content.includes('use claude code\'s terminal setup') && !content.includes('/help for help')) ||
        (content.includes('choose the text style') && content.includes('preview')) ||
        (content.includes('preview') && (content.includes('dark mode') || content.includes('light mode')))) {
      return { state: 'auth_claude', agent: 'claude', details: 'Claude認証中' };
    }

    // 🔍 優先度5: Gemini認証中
    if (content.includes('waiting for auth') ||
        content.includes('login with google') || 
        content.includes('vertex ai') ||
        content.includes('gemini api key')) {
      return { state: 'auth_gemini', agent: 'gemini', details: 'Gemini認証中' };
    }

    // 🔍 優先度6: Gemini起動完了（auth_helper.shのcheck_gemini_startupロジック）
    if ((content.includes('type your message') || normalizedLower.includes('type your message')) && 
        !content.includes('waiting for auth')) {
      return { state: 'running_gemini', agent: 'gemini', details: 'Gemini起動完了' };
    }
    
    // 改行を考慮したGemini検出（gemini-とバージョン番号が分離されている場合）
    if (content.includes('gemini-2.') || content.includes('gemini-1.') ||
        (content.includes('gemini-') && (content.includes('2.5-pro') || content.includes('2.0-pro') || content.includes('1.5-pro')))) {
      return { state: 'running_gemini', agent: 'gemini', details: 'Gemini起動完了' };
    }
    
    if (content.includes('/help') && content.includes('information') && !content.includes('waiting for auth')) {
      return { state: 'running_gemini', agent: 'gemini', details: 'Gemini起動完了' };
    }

    // 🔍 優先度7: 停止中（エージェントなし）
    // Bashプロンプトのみの場合
    if ((content.match(/.*[$#]\s*$/) || content.includes('bash') || content.includes('sh-')) &&
        !content.includes('claude') && 
        !content.includes('gemini')) {
      return { state: 'stopped', agent: 'none', details: '停止中' };
    }

    // その他（不明な状態）
    return { state: 'stopped', agent: 'none', details: '停止中' };
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
        
        // ペイン画面内容をキャプチャ
        let screenContent = '';
        try {
          const { stdout } = await execAsync(`tmux capture-pane -t ${fullTarget} -p -S -3000`, { 
            cwd: this.projectDir,
            timeout: 5000
          });
          screenContent = stdout;
        } catch (captureError) {
          screenContent = `キャプチャエラー: ${captureError.message}`;
        }

        // 状態分析
        console.error(`[DEBUG] Analyzing pane ${fullTarget}, content length: ${screenContent.length}`);
        const analysis = this.analyzeAgentState(screenContent);
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
        
        // tmuxセッションのペイン一覧を取得
        try {
          const { stdout: paneList } = await execAsync(`tmux list-panes -t ${sessionName} -F "#{pane_index}"`, {
            cwd: this.projectDir,
            timeout: 5000
          });
          
          const paneNumbers = paneList.trim().split('\n').filter(p => p.trim());
          
          for (const paneNum of paneNumbers) {
            const currentTarget = `${sessionName}:0.${paneNum}`;
            
            try {
              const { stdout } = await execAsync(`tmux capture-pane -t ${currentTarget} -p -S -3000`, { 
                cwd: this.projectDir,
                timeout: 3000
              });
              
              const analysis = this.analyzeAgentState(stdout);
              stateSummary[analysis.state]++;
              
              // 空でない最後の行を取得
              const lines = stdout.split('\n');
              let lastLine = '(empty)';
              for (let i = lines.length - 1; i >= 0; i--) {
                if (lines[i].trim()) {
                  lastLine = lines[i].slice(0, 50);
                  break;
                }
              }
              
              // ペイン名を取得（tmuxペインタイトルから）
              const [_, windowPane] = currentTarget.split(':');
              const [windowNum, paneNum] = windowPane.split('.');
              const paneName = await this.getPaneName(sessionName, windowNum, paneNum);
              const targetDisplay = paneName ? `${currentTarget} (${paneName})` : currentTarget;
              
              result += `${this.getStateIcon(analysis.state)} ${targetDisplay.padEnd(30)} | ${analysis.agent.padEnd(8)} | ${analysis.state.padEnd(12)} | ${lastLine}\n`;
              
            } catch (error) {
              stateSummary.stopped++;
              result += `❌ ${currentTarget.padEnd(30)} | error    | capture_fail | キャプチャエラー\n`;
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

  // ペイン番号→名前変換（tmuxペインタイトルから取得）
  async getPaneName(sessionName, windowNumber, paneNumber) {
    try {
      // tmuxのペインタイトルを取得
      const { stdout } = await execAsync(
        `tmux display-message -t ${sessionName}:${windowNumber}.${paneNumber} -p '#{pane_title}'`,
        { timeout: 1000 }
      );
      
      const title = stdout.trim();
      // デフォルトのシェル名（bash, zshなど）の場合は空文字列を返す
      if (title === 'bash' || title === 'zsh' || title === 'sh' || title === '') {
        return '';
      }
      
      return title;
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