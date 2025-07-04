# State Detection Logic Comparison: JavaScript vs Shell Script

## Overview

This document compares the state detection logic between:
1. **JavaScript**: `analyzeAgentState()` in `/src/tools/agentManager.js`
2. **Shell Script**: `get_agent_state()` in `/scripts/agent_tools/agent_manager.sh` combined with `get_auth_state()` in `/scripts/agent_tools/auth_helper.sh`

## States Detected

### JavaScript States
- `stopped` - Agent not running
- `executing_claude` - Claude is executing (ESC to interrupt)
- `running_claude` - Claude fully started
- `auth_claude` - Claude authentication in progress
- `running_gemini` - Gemini fully started
- `auth_gemini` - Gemini authentication in progress

### Shell Script States
- `stopped` - Agent not running
- `running` - Agent fully authenticated and running
- `auth_pending` - Authentication required/in progress

**Key Difference**: The shell script has only 3 states while JavaScript has 6 more granular states.

## Priority Order of Checks

### JavaScript Priority Order (analyzeAgentState)

1. **Priority 0 (Highest)**: Check if last valid line ends with `$` → `stopped`
2. **Priority 1**: ESC to interrupt → `executing_claude`
3. **Priority 2**: Logged out patterns → `stopped`
4. **Priority 2.5**: AUTH-HELPER prompt → `stopped`
5. **Priority 3**: Claude startup complete patterns → `running_claude`
6. **Priority 4**: Claude authentication patterns → `auth_claude`
7. **Priority 5**: Gemini authentication patterns → `auth_gemini`
8. **Priority 6**: Gemini startup complete patterns → `running_gemini`
9. **Priority 7**: Shell prompt only → `stopped`

### Shell Script Priority Order

The shell script doesn't have a clear priority order. Instead, it:
1. Calls `auth_helper.sh check` to get detailed auth state
2. Maps the detailed state to simplified states:
   - `authenticated` → `running`
   - Various auth states → `auth_pending`
   - Everything else → `stopped`

## Exact Patterns Comparison

### Detecting "Stopped" State

**JavaScript**:
```javascript
// Priority 0: Last valid line ends with $
if (lastValidLine.match(/\$\s*$/)) {
    return { state: 'stopped', agent: 'none', details: '停止中（シェルプロンプト）' };
}

// Logged out patterns
if (normalizedLower.includes('successfully logged out') ||
    (content.includes('$') && normalizedLower.includes('logged out')) ||
    (content.includes('Successfully logged out') && content.includes('$'))) {
    return { state: 'stopped', agent: 'none', details: '停止中（ログアウト済み）' };
}

// AUTH-HELPER prompt
if (content.includes('(auth-helper)') || content.includes('(AUTH-HELPER)')) {
    return { state: 'stopped', agent: 'none', details: '停止中（AUTH-HELPER）' };
}

// Shell prompt only
if ((content.match(/.*[$#]\s*$/) || content.includes('bash') || content.includes('sh-')) &&
    !content.includes('claude') && 
    !content.includes('gemini')) {
    return { state: 'stopped', agent: 'none', details: '停止中' };
}
```

**Shell Script** (in auth_helper.sh):
```bash
# Check for shell prompt in last lines
local last_lines=$(echo "$screen" | tail -5 | tr '\n' ' ' | tr '[:upper:]' '[:lower:]')
if echo "$last_lines" | grep -qE '.*[\$#]\s*' && \
   (echo "$last_lines" | grep -q "agent_collaboration\|org-\|pane-\|agent-"); then
    echo "not_started"
    return 0
fi
```

**Key Difference**: JavaScript checks specifically if the last line ends with `$`, while shell script checks if `$` appears anywhere in the last 5 lines combined with specific keywords.

### Detecting Claude Running State

**JavaScript**:
```javascript
// Complex composite check
if ((content.includes('/help for help') || normalizedLower.includes('/help for help')) &&
    ((content.includes('bypassing') && content.includes('permissions')) || 
     (content.includes('Bypassing') && content.includes('Permissions')))) {
    return { state: 'running_claude', agent: 'claude', details: 'Claude起動完了' };
}

// Multiple other patterns...
```

**Shell Script** (in auth_helper.sh):
```bash
# Check for /help for help pattern
if echo "$screen" | grep -q "/help for help.*status.*current setup" || \
   echo "$normalized_screen" | grep -q "/help for help.*status.*current setup"; then
    echo "authenticated"
    return 0
fi

# Similar patterns but returns "authenticated" not specific agent type
```

**Key Difference**: JavaScript identifies specific agent types in the state, while shell script only knows "authenticated" vs "not authenticated".

### Detecting Executing State

**JavaScript**:
```javascript
// Priority 1: Claude executing
if (content.includes('esc to interrupt') || content.includes('escape to interrupt')) {
    return { state: 'executing_claude', agent: 'claude', details: 'Claude実行中' };
}
```

**Shell Script**: Does not detect this state at all. This is a major gap.

## Critical Logic Differences

### 1. State Granularity
- **JavaScript**: 6 distinct states with agent type embedded
- **Shell Script**: 3 generic states without agent identification

### 2. Execution State Detection
- **JavaScript**: Detects when Claude is actively executing (ESC to interrupt)
- **Shell Script**: Missing this detection entirely

### 3. Screen Content Normalization
- **JavaScript**: 
  ```javascript
  const normalizedContent = screenContent.replace(/\n/g, ' ').replace(/\s+/g, ' ');
  ```
- **Shell Script**:
  ```bash
  local normalized_screen=$(echo "$screen" | tr '\n' ' ' | tr -s ' ')
  ```
  Both normalize similarly, but JavaScript uses it more consistently.

### 4. Last Line Detection
- **JavaScript**: Finds the last non-empty line and checks if it ends with `$`
- **Shell Script**: Checks last 5 lines combined for `$` anywhere with specific keywords

### 5. Agent Type Detection
- **JavaScript**: Returns agent type as part of state object
- **Shell Script**: Has to infer agent type separately by grepping screen content

### 6. Pattern Matching Approach
- **JavaScript**: Uses includes() for substring matching and regex for patterns
- **Shell Script**: Uses grep with various flags (-q, -E, -i)

## Why JavaScript Works Better

1. **Clear Priority System**: JavaScript has explicit priority levels (0-7) ensuring most specific patterns are checked first.

2. **Last Line Focus**: The Priority 0 check for `$` at the end of the last valid line is crucial for detecting stopped state accurately.

3. **Execution State Detection**: JavaScript catches the "ESC to interrupt" state which is critical for knowing when Claude is actively working.

4. **Better State Granularity**: 6 states vs 3 states provides much more accurate status information.

5. **Integrated Agent Detection**: State includes agent type, avoiding separate detection logic.

## What Shell Script is Missing

1. **No execution state detection** - Cannot tell when Claude is actively running a command
2. **Less precise last line checking** - Checks multiple lines instead of focusing on the actual last line
3. **No agent type in state** - Has to separately determine which agent is running
4. **Missing AUTH-HELPER prompt detection** - Doesn't recognize when in auth helper mode
5. **Less comprehensive pattern matching** - Fewer patterns for each state

## Recommendations

To improve the shell script:
1. Add execution state detection for "esc to interrupt" pattern
2. Implement proper last line checking (find last non-empty line, check if it ends with $)
3. Add more granular states that include agent type
4. Add AUTH-HELPER prompt detection as a stopped state
5. Implement a clear priority order for pattern matching