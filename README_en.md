# Agent Collaboration MCP Server

[日本語版はこちら](README.md)

A **completely self-contained** MCP server that enables AI agents to collaborate with each other. By giving this tool to agents like Claude Code, they can start and control other agents, allowing teams of agents to work together on complex tasks.

## ✨ Features

- **Simple Architecture**: Intuitive operation using direct pane numbers
- **Multi-Agent Support**: Control Claude Code and Gemini simultaneously
- **Flexible Session Management**: Support for parallel work on multiple projects
- **Advanced State Management**: Real-time monitoring of agent execution states

## 🎯 Agent-to-Agent Collaboration

> **⚠️ About Automatic Authentication**  
> If you want to automate authentication for new agents, [Playwright MCP](https://github.com/microsoft/playwright-mcp) is required. Without Playwright MCP, authentication must be done manually. See [Automatic Authentication Delegation](#automatic-authentication-delegation-optional) for details.

The main purpose of this MCP server is to **enable agents to manage other agents**. For example:

- A **boss agent** can divide tasks and assign them to multiple **worker agents**
- Each agent works in their specialized area (Claude Code for coding, Gemini for image generation)
- Agents send messages to each other and share progress
- One agent can review and integrate the work results of other agents
- **Automatic Authentication Delegation**: When new agents require authentication, existing authenticated agents automatically handle the authentication process

## 🛠️ Available Tools

Six tools that agents can use:

### 1. `start_agent` - Start an Agent
```javascript
start_agent(target="multiagent:0.2", agentType="claude")
start_agent(target="multiagent:0.3", agentType="gemini")
```
Starts an AI agent in the specified tmux target.
- **target**: tmux target format ("session:window.pane", e.g., "multiagent:0.5")
- **agentType**: claude (general code development) or gemini (image generation tasks)
- **additionalArgs**: Additional arguments (optional)

### 2. `get_agent_status` - Check Status
```javascript
get_agent_status()                          // Check all agents
get_agent_status(target="multiagent:0.2")  // Check specific pane details
get_agent_status(target="multiagent:*")    // Check all panes in session
```

#### Available Status Types

| Status | Icon | Description |
|--------|------|-------------|
| `running_claude` | ✅ | Claude Code is running and ready for input |
| `running_gemini` | 💎 | Gemini is running and ready for input |
| `auth_claude` | 🔐 | Claude Code is in authentication process |
| `auth_gemini` | 🔑 | Gemini is in authentication process |
| `executing_claude` | ⚡ | Claude is executing (showing "ESC to interrupt") |
| `stopped` | ⚫ | Agent is stopped or in shell state |

### 3. `send_message` - Send Messages
```javascript
send_message(target="multiagent:0.2", message="Hello")
send_message(target="multiagent:0.3", message="C-c", sendEnter=false) // Send Ctrl+C
```
Send messages or control characters to specified panes. Includes advanced message sending features.

### 4. `capture_screen` - Capture Screen
```javascript
capture_screen(target="multiagent:0.2")        // Full history capture
capture_screen(target="multiagent:0.3", lines=50) // Last 50 lines
```
Capture screen content from panes.

### 5. `parallel_implement` - Parallel Implementation
```javascript
parallel_implement(prompt="Implement user authentication feature")
parallel_implement(prompt="Execute refactoring", workerCount=5, complexity="complex")
```
Multiple worker agents implement the same task in parallel, and a boss agent selects and integrates the best outcomes.

**Important**: This feature **must be run within a Git repository**. Each worker operates in its own Git worktree.

- **prompt**: Implementation instructions (required)
- **workerCount**: Number of workers (default: 3)
- **complexity**: Task complexity (simple, medium, complex)
- **agentType**: Agent to use (claude, gemini)
- **autoMerge**: Auto-merge after completion (default: false)

### 6. `get_parallel_status` - Check Parallel Implementation Status
```javascript
get_parallel_status()                    // List all sessions
get_parallel_status(sessionId="parallel_20240105_123456")  // Specific session details
```
Check the progress of parallel implementation sessions. Get work status, completion rate, error information, and more for each worker.

## 📦 Setup

### 1. Installation

**Via npm (Recommended)**:
```bash
npm install -g agent-collaboration-mcp@latest
```

**From GitHub**:
```bash
git clone https://github.com/nishimoto265/Agent_Collaboration_MCP.git
cd Agent_Collaboration_MCP
npm install
```

### 2. Add to Claude Code (Recommended)

**Simple method (using CLI)**:
```bash
claude mcp add agent-collaboration npx agent-collaboration-mcp
```

**If you want to use automatic authentication, also add Playwright MCP**:
```bash
claude mcp add playwright npx @playwright/mcp@latest
```

**Or, using JSON configuration**:

1. Create `.mcp.json` in your project root:
```json
{
  "mcpServers": {
    "agent-collaboration": {
      "command": "npx",
      "args": ["agent-collaboration-mcp"]
    }
  }
}
```

2. For local installation:
```json
{
  "mcpServers": {
    "agent-collaboration": {
      "command": "node",
      "args": ["/absolute/path/to/Agent_Collaboration_MCP/index.js"]
    }
  }
}
```

### 3. Prepare tmux Sessions

```bash
# Create default session (multiagent)
tmux new-session -d -s multiagent

# For multiple projects
tmux new-session -d -s project1
tmux new-session -d -s project2
```

## 💡 Usage Examples

### Basic Usage
```javascript
// 1. Start agents
start_agent(target="multiagent:0.2", agentType="claude")
start_agent(target="multiagent:0.3", agentType="claude")

// 2. Check status
get_agent_status()

// 3. Send tasks
send_message(target="multiagent:0.2", message="Please review the README")
send_message(target="multiagent:0.3", message="Run the tests")

// 4. Check results
capture_screen(target="multiagent:0.3")
```

### Working with Multiple Sessions
```javascript
// Work on Project 1
start_agent(target="project1:0.0", agentType="claude")
send_message(target="project1:0.0", message="Implement the backend API")

// Parallel work on Project 2
start_agent(target="project2:0.0", agentType="gemini")
send_message(target="project2:0.0", message="Create UI designs")
```

### Automatic Authentication Delegation (Optional)

If you want to automate authentication for new agents, you can use [Playwright MCP](https://github.com/microsoft/playwright-mcp) in conjunction with this tool. This allows existing authenticated agents to automatically handle authentication for new agents.

```javascript
// How it works when Playwright MCP is installed
start_agent(target="multiagent:0.5", agentType="claude")
// When authentication is required, the following happens automatically:
// 1. Detect existing authenticated agents
// 2. Extract authentication URL from new agent
// 3. Use Playwright MCP to automate browser authentication
// 4. Automatically send authentication code to new agent
```

### Multi-Agent Collaboration Example
```javascript
// Boss Agent (task management)
start_agent(target="multiagent:0.0", agentType="claude")

// Worker Agent team
start_agent(target="multiagent:0.1", agentType="claude")  // Code development
start_agent(target="multiagent:0.2", agentType="gemini") // Image generation
start_agent(target="multiagent:0.3", agentType="claude") // Testing

// Boss sends task division instructions
send_message(target="multiagent:0.0", message="Please check project progress and divide tasks among teams")

// Monitor each worker's status
get_agent_status()
```

### Emergency Stop & Control
```javascript
// Stop process
send_message(target="multiagent:0.2", message="C-c", sendEnter=false)

// Clear screen
send_message(target="multiagent:0.2", message="C-l", sendEnter=false)
```

## 🔧 Prerequisites

### Required
- **Node.js 18+**
- **tmux**
- **tmux session**: `tmux new-session -d -s multiagent`

### Optional (for authentication automation)
- **[Playwright MCP](https://github.com/microsoft/playwright-mcp)**: Required if you want to automate agent authentication

## 🚀 Advanced Features

### Flexible Target Specification
- **Session Specification**: Work in parallel on different projects
- **Wildcards**: Target all panes with `multiagent:*`
- **Intuitive Numbering**: Simple specification with `0`, `1`, `2`...

### Precise State Detection
- **Real-time Monitoring**: Instantly determine agent execution states
- **Multiple State Recognition**: Accurately distinguish between running, authenticating, stopped, etc.
- **Icon Display**: Visually clear state representation

## 🚨 Troubleshooting

### tmux session doesn't exist
```bash
# Create multiagent session
tmux new-session -d -s multiagent
```

### Agent won't start
- Check status with `get_agent_status()`
- Check error messages with `capture_screen()`
- Authentication delegation system often resolves issues automatically

### Messages not being sent
- Check if agent is running with `get_agent_status()`
- Verify tmux session exists
- Check target format is correct ("session:window.pane")

## 📄 Script Customization

Agent Collaboration MCP uses scripts in `scripts/agent_tools/`. If you have custom agent startup methods or message sending methods, customize these scripts:

- `agent_manager.sh`: Define agent startup commands
- `pane_controller.sh`: Define message sending methods

## 🤝 Contributing

We welcome contributions to this project. Please report bugs and suggest features.

## 📄 License

MIT License