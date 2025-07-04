# 処理重複の分析と改善提案

## 概要
`/src/tools`と`/scripts`間で重複している処理を特定しました。

## 主な重複

### 1. エージェント状態検出ロジック（最優先で修正すべき）

**現状の問題**:
- JavaScriptの`analyzeAgentState()`（約150行）
- シェルスクリプトの`auth_helper.sh`の状態検出
- 両方で同じパターンマッチングを実装

**影響**:
- メンテナンスが二重に必要
- 不整合が発生する可能性
- バグ修正を両方に適用する必要

**改善案**:
```javascript
// 現在（重複あり）
async getAgentState(target) {
  const screenContent = await this.captureScreen(target);
  return this.analyzeAgentState(screenContent); // 独自実装
}

// 改善後（シェルスクリプトに委譲）
async getAgentState(target) {
  const { paneNumber } = this.parseTarget(target);
  const cmd = `${this.authHelperPath} check ${paneNumber}`;
  const { stdout } = await execAsync(cmd);
  return this.parseAuthHelperOutput(stdout);
}
```

### 2. ステータス表示ロジック

**現状の問題**:
- JavaScript側で独自のステータス整形
- シェルスクリプト側でも同様の整形

**改善案**:
- シェルスクリプトの`status`コマンドを呼び出し
- JavaScriptは結果をMCP形式に変換するだけ

### 3. 直接的なtmuxコマンド実行

**現状の問題**:
```javascript
// JavaScriptが直接tmuxを実行
const { stdout } = await execAsync(`tmux capture-pane -t ${fullTarget} -p -S -3000`);
```

**改善案**:
```javascript
// pane_controller.sh経由で実行
const { stdout } = await execAsync(`${this.paneControllerPath} capture ${paneNumber}`);
```

## 優先順位

1. **高**: `analyzeAgentState()`の削除とシェルスクリプトへの委譲
2. **中**: ステータス表示の統一
3. **低**: 直接tmuxコマンドの除去

## メリット

1. **保守性向上**: 修正箇所が一元化
2. **一貫性**: 状態判定ロジックが統一
3. **コード削減**: 約200行のコード削減が可能
4. **テスト容易性**: シェルスクリプトのみテストすれば良い

## 実装計画

1. `auth_helper.sh`の出力形式を確認
2. JavaScriptでパーサーを実装
3. `analyzeAgentState()`を段階的に置き換え
4. テストで動作確認
5. 不要なコードを削除