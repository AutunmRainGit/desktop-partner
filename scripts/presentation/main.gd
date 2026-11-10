class_name Main
extends Node
## 表现层：主入口。创建并持有 GameManager，连接各控制器，负责初始化、周期性时间推进与刷新，
## 并在玩家操作时播放对应的动作动画。不承担具体交互/动画/窗口细节。


signal menu_state_changed(state: Dictionary)

enum Action { FEED_BREAD, START_SLEEP, WAKE_UP, SET_STATUS_BAR_VISIBLE }

const SAVE_PATH := "user://desktop_partner/save.json"
const CONFIG_PATH := "res://resources/character_config.tres"
const CHARACTER_FRAMES_PATH := "res://resources/animate/character_frames.tres"
const SETTLE_INTERVAL_SECONDS := 1

# 键盘操作入口（临时：项目尚无道具栏 UI）
const KEY_FEED := KEY_F
const KEY_SLEEP := KEY_S
const KEY_WAKE := KEY_W
const DEBUG_ACTIONS := true  ## 诊断日志开关：定位交互问题后可置 false


var _game: GameManager
var _displayed_level := 0
var _last_menu_state: Dictionary = {}
var _pet_menu: Node


@onready var _pet: PetController = $PetController
@onready var _interaction: InteractionController = $InteractionController
@onready var _animation: AnimationController = $AnimationController
@onready var _window: WindowController = $WindowController


func _ready() -> void:
	_window.apply_desktop_settings()
	_center_pet()
	get_window().size_changed.connect(_center_pet)
	_pet.set_sprite_frames(_load_frames())
	_setup_game()
	_wire_controllers()

	var result := _game.initialize(_now())
	if not result.ok:
		push_error("Main: 初始化失败：%s" % _init_error_text(result.error))
		return
	_refresh()
	if DEBUG_ACTIONS:
		var st := _game.get_state()
		print("[Main] 初始化完成：is_new=%s is_dead=%s satiety=%d health=%d level=%d sleep_type=%s" % [
			str(result.is_new), str(st.is_dead), st.satiety, st.health, st.level, str(st.sleep_type)])


func _process(_delta: float) -> void:
	if _game == null or not _game.is_initialized():
		return
	# 周期性结算（按系统时间戳，不受帧率影响）；避免每帧保存。
	if _now() - _game.get_state().last_settlement_timestamp >= SETTLE_INTERVAL_SECONDS:
		var result := _game.settle(_now())
		if result.forage_count > 0:
			_animation.play_action(AnimationController.ANIM_EAT_LEAF)
		_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if _game == null or not _game.is_initialized():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if DEBUG_ACTIONS:
			print("[Main] 收到按键: ", event.keycode)
		match event.keycode:
			KEY_FEED:
				dispatch_action(Action.FEED_BREAD)
			KEY_SLEEP:
				dispatch_action(Action.START_SLEEP)
			KEY_WAKE:
				dispatch_action(Action.WAKE_UP)


# --- 初始化 ---

func _setup_game() -> void:
	var config := GameManager.load_default_config()
	if config == null:
		config = CharacterConfig.new()
	var save := SaveManager.new(SAVE_PATH)
	_game = GameManager.new(save, config)


func _wire_controllers() -> void:
	_interaction.setup(_game, _window)
	_animation.setup(_pet.get_sprite(), _game.get_config())
	_window.setup(_pet.get_sprite())
	_window.clicked.connect(_on_pet_clicked)
	_window.hover_changed.connect(_on_hover_changed)
	_window.context_menu_requested.connect(_on_context_menu_requested)


func _on_context_menu_requested(screen_position: Vector2i) -> void:
	# 按需加载独立场景：主场景和快捷键不依赖 WebView 类。
	if not is_instance_valid(_pet_menu):
		var menu_script := load("res://scripts/presentation/pet_menu_controller.gd") as Script
		if menu_script == null:
			_show_feedback("菜单未能加载，仍可使用 F / S / W")
			return
		_pet_menu = menu_script.new()
		add_child(_pet_menu)
		_pet_menu.connect("menu_failed", _on_menu_failed)
	_pet_menu.call("open_menu", self, screen_position)


func _on_menu_failed(message: String) -> void:
	push_warning("PetMenu: " + message)
	_show_feedback("菜单暂不可用，仍可使用 F / S / W")


# --- 交互（经 InteractionController，统一反馈 + 动画 + 刷新） ---

func _on_pet_clicked() -> void:
	var result := _interaction.handle_click(_now())
	if DEBUG_ACTIONS:
		var st := _game.get_state()
		print("[Main] 收到 clicked，结果=", result, " 状态(is_dead=%s, sleeping=%s, last_exp_date=%s)" % [str(st.is_dead), str(_game.get_sleep().is_sleeping()), st.last_exp_date])
	var fb := _feedback_text(result)
	if result == GameManager.ActionResult.REJECTED:
		var st := _game.get_state()
		if st != null and not st.is_dead:
			if _game.get_growth().is_max_level():
				fb = "已达最高等级 MAX"
			elif st.last_exp_date == TimeUtils.local_date_str(_now()):
				fb = "今天已获得经验"
	_show_feedback(fb)
	match result:
		GameManager.ActionResult.WOKE_UP:
			_animation.play_action(AnimationController.ANIM_STOP_SLEEP)
	_refresh()


## 快捷键和菜单共用操作入口；显隐只改变表现，不推进时间或唤醒。
func dispatch_action(action: int, params: Dictionary = {}) -> Dictionary:
	if action == Action.SET_STATUS_BAR_VISIBLE:
		if params.size() != 1 or not params.has("visible") or typeof(params.visible) != TYPE_BOOL or _pet == null:
			return _action_result("rejected", "状态栏参数无效")
		_pet.set_status_bar_visible(params.visible)
		_publish_menu_state()
		return _action_result("success", "已显示状态栏" if params.visible else "已隐藏状态栏")
	if not params.is_empty():
		return _action_result("rejected", "操作参数无效")
	if _game == null or not _game.is_initialized():
		return _action_result("rejected", "角色尚未初始化")
	match action:
		Action.FEED_BREAD:
			return _do_feed()
		Action.START_SLEEP:
			return _do_sleep()
		Action.WAKE_UP:
			return _do_wake()
	return _action_result("rejected", "未知操作")


func get_menu_state() -> Dictionary:
	var snapshot := {
		"is_sleeping": false,
		"status_bar_visible": _pet.is_status_bar_visible() if _pet != null else true,
		"health": 0, "max_health": 0, "satiety": 0, "max_satiety": 0,
		"level": 1, "experience": 0, "required_exp": 0,
		"is_max_level": false, "is_dead": false,
	}
	if _game != null and _game.is_initialized():
		var state := _game.get_state()
		var config := _game.get_config()
		snapshot.merge({
			"is_sleeping": _game.get_sleep().is_sleeping(),
			"health": state.health, "max_health": config.max_health,
			"satiety": state.satiety, "max_satiety": config.max_satiety,
			"level": state.level, "experience": state.experience,
			"required_exp": _game.get_growth().required_exp(state.level),
			"is_max_level": _game.get_growth().is_max_level(), "is_dead": state.is_dead,
		}, true)
	return snapshot


func _publish_menu_state() -> void:
	var state := get_menu_state()
	if state != _last_menu_state:
		_last_menu_state = state.duplicate()
		menu_state_changed.emit(state.duplicate())


func _action_result(status: String, message: String) -> Dictionary:
	return {"status": status, "message": message, "state": get_menu_state()}


func _do_feed() -> Dictionary:
	var result := _interaction.handle_feed(_now())
	if DEBUG_ACTIONS:
		print("[Main] 喂食结果=", result)
	_show_feedback(_feedback_text(result))
	if result == GameManager.ActionResult.DONE:
		_animation.play_action(AnimationController.ANIM_EAT_BREAD)
	elif result == GameManager.ActionResult.WOKE_UP:
		_animation.play_action(AnimationController.ANIM_STOP_SLEEP)
	_refresh()
	var status := "rejected"
	if result == GameManager.ActionResult.DONE:
		status = "success"
	elif result == GameManager.ActionResult.WOKE_UP:
		status = "woke_up"
	return _action_result(status, _feedback_text(result))


func _do_sleep() -> Dictionary:
	var ok := _interaction.handle_sleep(_now())
	if DEBUG_ACTIONS:
		print("[Main] 睡眠结果=", ok)
	_show_feedback("已入睡" if ok else "无法入睡")
	if ok:
		_animation.play_action(AnimationController.ANIM_START_SLEEP)
	_refresh()
	return _action_result("success" if ok else "rejected", "已入睡" if ok else "无法入睡")


func _do_wake() -> Dictionary:
	var ok := _interaction.handle_wake(_now())
	if DEBUG_ACTIONS:
		print("[Main] 唤醒结果=", ok)
	_show_feedback("已唤醒" if ok else "未在睡眠")
	if ok:
		_animation.play_action(AnimationController.ANIM_STOP_SLEEP)
	_refresh()
	return _action_result("success" if ok else "rejected", "已唤醒" if ok else "未在睡眠")


func _on_hover_changed(over: bool) -> void:
	_pet.show_tip(_interaction.sleep_tip() if over else "")


func _show_feedback(text: String) -> void:
	if text != "":
		_pet.flash_feedback(text)


## 操作结果 → 反馈文案；死亡被拒时给出更明确的提示。
func _feedback_text(result: GameManager.ActionResult) -> String:
	if result == GameManager.ActionResult.REJECTED:
		var st := _game.get_state()
		if st != null and st.is_dead:
			return "角色已死亡"
	return InteractionController.action_feedback_text(result)


# --- 刷新 ---

func _refresh() -> void:
	var state := _game.get_state()
	_pet.refresh(state, _game.get_config())
	_animation.set_state(state)
	# 所有操作与定时结算都会刷新，统一捕获点击/觅食（含操作前结算）升级。
	# 初始化首次刷新只展示折算结果，不重播历史升级。
	if _displayed_level > 0 and state.level > _displayed_level:
		_animation.play_action(AnimationController.ANIM_LEVEL_UP)
	_displayed_level = state.level
	_publish_menu_state()


func _load_frames() -> SpriteFrames:
	var frames := load(CHARACTER_FRAMES_PATH) as SpriteFrames
	if frames == null:
		push_warning("Main: 无法加载动画资源：" + CHARACTER_FRAMES_PATH)
	return frames


## 把 PetController（含精灵与状态/提示/反馈标签）整体居中到窗口中心，
## 否则 PetController 位于 (0,0)（左上角），精灵和标签会偏到画面外/最左侧。
func _center_pet() -> void:
	if _pet != null and get_window() != null:
		_pet.position = Vector2(get_window().size) / 2.0
		# 角色、状态和反馈按原始 300×300 布局一起缩放。
		_pet.scale = Vector2.ONE * (float(get_window().size.x) / WindowController.DEFAULT_SIZE.x)
		_pet.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _init_error_text(error: int) -> String:
	match error:
		GameManager.InitError.CONFIG_INVALID:
			return "配置无效"
		GameManager.InitError.SAVE_CORRUPT:
			return "存档损坏"
		GameManager.InitError.SAVE_VERSION_UNSUPPORTED:
			return "存档版本不支持"
		GameManager.InitError.SAVE_FAILED:
			return "保存失败"
	return "未知错误"
