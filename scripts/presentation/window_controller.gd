class_name WindowController
extends Node
## 表现层：桌面窗口控制器。
## 负责无边框/透明/置顶/尺寸，以及鼠标输入路由：区分窗口拖动与宠物点击、悬停检测。
## 不访问存档或领域规则。


signal clicked                  ## 宠物被点击（按下与释放均在宠物上且未构成拖动）
signal hover_changed(over: bool)  ## 鼠标进入/离开宠物区域
signal context_menu_requested(screen_position: Vector2i)


const DEFAULT_SIZE := Vector2i(300, 300)
const SCREEN_SIZE_RATIO := 0.30  ## 窗口边长占屏幕可用区域短边的比例
const MIN_SIZE := 480
const MAX_SIZE := 720
const DRAG_THRESHOLD_PX := 4.0
const DEBUG_INPUT := true  ## 诊断日志开关：定位交互问题后可置 false
const DEBUG_DISABLE_ALWAYS_ON_TOP := true  ## 调试：临时关闭置顶，排查 macOS 拖动不生效
const DEBUG_DISABLE_TRANSPARENT := false   ## 调试：保持透明（false = 透明开启）


var _pet_sprite: AnimatedSprite2D
var _potential_drag := false
var _dragging := false
var _press_position := Vector2.ZERO
var _drag_log_count := 0
var _hovering := false


func setup(pet_sprite: AnimatedSprite2D) -> void:
	_pet_sprite = pet_sprite


## 应用桌面窗口设置（无边框、置顶、透明、尺寸）。
func apply_desktop_settings() -> void:
	var window := get_window()
	if window == null:
		push_error("WindowController: 无法获取窗口")
		return
	window.borderless = true
	window.always_on_top = not DEBUG_DISABLE_ALWAYS_ON_TOP
	window.transparent_bg = not DEBUG_DISABLE_TRANSPARENT
	var usable_rect := DisplayServer.screen_get_usable_rect(window.current_screen)
	var short_side := mini(usable_rect.size.x, usable_rect.size.y)
	if short_side > 0:
		var side := mini(clampi(roundi(short_side * SCREEN_SIZE_RATIO), MIN_SIZE, MAX_SIZE), floori(short_side * 0.9))
		window.size = Vector2i(side, side)
		# 放大后保持整个窗口位于可用桌面内。
		window.position = window.position.clamp(usable_rect.position, usable_rect.end - window.size)
	else:
		window.size = Vector2i(MIN_SIZE, MIN_SIZE)
	window.grab_focus()  # 无边框窗口默认可能不获得键盘焦点，主动请求（否则 F/S/W 无效）


func is_dragging() -> bool:
	return _dragging


## 纯逻辑：按下位置与当前位置是否构成拖动（超过阈值）。
static func is_drag(press: Vector2, current: Vector2, threshold: float = DRAG_THRESHOLD_PX) -> bool:
	return press.distance_to(current) > threshold


## 命中测试：鼠标当前是否落在宠物精灵内（使用精灵局部坐标）。
func is_over_pet() -> bool:
	if _pet_sprite == null:
		return false
	var size := _sprite_size()
	if size == Vector2.ZERO:
		return false
	var local := _pet_sprite.get_local_mouse_position()
	return Rect2(-size / 2.0, size).has_point(local)


func _sprite_size() -> Vector2:
	if _pet_sprite == null or _pet_sprite.sprite_frames == null:
		return Vector2.ZERO
	var frames := _pet_sprite.sprite_frames
	if frames.get_frame_count(_pet_sprite.animation) == 0:
		return Vector2.ZERO
	var tex := frames.get_frame_texture(_pet_sprite.animation, 0)
	return tex.get_size() if tex != null else Vector2.ZERO


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and not _potential_drag and not _dragging and is_over_pet():
			context_menu_requested.emit(DisplayServer.mouse_get_position())
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if DEBUG_INPUT:
			print("[Window] 左键 %s  over_pet=%s" % ["按下" if event.pressed else "释放", str(is_over_pet())])
		if event.pressed:
			_on_press(event.position)
		else:
			_on_release()
	elif event is InputEventMouseMotion:
		_on_motion(event)


func _on_press(viewport_pos: Vector2) -> void:
	if not is_over_pet():
		return
	_potential_drag = true
	_dragging = false
	_press_position = viewport_pos
	if DEBUG_INPUT:
		print("[Window] 命中宠物，开始可能拖动")


func _on_motion(event: InputEventMouseMotion) -> void:
	var over := is_over_pet()
	if over != _hovering:
		_hovering = over
		hover_changed.emit(over)
		if DEBUG_INPUT:
			print("[Window] 悬停变化: over=", over)
	if _potential_drag and not _dragging and is_drag(_press_position, event.position):
		_dragging = true
		_drag_log_count = 0
		if DEBUG_INPUT:
			print("[Window] 开始拖动")
	if _dragging:
		var window := get_window()
		if window != null:
			if DEBUG_INPUT and _drag_log_count < 3:
				print("[Window] 拖动 relative=", event.relative, " 窗口位置=", window.position)
				_drag_log_count += 1
			window.position += Vector2i(event.relative)


func _on_release() -> void:
	var clicked_now := _potential_drag and not _dragging and is_over_pet()
	if DEBUG_INPUT:
		print("[Window] 释放: potential=%s dragging=%s over=%s → %s" % [
			str(_potential_drag), str(_dragging), str(is_over_pet()),
			"点击" if clicked_now else "无点击",
		])
	if clicked_now:
		clicked.emit()
	_potential_drag = false
	_dragging = false
