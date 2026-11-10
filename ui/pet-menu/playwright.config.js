import { defineConfig } from '@playwright/test'
export default defineConfig({
  testDir: './tests', workers: 1,
  outputDir: '../../ai/work/menu-browser-results',
  use: {
    browserName: 'chromium', viewport: { width: 304, height: 360 },
    launchOptions: { executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' },
  },
})
