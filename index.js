#!/usr/bin/env node

// Ensure process doesn't exit immediately
process.stdin.resume();

const { McpServer } = require('@modelcontextprotocol/sdk/server/mcp.js');
const { StdioServerTransport } = require('@modelcontextprotocol/sdk/server/stdio.js');
const { z } = require('zod');
const { AgentManager } = require('./src/tools/agentManager.js');
const { PaneController } = require('./src/tools/paneController.js');
const ParallelImplementation = require('./src/tools/parallelImplementation');
const fs = require('fs');
const path = require('path');

// Load configuration from environment variables and config file
function loadConfig() {
  const defaultConfig = {
    projectDir: process.cwd(),
    sessionName: 'multiagent',
    scriptDir: 'scripts/agent_tools'
  };

  // Try to load config.json if it exists
  const configPath = path.join(__dirname, 'config.json');
  let fileConfig = {};
  if (fs.existsSync(configPath)) {
    try {
      fileConfig = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    } catch (error) {
      console.error('Warning: Failed to parse config.json:', error.message);
    }
  }

  // Environment variables take precedence
  const envConfig = {
    projectDir: process.env.AGENT_COLLABORATION_PROJECT_DIR,
    sessionName: process.env.AGENT_COLLABORATION_SESSION_NAME,
    scriptDir: process.env.AGENT_COLLABORATION_SCRIPT_DIR
  };

  // Merge configurations: env > file > default
  return {
    ...defaultConfig,
    ...fileConfig,
    ...Object.fromEntries(Object.entries(envConfig).filter(([_, v]) => v != null))
  };
}

const config = loadConfig();

// Initialize tool instances with configuration
const agentManager = new AgentManager(config);
const paneController = new PaneController(config);
const parallelImpl = new ParallelImplementation(config.projectDir);

// Create MCP server with proper configuration
const server = new McpServer({
  name: 'agent-collaboration',
  version: '3.3.2',
});

// 🚀 1. Start Agent - エージェント起動（必須）
server.registerTool('start_agent', {
  title: 'Start Agent',
  description: 'Start an agent in a specific tmux target',
  inputSchema: {
    target: z.string().describe('tmux target in format "session:window.pane" (e.g., "multiagent:0.5", "dev:1.3")'),
    agentType: z.enum(['claude', 'gemini']).default('claude').describe('Type of agent to start'),
    additionalArgs: z.string().optional().describe('Additional arguments for the agent')
  }
}, async ({ target, agentType, additionalArgs }) => {
  try {
    const result = await agentManager.startAgent(target, agentType, additionalArgs);
    return { content: [{ type: 'text', text: result }] };
  } catch (error) {
    return { content: [{ type: 'text', text: `Error: ${error.message}` }], isError: true };
  }
});

// 📊 2. Get Agent Status - 状態確認（必須）
server.registerTool('get_agent_status', {
  title: 'Get Agent Status',
  description: 'Get status of agents',
  inputSchema: {
    target: z.string().optional().describe('tmux target in format "session:window.pane" (e.g., "multiagent:0.5") or "session:*" for all panes in session')
  }
}, async ({ target }) => {
  try {
    const result = await agentManager.getStatus(target);
    return { content: [{ type: 'text', text: result }] };
  } catch (error) {
    return { content: [{ type: 'text', text: `Error: ${error.message}` }], isError: true };
  }
});


// 💬 4. Send Message - 万能コミュニケーション（必須）
// 制御文字対応: C-c (Ctrl+C), C-l (Ctrl+L) など
server.registerTool('send_message', {
  title: 'Send Message',
  description: 'Send a message to a tmux target. Control characters supported: C-c (stop), C-l (clear), etc.',
  inputSchema: {
    target: z.string().describe('tmux target in format "session:window.pane" (e.g., "multiagent:0.5")'),
    message: z.string().describe('Message to send (use C-c for Ctrl+C, C-l for Ctrl+L, etc.)'),
    sendEnter: z.boolean().default(true).describe('Whether to send Enter after the message')
  }
}, async ({ target, message, sendEnter }) => {
  try {
    const result = await paneController.sendMessage(target, message, sendEnter);
    return { content: [{ type: 'text', text: result }] };
  } catch (error) {
    return { content: [{ type: 'text', text: `Error: ${error.message}` }], isError: true };
  }
});

// 📺 5. Capture Screen - 画面取得（必須）
server.registerTool('capture_screen', {
  title: 'Capture Screen',
  description: 'Capture screen content from a tmux target',
  inputSchema: {
    target: z.string().describe('tmux target in format "session:window.pane" (e.g., "multiagent:0.5")'),
    lines: z.number().optional().describe('Number of lines to capture (default: all history)')
  }
}, async ({ target, lines }) => {
  try {
    const result = await paneController.captureScreen(target, lines);
    return { content: [{ type: 'text', text: result }] };
  } catch (error) {
    return { content: [{ type: 'text', text: `Error: ${error.message}` }], isError: true };
  }
});

// 🚀 6. Parallel Implementation - 並列実装
server.registerTool('parallel_implement', {
  title: 'Start Parallel Implementation',
  description: 'Start parallel implementation with multiple workers',
  inputSchema: {
    prompt: z.string().describe('Implementation instructions'),
    workerCount: z.number().default(3).describe('Number of workers (default: 3)'),
    complexity: z.enum(['simple', 'medium', 'complex']).default('medium').describe('Task complexity'),
    autoMerge: z.boolean().default(false).describe('Auto-merge after completion'),
    agentType: z.enum(['claude', 'gemini']).default('claude').describe('Agent type to use')
  }
}, async ({ prompt, workerCount, complexity, autoMerge, agentType }) => {
  try {
    const result = await parallelImpl.startParallelImplementation(prompt, workerCount, complexity, autoMerge, true, agentType);
    if (result.success) {
      return { 
        content: [{ 
          type: 'text', 
          text: `${result.message}\n\nセッションID: ${result.sessionId}\nワーカー数: ${result.details.workerCount}\n複雑度: ${result.details.complexity}\n\n各Workerにプロンプトが配布されました。進捗は 'get_parallel_status' で確認できます。`
        }] 
      };
    } else {
      return { content: [{ type: 'text', text: `Error: ${result.error}` }], isError: true };
    }
  } catch (error) {
    return { content: [{ type: 'text', text: `Error: ${error.message}` }], isError: true };
  }
});

// 📊 7. Get Parallel Status - 並列実装状態確認
server.registerTool('get_parallel_status', {
  title: 'Get Parallel Implementation Status',
  description: 'Get status of parallel implementation sessions',
  inputSchema: {
    sessionId: z.string().optional().describe('Session ID (omit to list all sessions)')
  }
}, async ({ sessionId }) => {
  try {
    const result = await parallelImpl.getParallelStatus(sessionId);
    if (!result.success) {
      return { content: [{ type: 'text', text: `Error: ${result.error}` }], isError: true };
    }
    
    if (sessionId && result.sessionInfo) {
      const info = result.sessionInfo;
      return {
        content: [{
          type: 'text',
          text: `セッション: ${info.session_id}\n` +
                `状態: ${info.status}\n` +
                `完了率: ${info.completion_rate || 0}%\n` +
                `ワーカー数: ${info.worker_count}\n` +
                `複雑度: ${info.complexity}\n` +
                `Boss必要: ${info.needs_boss ? 'はい' : 'いいえ'}\n` +
                `タイムスタンプ: ${info.timestamp}`
        }]
      };
    } else {
      return {
        content: [{
          type: 'text',
          text: result.sessions.length > 0 
            ? `並列実装セッション一覧:\n\n${result.sessions.join('\n')}`
            : "アクティブなセッションはありません"
        }]
      };
    }
  } catch (error) {
    return { content: [{ type: 'text', text: `Error: ${error.message}` }], isError: true };
  }
});

// Start the server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error) => {
  console.error('Server error:', error);
  process.exit(1);
});