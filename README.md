# Agent Collaboration MCP Server

[English version is here](README_en.md)

複数のAIエージェントが協調して作業できるようにする**完全自己完結型**MCPサーバーです。このツールをClaude Codeなどのエージェントに使わせることで、エージェントが他のエージェントを起動・制御し、チームとして複雑なタスクを実行できます。

## 🚀 簡単インストール・即座に使用開始

```bash
# npm経由でグローバルインストール
npm install -g agent-collaboration-mcp

# または、ローカルで直接使用
git clone [repository-url]
cd agent-collaboration-mcp
npm install
npm start
```

## ✨ 特徴

- **シンプルなアーキテクチャ**: ペイン番号を直接指定する直感的な操作
- **複数エージェント対応**: Claude CodeとGeminiの同時制御
- **柔軟なセッション管理**: 複数プロジェクトの並行作業に対応
- **高度な状態管理**: エージェントの実行状態をリアルタイムで監視

## 🎯 エージェント同士の協調作業

このMCPサーバーの主な用途は、**エージェントが他のエージェントを管理すること**です。例えば：

- **ボスエージェント**がタスクを分割し、複数の**ワーカーエージェント**に割り振る
- 各エージェントが得意分野で作業（Claude Codeはコーディング、Geminiは画像生成）
- エージェント間でメッセージを送り合い、進捗を共有
- 一つのエージェントが他のエージェントの作業結果を確認・統合
- **自動認証代行**: 新しいエージェントが認証を要求された場合、既存の認証済みエージェントが自動で認証を代行

## 🛠️ 提供ツール

エージェントが使用できる4つのツール：

### 1. `start_agent` - エージェントの起動
```javascript
start_agent(target="multiagent:0.2", agentType="claude")
start_agent(target="multiagent:0.3", agentType="gemini")
```
指定したtmuxターゲットでAIエージェントを起動します。
- **target**: tmuxターゲット形式（"session:window.pane"、例："multiagent:0.5"）
- **agentType**: claude（一般的なコード開発）または gemini（画像生成タスク）
- **additionalArgs**: 追加の引数（オプション）

### 2. `get_agent_status` - ステータス確認
```javascript
get_agent_status()                          // 全エージェントの状態を確認
get_agent_status(target="multiagent:0.2")  // 特定ペインの詳細状態を確認
get_agent_status(target="multiagent:*")    // セッション内全ペインの状態確認
```

#### 取得可能なステータス

| ステータス | アイコン | 説明 |
|-----------|---------|------|
| `running_claude` | ✅ | Claude Codeが実行中で入力待機状態 |
| `running_gemini` | 💎 | Geminiが実行中で入力待機状態 |
| `auth_claude` | 🔐 | Claude Codeが認証プロセス中 |
| `auth_gemini` | 🔑 | Geminiが認証プロセス中 |
| `executing_claude` | ⚡ | Claude実行中（ESC to interrupt表示） |
| `stopped` | ⚫ | エージェントが停止中またはシェル状態 |

### 3. `send_message` - メッセージ送信
```javascript
send_message(target="multiagent:0.2", message="こんにちは")
send_message(target="multiagent:0.3", message="C-c", sendEnter=false) // Ctrl+C送信
```
指定したペインにメッセージや制御文字を送信します。高度なメッセージ送信機能付き。

### 4. `capture_screen` - 画面キャプチャ
```javascript
capture_screen(target="multiagent:0.2")        // 全履歴キャプチャ
capture_screen(target="multiagent:0.3", lines=50) // 最後の50行
```
ペインの画面内容を取得します。

## 📦 インストール・設定

### 1. インストール方法

**npm経由（推奨）**:
```bash
npm install -g agent-collaboration-mcp
```

**ローカルインストール**:
```bash
git clone [repository-url]
cd agent-collaboration-mcp
npm install
```

### 2. Claude Codeへの設定

`.claude.json`に以下を追加：

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

ローカルインストールの場合：
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

### 3. tmuxセッションの準備

```bash
# デフォルトセッション（multiagent）を作成
tmux new-session -d -s multiagent

# 複数プロジェクトの場合
tmux new-session -d -s project1
tmux new-session -d -s project2
```

## 💡 使用例

### 基本的な使い方
```javascript
// 1. エージェントを起動（自動認証付き）
start_agent(target="multiagent:0.2", agentType="claude")
start_agent(target="multiagent:0.3", agentType="claude")

// 2. ステータス確認
get_agent_status()

// 3. タスクを指示
send_message(target="multiagent:0.2", message="READMEを確認してください")
send_message(target="multiagent:0.3", message="テストを実行してください")

// 4. 結果を確認
capture_screen(target="multiagent:0.3")
```

### 複数セッションでの作業例
```javascript
// プロジェクト1での作業
start_agent(target="project1:0.0", agentType="claude")
send_message(target="project1:0.0", message="バックエンドAPIを実装してください")

// プロジェクト2での並行作業
start_agent(target="project2:0.0", agentType="gemini")
send_message(target="project2:0.0", message="UIデザインを作成してください")
```

### 自動認証代行機能（オプション）

新しいエージェントの認証を自動化したい場合は、[Playwright MCP](https://github.com/microsoft/playwright-mcp)を併用することで、既存の認証済みエージェントが新しいエージェントの認証を自動で代行できます。

```javascript
// Playwright MCPがインストールされている場合の動作
start_agent(target="multiagent:0.5", agentType="claude")
// 認証が必要な場合、以下が自動実行されます：
// 1. 既存の認証済みエージェントを検出
// 2. 新エージェントの認証URLを抽出
// 3. Playwright MCPを使用してブラウザで自動認証
// 4. 認証コードを自動的に新エージェントに送信
```

### マルチエージェント協調の例
```javascript
// Boss エージェント（タスク管理）
start_agent(target="multiagent:0.0", agentType="claude")

// Worker エージェント群
start_agent(target="multiagent:0.1", agentType="claude")  // コード開発担当
start_agent(target="multiagent:0.2", agentType="gemini") // 画像生成担当
start_agent(target="multiagent:0.3", agentType="claude") // テスト担当

// Bossからタスク分割指示
send_message(target="multiagent:0.0", message="プロジェクトの進捗確認と各チームへのタスク分割をお願いします")

// 各Workerの状態監視
get_agent_status()
```

### 緊急停止・制御
```javascript
// プロセスを停止
send_message(target="multiagent:0.2", message="C-c", sendEnter=false)

// 画面をクリア
send_message(target="multiagent:0.2", message="C-l", sendEnter=false)
```

## 🔧 前提条件

### 必須
- **Node.js 18以上**
- **tmux**
- **tmuxセッション**: `tmux new-session -d -s multiagent`

### オプション（認証自動化用）
- **[Playwright MCP](https://github.com/microsoft/playwright-mcp)**: エージェントの認証を自動化する場合に必要

## 🚀 高度な機能

### 柔軟なターゲット指定
- **セッション指定**: 異なるプロジェクトで並行作業
- **ワイルドカード**: `multiagent:*`で全ペインを対象に
- **直感的な番号指定**: `0`, `1`, `2`...のシンプルな指定

### 精密な状態検出
- **リアルタイム監視**: エージェントの実行状態を即座に判定
- **複数状態の識別**: 実行中、認証中、停止中などを正確に判別
- **アイコン付き表示**: 視覚的に分かりやすい状態表示

## 🚨 トラブルシューティング

### tmuxセッションが存在しない
```bash
# multiagentセッションを作成
tmux new-session -d -s multiagent
```

### エージェントが起動しない
- `get_agent_status()`で状態を確認
- `capture_screen()`でエラーメッセージを確認
- 認証代行システムが自動で問題を解決する場合が多い

### メッセージが送信されない
- エージェントが起動中か`get_agent_status()`で確認
- tmuxセッションが存在するか確認
- ターゲット形式が正しいか確認（"session:window.pane"）

## 📄 スクリプトのカスタマイズ

本MCPサーバーは`scripts/agent_tools/`内のスクリプトを使用します。独自のエージェント起動方法やメッセージ送信方法がある場合は、これらのスクリプトをカスタマイズしてください：

- `agent_manager.sh`: エージェント起動コマンドの定義
- `pane_controller.sh`: メッセージ送信方法の定義


## 🤝 貢献

このプロジェクトへの貢献を歓迎します。バグ報告や機能提案をお願いします。

## 📄 ライセンス

MIT License