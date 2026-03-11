const puppeteer = require('puppeteer');

(async () => {
  const browser = await puppeteer.launch({ headless: "new" });
  const page = await browser.newPage();
  
  // Capture console messages
  page.on('console', msg => {
    console.log(`[BROWSER CONSOLE] ${msg.type().toUpperCase()}:`, msg.text());
  });

  // Capture page errors (uncaught exceptions)
  page.on('pageerror', err => {
    console.error('[BROWSER ERROR]', err.toString());
  });

  console.log('Navigating to http://localhost:8080...');
  try {
    await page.goto('http://localhost:8080', { waitUntil: 'networkidle2', timeout: 15000 });
    console.log('Page loaded. Waiting a few seconds for Flutter to initialize...');
    await new Promise(r => setTimeout(r, 5000));
  } catch (e) {
    console.error('Failed to load page:', e);
  }

  await browser.close();
  console.log('Script finished.');
})();
