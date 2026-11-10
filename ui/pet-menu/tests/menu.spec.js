import { test, expect } from '@playwright/test'
import { pathToFileURL, fileURLToPath } from 'node:url'

const target = pathToFileURL(fileURLToPath(new URL('../../../resources/ui/pet-menu/index.html', import.meta.url))).href
async function load(page, handshake = true) {
  await page.addInitScript(({ handshake }) => {
    window.sent = []
    window.menuState = { is_sleeping: true, status_bar_visible: true, health: 100, max_health: 100, satiety: 97, max_satiety: 100, level: 4, experience: 2, required_exp: 8, is_max_level: false, is_dead: false }
    window.reply = message => document.dispatchEvent(new CustomEvent('message', { detail: JSON.stringify(message) }))
    window.ipc = { postMessage(raw) {
      const message = JSON.parse(raw)
      window.sent.push(message)
      if (handshake && message.type === 'ready') window.reply({ type: 'initial_state', state: window.menuState })
    } }
  }, { handshake })
  await page.goto(target)
}

test('离线加载、握手和只读教程', async ({ page }) => {
  const network = []
  page.on('request', request => { if (/^https?:/.test(request.url())) network.push(request.url()) })
  await load(page)
  await expect(page.locator('[data-action="sleep"]')).toContainText('唤醒')
  await page.locator('[data-action="tutorial"]').click()
  await expect(page.getByRole('heading')).toHaveText('相处小指南')
  await expect(page.locator('.tutorial')).toContainText('第一次只唤醒')
  await page.waitForTimeout(600)
  await expect(page.getByRole('heading')).toHaveText('相处小指南')
  expect(await page.evaluate(() => window.sent.filter(x => x.type === 'action'))).toEqual([])
  expect(network).toEqual([])
})

test('喂食发送动作并展示实际仅唤醒结果', async ({ page }) => {
  await load(page)
  await page.locator('[data-action="feed_bread"]').click()
  expect(await page.evaluate(() => window.sent.at(-1))).toEqual({ type: 'action', id: '1', action: 'feed_bread', params: {} })
  await page.evaluate(() => window.reply({ type: 'action_result', id: '1', status: 'woke_up', message: '已唤醒', state: { is_sleeping: false, status_bar_visible: true } }))
  await expect(page.getByRole('status')).toHaveText('已唤醒')
  await expect(page.locator('[data-action="sleep"]')).toContainText('睡眠')
})

test('显隐提交明确布尔目标值，状态变化实时更新', async ({ page }) => {
  await load(page)
  await page.locator('[data-action="status"]').click()
  expect(await page.evaluate(() => window.sent.at(-1).params)).toEqual({ visible: false })
  await page.evaluate(() => window.reply({ type: 'action_result', id: '1', status: 'success', message: '已隐藏状态栏', state: { is_sleeping: true, status_bar_visible: false } }))
  await expect(page.locator('[data-action="status"]')).toContainText('显示状态栏')
  await page.evaluate(() => window.reply({ type: 'state', state: { is_sleeping: false, status_bar_visible: false } }))
  await expect(page.locator('[data-action="sleep"]')).toContainText('睡眠')
  await page.locator('[data-action="sleep"]').click()
  expect(await page.evaluate(() => window.sent.at(-1).action)).toBe('start_sleep')
})

test('握手前禁用养成操作，教程和关闭仍可用', async ({ page }) => {
  await load(page, false)
  await expect(page.locator('[data-action="feed_bread"]')).toBeDisabled()
  await page.locator('[data-action="tutorial"]').click()
  await expect(page.locator('.tutorial')).toBeVisible()
  await page.keyboard.press('Escape')
  expect(await page.evaluate(() => window.sent.at(-1))).toEqual({ type: 'close' })
})

test('聚焦按钮后Esc关闭，卡片不溢出', async ({ page }) => {
  await load(page)
  await page.locator('[data-action="feed_bread"]').focus()
  await page.keyboard.press('Escape')
  expect(await page.evaluate(() => window.sent.at(-1))).toEqual({ type: 'close' })
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= 304 && document.documentElement.scrollHeight <= 360 && document.querySelector('.card').scrollHeight <= document.querySelector('.card').clientHeight)).toBe(true)
  // 只在截图测试中加入壁纸，生产页面背景始终透明。
  await page.addStyleTag({ content: 'html{background:radial-gradient(ellipse at 10% 35%,#afc9e4 0,transparent 65%),linear-gradient(135deg,#edf3fc,#e9e9f1 65%,#f6e9dc)}' })
  await page.locator('[data-action="feed_bread"]').hover()
  await page.screenshot({ path: '../../ai/work/menu-browser-results/pet-menu-v3.png' })
})

test('实时状态、升级阈值与MAX均由Godot快照驱动', async ({ page }) => {
  await load(page)
  await expect(page.locator('.level')).toHaveText('Lv.4')
  await expect(page.getByRole('progressbar', { name: '生命', exact: true })).toHaveAttribute('aria-valuetext', '100/100')
  await expect(page.getByRole('progressbar', { name: '饱食', exact: true })).toHaveAttribute('aria-valuetext', '97/100')
  await expect(page.getByRole('progressbar', { name: 'EXP', exact: true })).toHaveAttribute('aria-valuetext', '2/8')
  await page.evaluate(() => window.reply({ type: 'state', state: { ...window.menuState, level: 10, experience: 0, required_exp: 0, is_max_level: true, health: 42, satiety: 12 } }))
  await expect(page.locator('.level')).toHaveText('Lv.10')
  await expect(page.getByRole('progressbar', { name: 'EXP', exact: true })).toHaveAttribute('aria-valuetext', 'MAX')
  await expect(page.getByRole('progressbar', { name: '生命', exact: true })).toHaveAttribute('aria-valuetext', '42/100')
  await page.evaluate(() => window.reply({ type: 'state', state: { ...window.menuState, is_dead: true, is_sleeping: false, health: 0 } }))
  await expect(page.locator('.presence')).toHaveText('已死亡')
})

test('玻璃背景透明，教程在紧凑窗口中不溢出', async ({ page }) => {
  await load(page)
  expect(await page.evaluate(() => getComputedStyle(document.body).backgroundColor)).toBe('rgba(0, 0, 0, 0)')
  expect(await page.locator('.card').evaluate(el => getComputedStyle(el).backdropFilter)).toContain('blur')
  await page.locator('[data-action="tutorial"]').click()
  expect(await page.locator('.card').evaluate(el => el.scrollHeight <= el.clientHeight)).toBe(true)
})
