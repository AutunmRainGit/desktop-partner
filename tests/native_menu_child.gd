extends SceneTree
## 原生菜单测试子进程；测试专用类消费DOM查询结果，不扩展生产消息协议。

class TestHost extends "res://scripts/presentation/pet_menu_host.gd":
	var samples: Dictionary = {}
	func _on_ipc_message(raw: String) -> void:
		var message = JSON.parse_string(raw)
		if typeof(message) == TYPE_DICTIONARY and message.get("type") == "_qa":
			samples[message.name] = message.value
		else:
			super._on_ipc_message(raw)

var host: Control
var checks: Dictionary = {}
var serial := 0

func _init() -> void:
	_run.call_deferred()

func _until(condition: Callable, seconds := 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return false

func _query(expression: String) -> Variant:
	serial += 1
	var name := str(serial)
	host._webview.call("eval", "window.ipc.postMessage(JSON.stringify({type:'_qa',name:'%s',value:(%s)}))" % [name, expression])
	if not await _until(func(): return host.samples.has(name)):
		return null
	return host.samples[name]

func _click(action: String) -> void:
	host._webview.call("eval", "document.querySelector('[data-action=\"%s\"]').click()" % action)
	await create_timer(0.25).timeout

func _run() -> void:
	host = (load("res://scenes/pet_menu.tscn") as PackedScene).instantiate()
	host.set_script(TestHost)
	root.add_child(host)
	if not await _until(func(): return is_instance_valid(host._webview)):
		checks.webview_created = false
		_finish()
		return
	await create_timer(1.0).timeout
	checks.native_glass = host.native_glass_active
	checks.transparent_window = root.transparent_bg and host._webview.get("transparent")
	if OS.get_cmdline_user_args().has("--pet-menu-test-stage=focus"):
		var phase := FileAccess.open("res://ai/work/menu-native-focus-ready.txt", FileAccess.WRITE)
		phase.store_string("ready")
		phase.close()
		return
	checks.initial_sleep_state = await _query("document.querySelector('[data-action=sleep]').textContent.includes('唤醒')")
	checks.live_health = await _query("document.querySelector('[aria-label=\"生命\"]').getAttribute('aria-valuetext') === '100/100'")
	checks.live_satiety = await _query("document.querySelector('[aria-label=\"饱食\"]').getAttribute('aria-valuetext') === '40/100'")
	print("NATIVE_LAYOUT window=", root.size, " web=", await _query("JSON.stringify({width:innerWidth,height:innerHeight,dpr:devicePixelRatio,cardHeight:document.querySelector('.card').clientHeight,contentHeight:document.querySelector('.card').scrollHeight,cardWidth:document.querySelector('.card').clientWidth})"))
	checks.compact_layout = await _query("document.querySelector('.card').scrollHeight <= document.querySelector('.card').clientHeight")
	await _click("tutorial")
	checks.tutorial = await _query("document.querySelector('h1').textContent === '相处小指南'")
	await _click("back")
	await _click("status")
	checks.status_hidden = await _query("document.querySelector('[data-action=status]').textContent.includes('显示状态栏')")
	await _click("feed_bread")
	checks.feed_only_woke = await _query("document.querySelector('.feedback').textContent === '已唤醒'")
	await _click("feed_bread")
	checks.feed_success = await _query("document.querySelector('.feedback').textContent === '完成'")
	checks.feed_updates_meter = await _query("document.querySelector('[aria-label=\"饱食\"]').getAttribute('aria-valuetext') === '70/100'")
	await _click("sleep")
	checks.sleep = await _query("document.querySelector('[data-action=sleep]').textContent.includes('唤醒')")
	# 父进程在接到sleep结果后推进测试时钟，自然醒来必须更新网页。
	await create_timer(1.2).timeout
	checks.natural_wake_sync = await _query("document.querySelector('[data-action=sleep]').textContent.includes('睡眠')")
	await _click("sleep")
	await _click("sleep")
	checks.wake = await _query("document.querySelector('[data-action=sleep]').textContent.includes('睡眠')")
	_write_report()
	host._webview.call("focus")
	host._webview.call("eval", "document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}))")

func _finish() -> void:
	_write_report()
	quit()

func _write_report() -> void:
	var file := FileAccess.open("res://ai/work/menu-native-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(checks, "\t"))
	file.close()
