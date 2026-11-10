extends Control
## 独立菜单进程的主场景。只承载本地Vue，不加载宠物业务或存档。

const HTML_PATH := "res://resources/ui/pet-menu/index.html"
const EXTENSION_PATH := "res://addons/godot_wry/WRY.gdextension"
var _peer := StreamPeerTCP.new()
var _buffer := PackedByteArray()
var _token := ""
var _port := 0
var _webview: Control
var _connected := false
var _start_time := 0
var _closing := false
var _native_glass: RefCounted
var native_glass_active := false


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--pet-menu-port="):
			_port = argument.get_slice("=", 1).to_int()
		elif argument.begins_with("--pet-menu-token="):
			_token = argument.get_slice("=", 1)
	if _port < 1 or _token.is_empty():
		get_tree().quit(1)
		return
	var window := get_window()
	window.title = "伙伴菜单"
	window.borderless = true
	window.unresizable = true
	window.always_on_top = true
	window.transparent_bg = true
	window.close_requested.connect(_close)
	window.focus_exited.connect(_close)
	window.window_input.connect(_on_window_input)
	Engine.max_fps = 30
	_start_time = Time.get_ticks_msec()
	if _peer.connect_to_host("127.0.0.1", _port) != OK:
		get_tree().quit(1)


func _process(_delta: float) -> void:
	_peer.poll()
	if not _connected:
		if _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			_connected = true
			_send({"type": "hello", "token": _token})
			_create_webview()
		elif Time.get_ticks_msec() - _start_time > 10000:
			get_tree().quit(1)
		return
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		get_tree().quit()
		return
	var count := _peer.get_available_bytes()
	if count > 0:
		if count + _buffer.size() > 16384:
			get_tree().quit(1)
			return
		_buffer.append_array(_peer.get_data(count)[1])
	while _buffer.has(10):
		var end := _buffer.find(10)
		var line := _buffer.slice(0, end).get_string_from_utf8()
		_buffer = _buffer.slice(end + 1)
		var message = JSON.parse_string(line)
		if typeof(message) != TYPE_DICTIONARY:
			continue
		if message.get("type") == "close":
			_close()
		elif message.get("type") == "open":
			_closing = false
			get_window().position = Vector2i(message.x, message.y)
			get_window().size = Vector2i(message.width, message.height)
			get_window().grab_focus()
			_webview.call("focus")
		else:
			_webview.call("post_message", line)


func _create_webview() -> void:
	if not ClassDB.class_exists("WebView"):
		GDExtensionManager.load_extension(EXTENSION_PATH)
	if not ClassDB.class_exists("WebView") or not FileAccess.file_exists(HTML_PATH):
		_send({"type": "host_error"})
		get_tree().quit(1)
		return
	_webview = ClassDB.instantiate("WebView") as Control
	if _webview == null:
		_send({"type": "host_error"})
		get_tree().quit(1)
		return
	_webview.set("url", "")
	_webview.set("html", FileAccess.get_file_as_string(HTML_PATH))
	_webview.set("full_window_size", true)
	_webview.set("transparent", true)
	_webview.set("forward_input_events", false)
	_webview.set("devtools", false)
	_webview.set("data_directory", "user://pet_menu_webview")
	_webview.connect("ipc_message", _on_ipc_message)
	add_child(_webview)
	_webview.call("focus")
	_apply_native_glass.call_deferred()


func _apply_native_glass() -> void:
	# 真正的窗口外模糊交给OS；CSS backdrop-filter只处理WebView内部。
	if OS.get_name() != "macOS":
		return
	var extension := "res://addons/desktop_glass/desktop_glass.gdextension"
	var binary := "res://addons/desktop_glass/bin/libdesktop_glass.macos.dylib"
	if not FileAccess.file_exists(extension) or not FileAccess.file_exists(binary):
		return
	if not ClassDB.class_exists("DesktopGlass"):
		GDExtensionManager.load_extension(extension)
	if ClassDB.class_exists("DesktopGlass"):
		_native_glass = ClassDB.instantiate("DesktopGlass") as RefCounted
		if _native_glass != null:
			native_glass_active = _native_glass.call("apply", DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, get_window().get_window_id()))


func _on_ipc_message(raw: String) -> void:
	if raw.length() <= 4096 and not raw.contains("\n"):
		_peer.put_data((raw + "\n").to_utf8_buffer())


func _on_window_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close()


func _close() -> void:
	if _closing:
		return
	_closing = true
	_send({"type": "closed"})
	# 给本机通道一个短暂的排空窗口，父进程可区分正常关闭和崩溃。
	get_tree().create_timer(0.15).timeout.connect(get_tree().quit)


func _send(message: Dictionary) -> void:
	_peer.put_data((JSON.stringify(message) + "\n").to_utf8_buffer())
