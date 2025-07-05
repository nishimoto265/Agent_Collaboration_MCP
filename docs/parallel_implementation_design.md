# 並列実装機能設計書

## 概要
Claude Code (CC) で並列実装を簡単にするMCP機能。複数のワーカーが並列で実装を行い、ボスが評価・統合する。

## 機能フロー

1. **ユーザーがCCに指示**
   - 例: "○○を実装して"、"○○を改善して"、"リファクタして"

2. **MCPが自動的に並列環境を構築**
   - Boss 1体 + Worker N体（デフォルト3体、設定可能）
   - 簡単なタスクはWorker 1体のみ
   - 各Worker用のworktreeを作成

3. **実装フェーズ**
   - Bossがプロンプトを各Workerに配布
   - Workerが並列で実装
   - 全Worker完了後、Bossが評価

4. **評価・改善フェーズ**
   - Bossが各実装を評価
   - 目標点数未達の場合は改善指示
   - 最終的にBossのworktreeに完成品

5. **完了通知**
   - 音で終了を通知（CC機能利用）
   - ユーザーが確認してマージ
   - `--skip`オプションで自動マージ

## コンポーネント設計

### 1. Worktree Manager
```bash
# worktree_manager.sh
- create_worktree(branch_name, base_branch)
- list_worktrees()
- cleanup_worktree(branch_name)
- merge_worktree(source_branch, target_branch)
```

### 2. Parallel Implementation Manager
```bash
# parallel_impl_manager.sh
- start_parallel_implementation(prompt, worker_count, complexity)
- distribute_prompt(boss_pane, worker_panes, prompt)
- monitor_workers(worker_panes)
- trigger_evaluation(boss_pane)
```

### 3. Boss Agent Controller
```bash
# boss_controller.sh
- start_boss(pane, worktree)
- send_evaluation_prompt(pane, worker_results)
- handle_evaluation_result(result)
- send_improvement_instructions(worker_pane, improvements)
```

### 4. Worker Agent Controller
```bash
# worker_controller.sh
- start_worker(pane, worktree, worker_id)
- send_implementation_prompt(pane, prompt)
- monitor_completion(pane)
- get_implementation_result(pane)
```

## MCPツール定義

### parallel_implement
```javascript
{
  name: "parallel_implement",
  description: "並列実装を開始",
  parameters: {
    prompt: "実装指示",
    worker_count: "ワーカー数（デフォルト: 3）",
    complexity: "複雑度（simple/medium/complex）",
    auto_merge: "自動マージフラグ"
  }
}
```

### get_parallel_status
```javascript
{
  name: "get_parallel_status",
  description: "並列実装の状態を取得",
  parameters: {
    session_id: "セッションID"
  }
}
```

## 設定項目

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

## ペイン配置例

```
+--------+--------+--------+--------+
| Boss   | Worker1| Worker2| Worker3|
| (評価) | (実装) | (実装) | (実装) |
+--------+--------+--------+--------+
| Monitor Panel (状態表示)          |
+-----------------------------------+
```