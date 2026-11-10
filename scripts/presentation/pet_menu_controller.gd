class_name PetMenuController
extends Node
## 唯一 WebView 桥接边界。只接受固定消息和显式参数，不执行网页提供的代码。

signal menu_failed(message: String)
signal bridge_message_sent(message: Dictionary)

const HTML_PATH := "res://resources/ui/pet-menu/index.html"
const EXTENSION_PATH := "res://addons/godot_wry/WRY.gdextension"
const ACTIONS := {
	"feed_bread": Main.Action.FEED_BREAD,
	"start_sleep": Main.Action.START_SLEEP,
	"wake_up": Main.Action.WAKE_UP,
	"set_status_bar_visible": Main.Action.SET_STATUS_BAR_VISIBLE,
}

var _main: Main
var _ready_received := false
var _generation := 0
var _history: Dictionary = {}
var is_open := false
var _server := TCPServer.new()
var _peer: StreamPeerTCP
var _authenticated := false
var _token := ""
var _buffer := PackedByteArray()
var _pid := -1
var _placement: Dictionary = {}
var _connection_deadline := 0


func _exit_tree() -> void:
	_stop_host()


func setup(main: Main) -> void:
	if _main == main:
		return
	if is_instance_valid(_main) and _main.menu_state_changed.is_connected(_on_menu_state_changed):
		_main.menu_state_changed.disconnect(_on_menu_state_changed)
	_main = main
	_main.menu_state_changed.connect(_on_menu_state_changed)


func open_menu(main: Main, screen_position: Vector2i) -> bool:
	setup(main)
	if not FileAccess.file_exists(HTML_PATH):
		return _fail("缺少本地菜单构建产物")
	if not _host_available():
		return _fail("Godot WRY 扩展不可用")
	var screen := DisplayServer.get_screen_from_rect(Rect2i(screen_position, Vector2i.ONE))
	var usable := DisplayServer.screen_get_usable_rect(screen)
	# Godot/WRY窗口尺寸为物理像素，HTML布局使用CSS像素。
	# Retina上304物理像素只有152 CSS像素，必须按屏幕倍率换算。
	var scale := maxf(1.0, DisplayServer.screen_get_scale(screen))
	var menu_size := Vector2i(mini(roundi(304 * scale), usable.size.x), mini(roundi(360 * scale), usable.size.y))
	var menu_position := fit_position(screen_position, menu_size, usable)
	_placement = {"type": "open", "x": menu_position.x, "y": menu_position.y, "width": menu_size.x, "height": menu_size.y}
	is_open = true
	if _pid < 0 or not OS.is_process_running(_pid):
		_stop_host()
		is_open = true
		_ready_received = false
		_history.clear()
		_token = Crypto.new().generate_random_bytes(24).hex_encode()
		var port := 0
		for attempt in range(16):
			port = randi_range(30000, 60000)
			if _server.listen(port, "127.0.0.1") == OK:
				break
		if not _server.is_listening():
			return _fail("无法建立本机菜单通道")
		# WRY 1.0.2绑定主窗口，因此让独立菜单场景拥有自己的主窗口。
		# 菜单子进程不创建GameManager，不读写宠物存档。
		var args := PackedStringArray()
		if OS.has_feature("editor"):
			args.append_array(["--path", ProjectSettings.globalize_path("res://")])
		args.append_array(["--resolution", "%dx%d" % [menu_size.x, menu_size.y], "--position", "%d,%d" % [menu_position.x, menu_position.y], "--log-file", "user://logs/pet_menu.log", "res://scenes/pet_menu.tscn", "--", "--pet-menu-port=%d" % port, "--pet-menu-token=" + _token])
		_pid = _create_host_process(args)
		if _pid < 0:
			return _fail("无法启动菜单窗口")
	elif _ready_received:
		_send(_placement)
		_send({"type": "initial_state", "state": _main.get_menu_state()})
	_generation += 1
	var generation := _generation
	get_tree().create_timer(12.0).timeout.connect(func():
		if generation == _generation and is_open and not _ready_received:
			_fail("Vue 菜单握手超时")
	)
	return true


func _host_available() -> bool:
	return DisplayServer.get_name() != "headless" and FileAccess.file_exists(EXTENSION_PATH)


func _create_host_process(args: PackedStringArray) -> int:
	return OS.create_process(OS.get_executable_path(), args)


static func fit_position(anchor: Vector2i, menu_size: Vector2i, usable: Rect2i) -> Vector2i:
	var target := anchor + Vector2i(16, 8)
	if target.x + menu_size.x > usable.end.x:
		target.x = anchor.x - menu_size.x - 16
	return target.clamp(usable.position, (usable.end - menu_size).max(usable.position))


func close_menu() -> void:
	_generation += 1
	is_open = false
	_send({"type": "close"})


func _stop_host() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	if _peer != null:
		_peer.disconnect_from_host()
	_peer = null
	_server.stop()
	_authenticated = false
	_ready_received = false
	_buffer.clear()


func _process(_delta: float) -> void:
	if _pid > 0 and not OS.is_process_running(_pid):
		var was_open := is_open
		_stop_host()
		if was_open:
			_fail("菜单进程已退出")
	if _server.is_connection_available():
		var candidate := _server.take_connection()
		if _peer == null:
			_peer = candidate
			_connection_deadline = Time.get_ticks_msec() + 2000
		else:
			candidate.disconnect_from_host()
	if _peer == null:
		return
	_peer.poll()
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or (not _authenticated and Time.get_ticks_msec() > _connection_deadline):
		_peer.disconnect_from_host()
		_peer = null
		_authenticated = false
		_buffer.clear()
		return
	var count := _peer.get_available_bytes()
	if count > 0:
		if count + _buffer.size() > 8192:
			_fail("菜单通道消息过长")
			return
		_buffer.append_array(_peer.get_data(count)[1])
	while _buffer.has(10):
		var end := _buffer.find(10)
		var line := _buffer.slice(0, end).get_string_from_utf8()
		_buffer = _buffer.slice(end + 1)
		if not _authenticated:
			var hello = JSON.parse_string(line)
			if typeof(hello) == TYPE_DICTIONARY and hello.get("type") == "hello" and hello.get("token") == _token:
				_authenticated = true
			else:
				_peer.disconnect_from_host()
				_peer = null
				_buffer.clear()
				return
		elif line == '{"type":"closed"}':
			is_open = false
		elif line.begins_with('{"type":"host_error"'):
			_fail("原生 WebView 加载失败")
			return
		else:
			_on_ipc_message(line)


func _fail(message: String) -> bool:
	close_menu()
	_stop_host()
	menu_failed.emit(message)
	return false


func _on_ipc_message(raw: String) -> void:
	var response := handle_message(raw)
	if not response.is_empty():
		_send(response)
		if response.get("type") == "initial_state" and not is_open:
			_send({"type": "close"})


## 返回固定字段响应，便于独立测试校验与分派，不依赖原生 WebView。
func handle_message(raw: String) -> Dictionary:
	if raw.length() > 4096:
		return _error("消息过长")
	var parser := JSON.new()
	if parser.parse(raw) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return _error("消息格式无效")
	var message: Dictionary = parser.data
	if typeof(message.get("type")) != TYPE_STRING:
		return _error("消息类型无效")
	if not is_instance_valid(_main):
		return _error("角色尚未连接")
	match message.type:
		"ready":
			if message.size() != 1:
				return _error("握手参数无效")
			_ready_received = true
			return {"type": "initial_state", "state": _main.get_menu_state()}
		"close":
			if message.size() != 1:
				return _error("关闭参数无效")
			close_menu()
			return {}
		"action":
			return _handle_action(message)
	return _error("未知消息类型")


func _handle_action(message: Dictionary) -> Dictionary:
	if not _ready_received:
		return _error("请先完成握手")
	if message.size() != 4 or typeof(message.get("id")) != TYPE_STRING or message.id.is_empty() or message.id.length() > 64:
		return _error("操作编号无效")
	if typeof(message.get("action")) != TYPE_STRING or not ACTIONS.has(message.action) or typeof(message.get("params")) != TYPE_DICTIONARY:
		return _error("操作或参数无效")
	if _history.has(message.id):
		# 相同编号重试不能重复喂食，也不能将旧编号用于另一操作。
		var previous: Dictionary = _history[message.id]
		if previous.request != message:
			return _error("操作编号已使用")
		var replay: Dictionary = previous.response.duplicate(true)
		replay.state = _main.get_menu_state()
		return replay
	var result := _main.dispatch_action(ACTIONS[message.action], message.params)
	var response := {"type": "action_result", "id": message.id, "status": result.status, "message": result.message, "state": result.state}
	if _history.size() >= 128:
		_history.erase(_history.keys()[0])
	_history[message.id] = {"request": message.duplicate(true), "response": response.duplicate(true)}
	return response


func _error(message: String) -> Dictionary:
	return {"type": "error", "status": "rejected", "message": message}


func _on_menu_state_changed(state: Dictionary) -> void:
	if is_open and _ready_received:
		_send({"type": "state", "state": state})


func _send(message: Dictionary) -> void:
	bridge_message_sent.emit(message.duplicate(true))
	if _peer != null and _authenticated:
		var bytes := (JSON.stringify(message) + "\n").to_utf8_buffer()
		_peer.put_data(bytes)
