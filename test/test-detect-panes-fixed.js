#!/usr/bin/env node

// Test auto-detection after fix
const { PaneConfigManager } = require('../src/tools/paneConfigManager');

console.log('🔍 Testing fixed pane auto-detection...');

try {
  const paneManager = new PaneConfigManager(process.cwd(), 'test-session2');
  
  console.log('1. Testing configuration initialization...');
  const debugInfo = paneManager.getDebugInfo();
  console.log(`   ✅ Config loaded: ${debugInfo.configVersion}`);
  console.log(`   ✅ Current layout: ${debugInfo.currentLayout}`);
  
  console.log('2. Testing pane detection...');
  const detectedPanes = paneManager.detectCurrentPanes();
  const paneCount = Object.keys(detectedPanes).length;
  
  console.log(`   ✅ Detection successful: Found ${paneCount} panes`);
  
  if (paneCount > 0) {
    console.log('3. Detected pane details:');
    Object.entries(detectedPanes).forEach(([num, config]) => {
      console.log(`   - Pane ${num}: ${config.displayName} (${config.organization}/${config.role})`);
    });
  }
  
  console.log('4. Testing layout switching...');
  const layouts = paneManager.getAvailableLayouts();
  console.log(`   ✅ Available layouts: ${layouts.map(l => l.name).join(', ')}`);
  
} catch (error) {
  console.log('❌ Test failed:');
  console.error(error.message);
  console.error(error.stack);
}

console.log('\n🎯 Fixed Pane Detection Test Complete');