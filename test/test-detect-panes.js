#!/usr/bin/env node

// Test auto-detection of different pane configurations
const { PaneConfigManager } = require('../src/tools/paneConfigManager');

console.log('🔍 Testing pane auto-detection...');

// Test with test-session (3 panes)
try {
  const paneManager = new PaneConfigManager(process.cwd(), 'test-session');
  const detectedPanes = paneManager.detectCurrentPanes();
  const paneCount = Object.keys(detectedPanes).length;
  
  console.log(`✅ Auto-detection test: Found ${paneCount} panes in test-session`);
  
  if (paneCount > 0) {
    console.log('   Detected panes:');
    Object.entries(detectedPanes).forEach(([num, config]) => {
      console.log(`   - Pane ${num}: ${config.displayName} (${config.role})`);
    });
  }
  
} catch (error) {
  console.log('⚠️ Auto-detection test: Session not found or error');
  console.log(`   Error: ${error.message}`);
}

console.log('\n🎯 Pane Detection Test Complete');