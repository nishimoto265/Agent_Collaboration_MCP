const { exec } = require('child_process');
const { promisify } = require('util');
const execAsync = promisify(exec);
const path = require('path');
const { parseTarget, formatOutput } = require('../utils/tmuxUtils');

class PaneController {
  constructor(config = {}) {
    // Use provided config or defaults
    this.projectDir = config.projectDir || process.cwd();
    const scriptDir = config.scriptDir || 'scripts/agent_tools';
    
    // Build script path - prioritize internal scripts if available
    const mcpDir = path.dirname(path.dirname(__dirname)); // Get MCP root directory
    const internalScriptPath = path.join(mcpDir, 'scripts', 'agent_tools', 'pane_controller.sh');
    
    // Use internal script if it exists, otherwise fallback to project script
    if (require('fs').existsSync(internalScriptPath)) {
      this.scriptPath = internalScriptPath;
      console.error(`Using internal MCP pane controller: ${internalScriptPath}`);
    } else {
      this.scriptPath = path.join(this.projectDir, scriptDir, 'pane_controller.sh');
      console.error(`Using external project pane controller: ${this.scriptPath}`);
    }
  }


  async sendMessage(target, message, sendEnter = true) {
    try {
      const { paneNumber } = parseTarget(target);
      // Escape special characters in message
      const escapedMessage = message.replace(/'/g, "'\\''");
      const enterFlag = sendEnter ? '' : 'false';
      const cmd = `${this.scriptPath} send ${paneNumber} '${escapedMessage}' ${enterFlag}`.trim();
      const { stdout, stderr } = await execAsync(cmd, { cwd: this.projectDir });
      return formatOutput(stdout, stderr);
    } catch (error) {
      throw new Error(`Failed to send message: ${error.message}`);
    }
  }

  async captureScreen(target, lines = '') {
    try {
      const { paneNumber } = parseTarget(target);
      // Build command - if lines specified, pass as argument to capture command
      let cmd;
      if (lines && lines > 0) {
        cmd = `${this.scriptPath} capture ${paneNumber} -${lines}`;
      } else {
        cmd = `${this.scriptPath} capture ${paneNumber}`;
      }
      
      const { stdout, stderr } = await execAsync(cmd, { 
        cwd: this.projectDir,
        maxBuffer: 10 * 1024 * 1024 // 10MB buffer for large captures
      });
      
      // Return raw stdout for screen captures
      if (stderr && !stderr.includes('[INFO]') && !stderr.includes('[SUCCESS]')) {
        return `Error: ${stderr}`;
      }
      return stdout;
    } catch (error) {
      throw new Error(`Failed to capture screen: ${error.message}`);
    }
  }


}

module.exports = { PaneController };