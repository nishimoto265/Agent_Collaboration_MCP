const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

class ParallelImplementation {
    constructor(projectDir) {
        this.projectDir = projectDir;
        
        // MCPサーバーのルートディレクトリを取得
        const mcpRoot = path.dirname(path.dirname(__dirname));
        this.parallelScriptPath = path.join(mcpRoot, 'scripts', 'parallel', 'parallel_impl_manager.sh');
        this.worktreeScriptPath = path.join(mcpRoot, 'scripts', 'parallel', 'worktree_manager.sh');
        
        // スクリプトの存在確認
        if (!fs.existsSync(this.parallelScriptPath)) {
            throw new Error(`Parallel implementation script not found: ${this.parallelScriptPath}`);
        }
    }

    /**
     * 並列実装を開始
     */
    async startParallelImplementation(prompt, workerCount = 3, complexity = 'medium', autoMerge = false, useNewTerminal = true, agentType = 'claude') {
        try {
            console.log(`[ParallelImpl] Starting parallel implementation...`);
            console.log(`[ParallelImpl] Prompt: ${prompt}`);
            console.log(`[ParallelImpl] Workers: ${workerCount}, Complexity: ${complexity}`);
            
            // プロンプトをエスケープ
            const escapedPrompt = prompt.replace(/'/g, "'\\''");
            
            // コマンドを構築
            const command = `'${this.parallelScriptPath}' start '${escapedPrompt}' ${workerCount} ${complexity} ${autoMerge} ${useNewTerminal} ${agentType}`;
            
            // 実行（プロジェクトディレクトリから実行）
            const result = execSync(command, {
                cwd: this.projectDir,
                encoding: 'utf-8',
                env: {
                    ...process.env,
                    PROJECT_DIR: path.dirname(path.dirname(__dirname))
                }
            });
            
            // セッションIDを抽出
            const lines = result.trim().split('\n');
            let sessionId = null;
            
            // 最後の行からparallel_で始まる行を探す
            for (let i = lines.length - 1; i >= 0; i--) {
                if (lines[i].startsWith('parallel_')) {
                    sessionId = lines[i];
                    break;
                }
            }
            
            if (!sessionId) {
                console.error('[ParallelImpl] Script output:', result);
                throw new Error('Failed to get session ID from script output');
            }
            
            console.log(`[ParallelImpl] Session started: ${sessionId}`);
            
            return {
                success: true,
                sessionId: sessionId,
                message: `並列実装セッションを開始しました: ${sessionId}`,
                details: {
                    workerCount: workerCount,
                    complexity: complexity,
                    autoMerge: autoMerge,
                    agentType: agentType
                }
            };
            
        } catch (error) {
            console.error('[ParallelImpl] Error:', error);
            return {
                success: false,
                error: error.message,
                details: error.toString()
            };
        }
    }

    /**
     * 並列実装の状態を取得
     */
    async getParallelStatus(sessionId = null) {
        try {
            console.log(`[ParallelImpl] Getting status...`);
            
            const command = sessionId 
                ? `'${this.parallelScriptPath}' status '${sessionId}'`
                : `'${this.parallelScriptPath}' status`;
            
            const result = execSync(command, {
                cwd: this.projectDir,
                encoding: 'utf-8',
                env: {
                    ...process.env,
                    PROJECT_DIR: path.dirname(path.dirname(__dirname))
                }
            });
            
            if (sessionId && result.includes('{')) {
                // 特定セッションの詳細情報（JSON）
                const sessionInfo = JSON.parse(result);
                
                return {
                    success: true,
                    sessionInfo: sessionInfo,
                    message: `セッション ${sessionId} の状態を取得しました`
                };
            } else {
                // 全セッションのリスト
                const sessions = result.trim().split('\n').filter(line => line.length > 0);
                
                return {
                    success: true,
                    sessions: sessions,
                    message: `${sessions.length}個のセッションが見つかりました`
                };
            }
            
        } catch (error) {
            console.error('[ParallelImpl] Error:', error);
            return {
                success: false,
                error: error.message
            };
        }
    }

    /**
     * Worker完了をモニター
     */
    async monitorWorkers(sessionId) {
        try {
            console.log(`[ParallelImpl] Monitoring workers for session: ${sessionId}`);
            
            const command = `'${this.parallelScriptPath}' monitor '${sessionId}'`;
            
            const result = execSync(command, {
                cwd: this.projectDir,
                encoding: 'utf-8',
                env: {
                    ...process.env,
                    PROJECT_DIR: path.dirname(path.dirname(__dirname))
                }
            });
            
            const completionRate = parseInt(result.trim());
            
            return {
                success: true,
                completionRate: completionRate,
                message: `完了率: ${completionRate}%`,
                isComplete: completionRate === 100
            };
            
        } catch (error) {
            console.error('[ParallelImpl] Error:', error);
            return {
                success: false,
                error: error.message
            };
        }
    }

    /**
     * Boss評価をトリガー
     */
    async triggerBossEvaluation(sessionId) {
        try {
            console.log(`[ParallelImpl] Triggering boss evaluation for session: ${sessionId}`);
            
            const command = `'${this.parallelScriptPath}' trigger-boss '${sessionId}'`;
            
            execSync(command, {
                cwd: path.dirname(this.parallelScriptPath),
                encoding: 'utf-8'
            });
            
            return {
                success: true,
                message: `Boss評価を開始しました: ${sessionId}`
            };
            
        } catch (error) {
            console.error('[ParallelImpl] Error:', error);
            return {
                success: false,
                error: error.message
            };
        }
    }

    /**
     * Worktreeをマージ
     */
    async mergeWorktree(sourceBranch, targetBranch = 'main', autoMerge = false) {
        try {
            console.log(`[ParallelImpl] Merging worktree: ${sourceBranch} -> ${targetBranch}`);
            
            const command = `'${this.worktreeScriptPath}' merge '${sourceBranch}' '${targetBranch}' ${autoMerge}`;
            
            const result = execSync(command, {
                cwd: path.dirname(this.worktreeScriptPath),
                encoding: 'utf-8'
            });
            
            return {
                success: true,
                message: autoMerge ? `自動マージ完了: ${sourceBranch} -> ${targetBranch}` : 'マージプレビューを表示しました',
                details: result
            };
            
        } catch (error) {
            console.error('[ParallelImpl] Error:', error);
            return {
                success: false,
                error: error.message
            };
        }
    }

    /**
     * Worktreeをクリーンアップ
     */
    async cleanupWorktree(branchName, force = false) {
        try {
            console.log(`[ParallelImpl] Cleaning up worktree: ${branchName}`);
            
            const command = `'${this.worktreeScriptPath}' cleanup '${branchName}' ${force}`;
            
            execSync(command, {
                cwd: path.dirname(this.worktreeScriptPath),
                encoding: 'utf-8'
            });
            
            return {
                success: true,
                message: `Worktreeを削除しました: ${branchName}`
            };
            
        } catch (error) {
            console.error('[ParallelImpl] Error:', error);
            return {
                success: false,
                error: error.message
            };
        }
    }
}

module.exports = ParallelImplementation;