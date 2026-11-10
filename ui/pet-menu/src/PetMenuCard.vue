<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'
import MenuIcon from './MenuIcon.vue'

const state = ref({ is_sleeping: false, status_bar_visible: true })
const connected = ref(false)
const tutorial = ref(false)
const pending = ref(null)
const feedback = ref('正在连接…')
const presence = computed(() => !connected.value ? '连接中' : state.value.is_dead ? '已死亡' : state.value.is_sleeping ? '睡眠中' : '清醒')
const meters = computed(() => [
  { label: '生命', value: state.value.health, max: state.value.max_health },
  { label: '饱食', value: state.value.satiety, max: state.value.max_satiety },
  { label: 'EXP', value: state.value.experience, max: state.value.required_exp, isMax: state.value.is_max_level },
])
let counter = 0
let timer
let pendingTimer

function progress(meter) {
  if (meter.isMax) return 100
  return Number.isFinite(meter.value) && meter.max > 0 ? Math.max(0, Math.min(100, meter.value / meter.max * 100)) : 0
}
function meterText(meter) {
  if (!connected.value || !Number.isFinite(meter.value)) return '—'
  return meter.isMax ? 'MAX' : `${meter.value}/${meter.max}`
}
function send(message) { window.ipc?.postMessage(JSON.stringify(message)) }
function applyState(value) {
  if (typeof value?.is_sleeping === 'boolean' && typeof value?.status_bar_visible === 'boolean') {
    state.value = { ...state.value, ...value }
  }
}
function receive(event) {
  let message
  const data = event.detail ?? event.data
  try { message = typeof data === 'string' ? JSON.parse(data) : data } catch { return }
  if (message?.type === 'state' || message?.type === 'initial_state') {
    applyState(message.state)
    if (message.type === 'initial_state') {
      connected.value = true
      tutorial.value = false
      feedback.value = ''
      clearInterval(timer)
    }
  } else if (message?.type === 'action_result' && message.id === pending.value) {
    applyState(message.state)
    feedback.value = message.message
    pending.value = null
    clearTimeout(pendingTimer)
  } else if (message?.type === 'error') {
    feedback.value = message.message || '操作未能完成'
    pending.value = null
    clearTimeout(pendingTimer)
  }
}
function act(action, params = {}) {
  if (!connected.value || pending.value) return
  const id = String(++counter)
  pending.value = id
  pendingTimer = setTimeout(() => {
    pending.value = null
    feedback.value = '暂未收到结果'
  }, 5000)
  send({ type: 'action', id, action, params })
}
function close() { send({ type: 'close' }) }
function keydown(event) {
  if (event.key === 'Escape') { event.preventDefault(); close() }
}
function preventContext(event) { event.preventDefault() }
onMounted(() => {
  window.addEventListener('message', receive)
  document.addEventListener('message', receive)
  window.addEventListener('keydown', keydown, true)
  document.addEventListener('contextmenu', preventContext)
  timer = setInterval(() => send({ type: 'ready' }), 500)
  send({ type: 'ready' })
})
onUnmounted(() => {
  clearInterval(timer)
  clearTimeout(pendingTimer)
  window.removeEventListener('message', receive)
  document.removeEventListener('message', receive)
  window.removeEventListener('keydown', keydown, true)
  document.removeEventListener('contextmenu', preventContext)
})
</script>

<template>
  <main class="card" aria-label="桌面伙伴操作菜单">
    <header>
      <h1>{{ tutorial ? '相处小指南' : '桌面伙伴' }}</h1>
      <span v-if="!tutorial" class="level">{{ connected ? `Lv.${state.level ?? 1}` : '—' }}</span>
    </header>
    <template v-if="!tutorial">
      <p class="presence" :class="{ sleeping: state.is_sleeping, dead: state.is_dead }"><span class="dot"></span>{{ presence }}</p>
      <section class="meters" aria-label="角色实时状态">
        <div v-for="meter in meters" :key="meter.label" class="meter">
          <span class="meter-label">{{ meter.label }}</span>
          <span class="track" role="progressbar" :aria-label="meter.label" :aria-valuenow="meter.isMax ? 100 : meter.value ?? 0" :aria-valuemax="meter.isMax ? 100 : meter.max || 100" :aria-valuetext="meterText(meter)"><span :style="{ width: `${progress(meter)}%` }"></span></span>
          <span class="meter-value">{{ meterText(meter) }}</span>
        </div>
      </section>
      <div class="divider"></div>
      <nav aria-label="伙伴操作">
        <button data-action="feed_bread" :disabled="!connected || !!pending" :title="state.is_sleeping ? '这次只唤醒，再次操作才喂食' : '恢复30点饱食度'" @click="act('feed_bread')"><MenuIcon name="bread"/><span>喂面包</span><kbd>F</kbd></button>
        <button data-action="sleep" :disabled="!connected || !!pending" @click="act(state.is_sleeping ? 'wake_up' : 'start_sleep')"><MenuIcon :name="state.is_sleeping ? 'sun' : 'moon'"/><span>{{ state.is_sleeping ? '唤醒' : '睡眠' }}</span><kbd>{{ state.is_sleeping ? 'W' : 'S' }}</kbd></button>
        <button data-action="tutorial" @click="tutorial = true"><MenuIcon name="book"/><span>教程</span><MenuIcon class="trailing" name="chevron"/></button>
        <button data-action="status" :disabled="!connected || !!pending" @click="act('set_status_bar_visible', { visible: !state.status_bar_visible })"><MenuIcon name="monitor"/><span>{{ state.status_bar_visible ? '隐藏状态栏' : '显示状态栏' }}</span><MenuIcon v-if="state.status_bar_visible" class="trailing" name="check"/></button>
      </nav>
    </template>
    <section v-else class="tutorial">
      <p><b>点击</b><span>回应伙伴，每日最多获得1点经验。</span></p>
      <p><b>拖动</b><span>按住角色移动，松开不会触发点击。</span></p>
      <p><b>喂食</b><span>面包恢复30点饱食度。睡眠时第一次只唤醒，再次操作才喂食。</span></p>
      <p><b>睡眠</b><span>23:00自动入睡，07:00醒来，也可以主动安排休息。</span></p>
      <p class="shortcuts">F 喂食 · S 睡眠 · W 唤醒</p>
      <button data-action="back" class="back" @click="tutorial = false"><MenuIcon name="back"/>返回菜单</button>
    </section>
    <footer><span class="escape">Esc 关闭</span><span class="feedback" role="status" aria-live="polite">{{ feedback }}</span></footer>
  </main>
</template>

<style>
:root{color-scheme:light;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","Microsoft YaHei",sans-serif;font-size:13px;color:#20242a;font-synthesis:none;-webkit-font-smoothing:antialiased}
*{box-sizing:border-box}html,body,#app{margin:0;width:100%;height:100%;background:transparent}body{padding:8px;user-select:none;overflow:hidden}button{font:inherit;color:inherit;cursor:pointer;-webkit-tap-highlight-color:transparent}button:focus-visible{outline:2px solid #71976a;outline-offset:-2px}button:disabled{opacity:.4;cursor:default}
.card{height:100%;padding:14px 12px 10px;border:1px solid rgba(255,255,255,.82);border-radius:14px;background:linear-gradient(145deg,rgba(255,255,255,.34),rgba(255,255,255,.23));-webkit-backdrop-filter:blur(24px) saturate(1.15);backdrop-filter:blur(24px) saturate(1.15);box-shadow:0 4px 10px rgba(27,35,50,.12),inset 0 1px 0 rgba(255,255,255,.32);display:flex;flex-direction:column;overflow:auto;scrollbar-width:thin}
header{display:flex;align-items:center;justify-content:space-between;padding:0 6px}h1{font-size:16px;line-height:22px;font-weight:600;margin:0;letter-spacing:.1px}.level{font-size:13px;color:#70747c;font-variant-numeric:tabular-nums}.presence{display:flex;align-items:center;gap:6px;color:#68a751;font-size:12px;line-height:16px;margin:6px 6px 14px}.dot{width:6px;height:6px;border-radius:50%;background:currentColor}.sleeping{color:#858da7}.dead{color:#888b91}
.meters{display:grid;gap:10px;padding:0 6px}.meter{display:grid;grid-template-columns:30px minmax(20px,1fr) 53px;align-items:center;gap:9px;font-size:12px;line-height:14px;color:#747780}.meter-value{text-align:right;font-size:11px;font-variant-numeric:tabular-nums;white-space:nowrap}.track{height:5px;border-radius:8px;overflow:hidden;background:rgba(126,139,157,.15)}.track>span{display:block;height:100%;border-radius:inherit;background:#79b958;transition:width .18s ease}.divider{height:1px;flex-shrink:0;background:rgba(112,122,140,.13);margin:15px 6px 6px}
nav{display:grid;gap:1px}nav button{display:flex;align-items:center;gap:11px;width:100%;height:34px;padding:0 10px;border:0;border-radius:7px;background:transparent;text-align:left}nav button:hover:not(:disabled),nav button:focus-visible{background:rgba(107,120,142,.12)}.menu-icon{width:19px;height:19px;flex-shrink:0;stroke-width:1.55}kbd,.trailing{margin-left:auto;color:#727780}kbd{font:inherit;font-size:12px;padding-right:1px}.trailing{width:15px;height:15px;stroke-width:1.6}footer{display:flex;align-items:center;gap:10px;border-top:1px solid rgba(112,122,140,.13);margin:10px 6px 0;padding-top:10px;line-height:15px;color:#81858c;font-size:11px}.escape{white-space:nowrap}.feedback{margin-left:auto;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:#687460;min-width:0}.tutorial{padding:3px 6px;flex:1;font-size:12px;line-height:1.65}.tutorial p{margin:12px 0;display:grid;grid-template-columns:30px 1fr;gap:8px}.tutorial b{font-weight:550}.tutorial .shortcuts{display:block;color:#7a7e86;font-size:11px}.back{display:flex;align-items:center;gap:7px;border:0;border-radius:7px;background:rgba(255,255,255,.25);padding:7px 9px;font-size:12px}.back:hover{background:rgba(107,120,142,.12)}
@media(prefers-reduced-motion:reduce){.track>span{transition:none}}
</style>
