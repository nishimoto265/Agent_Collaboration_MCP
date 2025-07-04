/**
 * Shared tmux utility functions
 */

/**
 * Parse tmux target string into components
 * @param {string} target - Target in format "session:window.pane"
 * @returns {Object} Parsed target components
 */
function parseTarget(target) {
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

/**
 * Format command output by removing ANSI color codes
 * @param {string} stdout - Standard output
 * @param {string} stderr - Standard error
 * @returns {string} Cleaned output
 */
function formatOutput(stdout, stderr) {
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

module.exports = {
  parseTarget,
  formatOutput
};