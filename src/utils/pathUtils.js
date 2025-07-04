/**
 * Shared path utility functions
 */

const path = require('path');
const fs = require('fs');

/**
 * Resolve script path, prioritizing internal MCP scripts over external project scripts
 * @param {string} projectDir - Project directory
 * @param {string} scriptDir - Script directory relative to project
 * @param {string} scriptName - Name of the script file
 * @returns {Object} Script path and type (internal/external)
 */
function resolveScriptPath(projectDir, scriptDir, scriptName) {
  // Get MCP root directory
  const mcpDir = path.dirname(path.dirname(path.dirname(__dirname))); 
  const internalScriptPath = path.join(mcpDir, 'scripts', path.basename(scriptDir), scriptName);
  
  // Use internal script if it exists, otherwise fallback to project script
  if (fs.existsSync(internalScriptPath)) {
    return {
      path: internalScriptPath,
      type: 'internal',
      message: `Using internal MCP script: ${internalScriptPath}`
    };
  } else {
    const externalPath = path.join(projectDir, scriptDir, scriptName);
    return {
      path: externalPath,
      type: 'external',
      message: `Using external project script: ${externalPath}`
    };
  }
}

module.exports = {
  resolveScriptPath
};