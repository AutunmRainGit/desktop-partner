# 桌宠本地 Vue 菜单

右键命中角色打开卡片。菜单包含喂面包、睡眠／唤醒、教程、状态栏显隐；教程在网页内切换，其他操作经 Main.dispatch_action 执行。

## 运行与构建

仓库中的 `resources/ui/pet-menu/index.html` 是完整构建产物，Vue、脚本和样式均已内联。运行不需要 Node、Vite、CDN、开发服务器或网络连接。修改前端后执行：

```sh
cd ui/pet-menu
npm ci
npm run build
```

`package-lock.json` 锁定构建依赖。前端源目录由 `.gdignore` 排除 Godot 扫描；HTML 位于可导出的资源目录。

## Godot 接口

`Main.Action`：FEED_BREAD、START_SLEEP、WAKE_UP、SET_STATUS_BAR_VISIBLE。

`dispatch_action(action, params)` 返回 `{status, message, state}`。status 为 success、woke_up 或 rejected。状态栏操作必须传 `{visible: bool}`，只改变本次运行中的展示。

`get_menu_state()` 返回 `{is_sleeping: bool, status_bar_visible: bool}`。字段变化时发布 `menu_state_changed`，网页初次握手和重开菜单获取当前快照。

v3还包含health、max_health、satiety、max_satiety、level、experience、required_exp、is_max_level、is_dead。数值直接来自共享状态，升级阈值由GrowthSystem提供；Vue只格式化数值和进度条。隐藏桌宠状态栏不影响菜单数值更新。

## v3 玻璃右键菜单

使用单色SVG线框图标、紧凑菜单行和透明白色圆角表面，顶部展示等级、生命、饱食度及经验，满级显示MAX。教程仍在同一窗口内切换，操作协议不变。

菜单按304×360 CSS像素布局，再根据屏幕倍率换算物理窗口尺寸。在本机Retina 2倍缩放下，实际窗口为608×720物理像素；已实测网页innerWidth=304、innerHeight=360，卡片内容未溢出。不能直接把304物理像素当成304 CSS像素。

窗口与WRY WebView均开启透明。macOS额外使用可选DesktopGlass适配实现真实的窗口后方毛玻璃；参见native/desktop_glass/README.md。Windows原生模糊未编译或验证。

本轮验证：16个Godot测试脚本、608条断言通过；7项浏览器测试通过；21项macOS原生验证通过，包括透明窗口、原生材质、完整卡片、实时数值及全部原有操作。下方最初版本验证记录保留为历史记录。

## 原生窗口适配

Godot WRY v1.0.2 的原生窗口句柄绑定 Godot 主窗口。菜单因此使用同一 Godot 可执行文件的独立场景进程：`scenes/pet_menu.tscn` + `pet_menu_host.gd`。该进程不创建 GameManager、不访问宠物存档。桌宠窗口由 `pet_menu_controller.gd` 管理通道、校验和业务分派。

通道只监听 `127.0.0.1` 的临时端口，用随机会话令牌校验菜单进程。没有远程服务。父进程退出时清理子进程；菜单异常退出或握手失败时保留桌宠和快捷键。

主场景不包含或预加载 WebView 节点。WebView 只在菜单进程中按需实例化。Godot 编辑器仍可能自动发现已安装 GDExtension，因此分发前必须验证原生库自身能够加载；操作系统级的损坏二进制异常不属于 GDScript 能捕获的普通加载失败。

WRY 的网页回传是 `window.ipc.postMessage(JSON.stringify(message))`；Godot 回传通过 `document` 的 `CustomEvent('message').detail`。网页同时兼容标准 MessageEvent。

## 消息协议

- 网页先发送 `{type: 'ready'}`，Godot返回 `{type: 'initial_state', state}`。
- 操作消息为 `{type: 'action', id: string, action: string, params: object}`。
- 只接受 feed_bread、start_sleep、wake_up、set_status_bar_visible。
- 操作响应为 `{type: 'action_result', id, status, message, state}`。
- 后续状态变化为 `{type: 'state', state}`。
- 关闭为 `{type: 'close'}`。
- 不允许任意脚本、文件路径或方法调用；重复请求编号在有限缓存内回放结果，不重复执行。

打开菜单、阅读教程和切换状态栏不会唤醒角色。睡眠中喂面包第一次只唤醒，第二次新操作才喂食。状态栏隐藏后仍更新文本。

## 平台与打包

`addons/godot_wry` 包含官方 v1.0.2 Windows x86_64、macOS universal、Linux x86_64 二进制和 MIT 许可证。

官方包地址：https://github.com/doceazedo/godot_wry/releases/tag/v1.0.2

下载 ZIP 的 SHA-256：706b407aca47df0626df26997a3e825a49c91985a199cead3d0b75d35fca783c。

本机 macOS 框架经过临时签名以用于开发验证。重新下载后如签名异常，可运行 `python3 ai/work/prepare_wry_macos.py`；正式 macOS 分发仍需按发行渠道进行签名和验证。

`export_presets.cfg` 提供 Windows Desktop 和 macOS 预设，并明确包含 HTML。导出前需安装对应 Godot 导出模板。Windows 机器还需可用的系统 WebView2 运行时；本功能不会在启动时联网下载它。没有 WebView2 的机器应验证菜单失败后的快捷键降级。

本机为 macOS Apple Silicon，没有 Windows 执行环境；打包配置不等同于 Windows 实测通过。

## 本次验证记录（2026-11-10）

- Godot无头回归：15个脚本、605条断言通过。
- 离线Vue浏览器测试：5项通过；无HTTP请求，按钮聚焦后Esc能够发送关闭消息。
- macOS原生WRY链路：15项通过，覆盖真实右键命中、四个菜单项、仅唤醒、自然苏醒状态推送、DOM Esc关闭、真实窗口失焦退出及重新打开。
- 无WRY临时项目副本：主场景成功初始化，右键失败被隔离，F快捷键仍恢复30点饱食度。
- Windows预设PCK生成成功，确认收录完整HTML、菜单场景及桥接脚本。PCK检查不等同于Windows可执行程序或WebView2运行验证。
- 尚未验证：Windows/WebView2运行、Windows键盘与高DPI行为、多显示器实机边界、正式签名安装包。macOS原生Esc使用聚焦WebView中的DOM键盘事件验证，未进行物理键盘自动化实测。

日志及截图位于 `ai/work/menu-regression/`、`ai/work/menu-native-parent.log`、`ai/work/menu-native-report.json` 和 `ai/work/menu-browser-results/`。

## 验证命令

```sh
godot --headless --path . --script res://tests/test_main_actions.gd
godot --headless --path . --script res://tests/test_pet_menu_bridge.gd
godot --path . --script res://tests/native_menu_smoke.gd
cd ui/pet-menu
npx playwright test
```

浏览器测试默认复用 macOS 上的 Chrome，可在 playwright.config.js 中调整浏览器路径。原生测试使用独立测试存档，测试脚本不会操作真实宠物存档。测试中的 DOM Esc 检查不等同于 Windows 原生 WebView2 键盘实测。
