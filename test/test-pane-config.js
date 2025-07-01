#!/usr/bin/env node

// Simple test for PaneConfigManager functionality
const { PaneConfigManager } = require('../src/tools/paneConfigManager');
const path = require('path');

console.log('🧪 Testing PaneConfigManager...');

// Test 1: Basic initialization
try {
  const paneManager = new PaneConfigManager(process.cwd(), 'test-session');
  console.log('✅ Test 1: PaneConfigManager initialization - PASS');
} catch (error) {
  console.log('❌ Test 1: PaneConfigManager initialization - FAIL');
  console.error(error.message);
  process.exit(1);
}

// Test 2: Configuration loading
try {
  const paneManager = new PaneConfigManager(process.cwd(), 'test-session');
  const debugInfo = paneManager.getDebugInfo();
  if (debugInfo.configVersion) {
    console.log('✅ Test 2: Configuration loading - PASS');
    console.log(`   Config version: ${debugInfo.configVersion}`);
    console.log(`   Current layout: ${debugInfo.currentLayout}`);
    console.log(`   Total panes: ${debugInfo.totalPanes}`);
  } else {
    console.log('⚠️ Test 2: Configuration loading - FALLBACK MODE');
  }
} catch (error) {
  console.log('❌ Test 2: Configuration loading - FAIL');
  console.error(error.message);
}

// Test 3: Pane number conversion
try {
  const paneManager = new PaneConfigManager(process.cwd(), 'test-session');
  
  // Test known pane names
  const testCases = [
    { input: 'boss01', expected: '0' },
    { input: 'worker-a01', expected: '1' },
    { input: 'president', expected: '16' },
    { input: '5', expected: '5' }, // numeric input
  ];
  
  let passCount = 0;
  testCases.forEach(test => {
    const result = paneManager.getPaneNumber(test.input);
    if (result === test.expected) {
      passCount++;
    } else {
      console.log(`   ⚠️ ${test.input} -> ${result} (expected ${test.expected})`);
    }
  });
  
  if (passCount === testCases.length) {
    console.log('✅ Test 3: Pane number conversion - PASS');
  } else {
    console.log(`⚠️ Test 3: Pane number conversion - PARTIAL (${passCount}/${testCases.length})`);
  }
} catch (error) {
  console.log('❌ Test 3: Pane number conversion - FAIL');
  console.error(error.message);
}

// Test 4: Available layouts
try {
  const paneManager = new PaneConfigManager(process.cwd(), 'test-session');
  const layouts = paneManager.getAvailableLayouts();
  if (layouts && layouts.length > 0) {
    console.log('✅ Test 4: Available layouts - PASS');
    console.log(`   Found ${layouts.length} layouts: ${layouts.map(l => l.name).join(', ')}`);
  } else {
    console.log('⚠️ Test 4: Available layouts - NO LAYOUTS FOUND');
  }
} catch (error) {
  console.log('❌ Test 4: Available layouts - FAIL');
  console.error(error.message);
}

console.log('\n🎯 Test Summary Complete');