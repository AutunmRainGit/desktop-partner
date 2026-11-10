import { build } from 'vite'
import vue from '@vitejs/plugin-vue'
import { mkdir, writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const root = path.dirname(fileURLToPath(import.meta.url))
const result = await build({
  root, configFile: false, plugins: [vue()],
  define: { 'process.env.NODE_ENV': JSON.stringify('production') },
  build: {
    write: false, cssCodeSplit: false,
    lib: { entry: path.join(root, 'src/main.js'), name: 'PetMenu', formats: ['iife'] },
  },
})
const files = (Array.isArray(result) ? result : [result]).flatMap(item => item.output)
const js = files.filter(item => item.type === 'chunk').map(item => item.code).join('\n')
const css = files.filter(item => item.fileName.endsWith('.css')).map(item => item.source).join('\n')
// 单文件，无 CDN、开发服务器或外部资源，适用于 load_html 和导出的 PCK。
const html = `<!doctype html><html lang="zh-CN"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; connect-src 'none'; base-uri 'none'; form-action 'none'">
<title>伙伴菜单</title><style>${css}</style></head><body><div id="app"></div>
<script>${js.replace(/<\/script/gi, '<\\/script')}</script></body></html>`
const target = path.resolve(root, '../../resources/ui/pet-menu')
await mkdir(target, { recursive: true })
await writeFile(path.join(target, 'index.html'), html)
console.log(`Offline menu: ${path.join(target, 'index.html')} (${Buffer.byteLength(html)} bytes)`)
