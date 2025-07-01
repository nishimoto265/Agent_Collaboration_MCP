# Agent Collaboration MCP Server (Self-Contained Edition)

[日本語版はこちら](README.md)

A **completely self-contained** MCP server that enables AI agents to collaborate with each other. By giving this tool to agents like Claude Code, they can start and control other agents, allowing teams of agents to work together on complex tasks.

## ✨ New Features: Complete Self-Containment

Features of this integrated version:
- **No External Dependencies**: All required scripts are built-in
- **Automatic Authentication Delegation**: Fully automated authentication system using Playwright MCP
- **Instant Deployment**: Complete operation with a single directory
- **Advanced State Management**: Precise agent state detection

## 🎯 Agent-to-Agent Collaboration

The main purpose of this MCP server is to **enable agents to manage other agents**. For example:

- A **boss agent** can divide tasks and assign them to multiple **worker agents**
- Each agent works in their specialized area (Claude Code for coding, Gemini for image generation)
- Agents send messages to each other and share progress
- One agent can review and integrate the work results of other agents
- **Automatic Authentication Delegation**: When new agents require authentication, existing authenticated agents automatically handle the authentication process

## 🛠️ Available Tools

Four tools that agents can use:

### 1. `start_agent` - Start an Agent
```javascript
start_agent(target="multiagent:0.2", agentType="claude")
start_agent(target="multiagent:0.3", agentType="gemini")
```
Starts an AI agent in the specified tmux target.
- **target**: tmux target format ("session:window.pane", e.g., "multiagent:0.5")
- **agentType**: claude (general code development) or gemini (image generation tasks)
- **Automatic Authentication**: When authentication is required, existing authenticated agents automatically handle the delegation

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

## 📦 Installation & Setup

### Self-Contained Installation

1. **Simply copy this directory!**
```bash
# Copy to any location
cp -r /path/to/agent-collaboration-mcp /your/target/directory/
cd /your/target/directory/agent-collaboration-mcp
npm install
```

2. **Configure with Claude Code**
```bash
# Register as MCP server
claude mcp add agent-collaboration node /path/to/agent-collaboration-mcp/index.js
```

Or add to `.claude.json`:
```json
{
  "mcpServers": {
    "agent-collaboration": {
      "command": "node",
      "args": ["/path/to/agent-collaboration-mcp/index.js"]
    }
  }
}
```

### Built-in Scripts

This MCP server includes the following built-in scripts (no external dependencies):

```
scripts/
├── agent_tools/
│   ├── agent_manager.sh      # Agent startup and state management
│   ├── auth_helper.sh        # Authentication state checking and process support
│   └── pane_controller.sh    # tmux pane control
├── utilities/
│   └── president_auth_delegator.sh  # Authentication delegation system
└── multiagent/
    └── quick_send_with_verify.sh    # Advanced message sending
```

## 💡 Usage Examples

### Basic Usage
```javascript
// 1. Start agents (with automatic authentication)
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

### Automatic Authentication Delegation Example
```javascript
// Start a new agent
start_agent(target="multiagent:0.5", agentType="claude")

// When authentication is required, the following happens automatically:
// 1. Detect existing authenticated agents (e.g., multiagent:0.2)
// 2. Extract authentication URL from new agent (multiagent:0.5)
// 3. Send Playwright MCP authentication instructions to authenticated agent
// 4. Automatic authentication code acquisition and sending
// 5. Automatic monitoring until startup completion
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

- **Node.js 18+**
- **tmux**
- **multiagent session**: `tmux new-session -d -s multiagent`

## 🚀 Advanced Features

### Authentication Delegation System
- **Automatic URL Detection**: Automatically extract authentication URLs from new agents
- **Playwright MCP Integration**: Browser automation for authentication code acquisition
- **Automatic Sending**: Automated sending of acquired authentication codes
- **Phase Monitoring**: Automatic monitoring of 3-stage authentication process

### Precise State Detection
- **Accurate Shell State Judgment**: Distinguish between authentication screen remnants and actual state
- **Real-time State Updates**: Dynamic state determination from screen content
- **Icon Display**: Intuitive state representation

### Advanced Message Sending
- **Send Confirmation**: Message reception confirmation
- **Control Character Support**: Support for Ctrl+C, Ctrl+L, etc.
- **Claude Code Compatibility**: Line break removal and reliable message sending

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

### Authentication delegation not working
- Check if existing authenticated agents exist
- Verify Playwright MCP availability
- Check authentication screen state with `capture_screen()`

## 🎯 Design Philosophy

This integrated MCP server is designed with the following principles:

1. **Complete Self-Containment**: Eliminate dependencies on external files
2. **Advanced Automation**: Minimize human intervention
3. **Collaboration Promotion**: Support natural collaboration between agents
4. **Scalability**: Stable simultaneous operation with multiple agents
5. **Deployment Simplification**: Complete operation with single directory

## 🤝 Contributing

We welcome contributions to this project. Please report bugs and suggest features.

## 📄 License

MIT License