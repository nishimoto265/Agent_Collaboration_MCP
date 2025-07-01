# Agent Collaboration MCP Server v3.0 (配布用完全版)

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

## ✨ v3.0の特徴：完全自己完結型

この配布用完全版の特徴：
- **外部依存完全除去**: 必要なスクリプトをすべて内蔵、単一パッケージで完全動作
- **自動認証代行システム**: Playwright MCPを使った完全自動認証システム
- **即座にデプロイ**: どこでも動作する移植可能なパッケージ
- **高度な状態管理**: 精密なエージェント状態検出・認証状態自動判別
- **配布最適化**: npm publish対応、グローバルインストール可能

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
- **自動認証**: 認証が必要な場合、既存の認証済みエージェントが自動で認証代行を実行

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

### 完全自己完結型のインストール

1. **このディレクトリをコピー**するだけ！
```bash
# 任意の場所にコピー
cp -r /path/to/agent-collaboration-mcp /your/target/directory/
cd /your/target/directory/agent-collaboration-mcp
npm install
```

2. **Claude Codeで設定**
```bash
# MCPサーバーとして登録
claude mcp add agent-collaboration node /path/to/agent-collaboration-mcp/index.js
```

または `.claude.json`に追加：
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

### 内蔵スクリプト

このMCPサーバーには以下のスクリプトが内蔵されています（外部依存なし）：

```
scripts/
├── agent_tools/
│   ├── agent_manager.sh      # エージェント起動・状態管理
│   ├── auth_helper.sh        # 認証状態確認・認証プロセス支援
│   └── pane_controller.sh    # tmuxペイン制御
├── utilities/
│   └── president_auth_delegator.sh  # 認証代行システム
└── multiagent/
    └── quick_send_with_verify.sh    # 高度なメッセージ送信
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

### 自動認証代行の動作例
```javascript
// 新しいエージェントを起動
start_agent(target="multiagent:0.5", agentType="claude")

// 認証が必要な場合、自動で以下が実行される：
// 1. 既存の認証済みエージェント（例：multiagent:0.2）を検出
// 2. 新エージェント（multiagent:0.5）の認証URLを抽出
// 3. 認証済みエージェントにPlaywright MCPを使った認証指示を送信
// 4. 認証コードの自動取得・送信
// 5. 起動完了まで自動監視
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

- **Node.js 18以上**
- **tmux**
- **multiagentセッション**: `tmux new-session -d -s multiagent`

## 🚀 高度な機能

### 認証代行システム
- **自動URL検出**: 新しいエージェントの認証URLを自動抽出
- **Playwright MCP連携**: ブラウザ自動操作による認証コード取得
- **自動送信**: 取得した認証コードの自動送信
- **Phase監視**: 3段階の認証プロセスを自動監視

### 精密な状態検出
- **シェル状態の正確な判定**: 認証画面の残骸と実際の状態を区別
- **リアルタイム状態更新**: 画面内容からの動的状態判定
- **アイコン付き表示**: 直感的な状態表示

### 高度なメッセージ送信
- **送信確認機能**: メッセージの受信確認
- **制御文字対応**: Ctrl+C, Ctrl+L等の制御文字送信
- **Claude Code対応**: 改行除去・確実なメッセージ送信

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

### 認証代行が動作しない
- 既存の認証済みエージェントが存在するか確認
- Playwright MCPが利用可能か確認
- `capture_screen()`で認証画面の状態を確認

## 📦 配布・インストール

### Claude Codeでの使用

1. **MCPサーバーとして設定**：
```json
// .claude.json に追加
{
  "agent-collaboration": {
    "command": "npx",
    "args": ["agent-collaboration-mcp"]
  }
}
```

2. **ローカルインストール**：
```bash
npm install agent-collaboration-mcp
# または
npm link agent-collaboration-mcp  # グローバルインストール後
```

### 独立使用

```bash
# ダウンロード・展開後
cd agent-collaboration-mcp
npm install
node index.js  # MCPサーバー起動
```

## 🎯 設計思想

この配布用完全版MCPサーバーは、以下の思想で設計されています：

1. **完全自己完結**: 外部ファイルへの依存を完全排除、単一パッケージで完全動作
2. **高度な自動化**: 認証代行システムによる人間の介入最小化
3. **協調作業の促進**: エージェント間の自然な協調とタスク分散を支援
4. **移植性の確保**: どこでも同じように動作する配布可能パッケージ
5. **配布最適化**: npm ecosystem対応、簡単インストール・即座使用開始

## 🤝 貢献

このプロジェクトへの貢献を歓迎します。バグ報告や機能提案をお願いします。

## 📄 ライセンス

MIT License