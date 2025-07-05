# 並列実装機能の使い方

## 概要

並列実装機能は、複数のWorkerが同じタスクを並列で実装し、Bossが最良の成果物を選択・統合する機能です。

## 基本的な使い方

### 1. 並列実装を開始

```bash
# Claude Codeから
parallel_implement "ユーザー認証機能を実装してください"
```

### 2. オプション指定

```bash
parallel_implement "リファクタリングを実行" worker_count=5 complexity=complex
```

### パラメータ

- `prompt`: 実装指示（必須）
- `worker_count`: ワーカー数（デフォルト: 3）
- `complexity`: 複雑度
  - `simple`: Worker 1体のみ（Bossなし）
  - `medium`: Boss + Worker 3体（デフォルト）
  - `complex`: Boss + Worker 5体
- `auto_merge`: 完了後の自動マージ（デフォルト: false）

## 機能の特徴

### 自動端末起動

並列実装を開始すると、自動的に：
1. 新しい端末ウィンドウが開く
2. 専用のtmuxセッションが作成される
3. ペインが横並びにレイアウトされる

### ペインレイアウト

```
+--------+--------+--------+--------+
| Boss   | Worker1| Worker2| Worker3|
+--------+--------+--------+--------+
```

### 各ペインの役割

- **Boss**: 評価・統合を担当
- **Worker**: 実装を担当

## ワークフロー

1. **開始時**
   - 各Workerに同じプロンプトが配布される
   - Workerは独立して実装を開始

2. **実装中**
   - 進捗は `get_parallel_status` で確認可能
   - 各Workerは「実装完了」と報告して終了

3. **評価フェーズ**
   - 全Worker完了後、Bossが起動
   - 各実装を評価し、最良のものを選択または統合

4. **完了**
   - Bossが音で完了を通知
   - 成果物はBossのworktreeに保存

## 状態確認

```bash
# 全セッションの一覧
get_parallel_status

# 特定セッションの詳細
get_parallel_status session_id="parallel_20240105_123456"
```

## 端末サポート

以下の端末エミュレータをサポート：
- GNOME Terminal
- Konsole
- xterm
- Alacritty
- Kitty
- WezTerm
- macOS Terminal.app

## 設定

`config.json`で以下を設定可能：

```json
{
  "parallel_implementation": {
    "default_worker_count": 3,
    "max_worker_count": 10,
    "evaluation_threshold": 80,
    "auto_cleanup_worktrees": true,
    "notification_sound": true,
    "default_base_branch": "main"
  }
}
```

## トラブルシューティング

### 端末が開かない場合

1. サポートされている端末がインストールされているか確認
2. `scripts/parallel/terminal_launcher.sh detect` で検出された端末を確認

### tmuxセッションが作成されない場合

1. tmuxがインストールされているか確認
2. 既存のセッションと名前が衝突していないか確認

### Workerが起動しない場合

1. Claudeがインストールされているか確認
2. Worktreeの作成権限があるか確認