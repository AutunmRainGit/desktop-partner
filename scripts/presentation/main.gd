class_name Main
extends Node
## 表现层：主入口。创建并持有 GameManager，连接各控制器，负责初始化、周期性时间推进与刷新，
## 并在玩家操作时播放对应的动作动画。不承担具体交互/动画/窗口细节。


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


@onready var _pet: PetController = $PetController
@onready var _interaction: InteractionController = $InteractionController
@onready var _animation: AnimationController = $AnimationController
@onready var _window: WindowController = $WindowController


func _ready() -> void:
	_window.apply_desktop_settings()
	_center_pet()
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
				_do_feed()
			KEY_SLEEP:
				_do_sleep()
			KEY_WAKE:
				_do_wake()


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


# --- 交互（经 InteractionController，统一反馈 + 动画 + 刷新） ---

func _on_pet_clicked() -> void:
	var result := _interaction.handle_click(_now())
	if DEBUG_ACTIONS:
		var st := _game.get_state()
		print("[Main] 收到 clicked，结果=", result, " 状态(is_dead=%s, sleeping=%s, last_exp_date=%s)" % [str(st.is_dead), str(_game.get_sleep().is_sleeping()), st.last_exp_date])
	var fb := _feedback_text(result)
	if result == GameManager.ActionResult.REJECTED:
		var st := _game.get_state()
		if st != null and not st.is_dead and st.last_exp_date == TimeUtils.local_date_str(_now()):
			fb = "今天已获得经验"
	_show_feedback(fb)
	match result:
		GameManager.ActionResult.LEVELED_UP:
			_animation.play_action(AnimationController.ANIM_LEVEL_UP)
		GameManager.ActionResult.WOKE_UP:
			_animation.play_action(AnimationController.ANIM_STOP_SLEEP)
	_refresh()


func _do_feed() -> void:
	var result := _interaction.handle_feed(_now())
	if DEBUG_ACTIONS:
		print("[Main] 喂食结果=", result)
	_show_feedback(_feedback_text(result))
	if result == GameManager.ActionResult.DONE:
		_animation.play_action(AnimationController.ANIM_EAT_BREAD)
	_refresh()


func _do_sleep() -> void:
	var ok := _interaction.handle_sleep(_now())
	if DEBUG_ACTIONS:
		print("[Main] 睡眠结果=", ok)
	_show_feedback("已入睡" if ok else "无法入睡")
	if ok:
		_animation.play_action(AnimationController.ANIM_START_SLEEP)
	_refresh()


func _do_wake() -> void:
	var ok := _interaction.handle_wake(_now())
	if DEBUG_ACTIONS:
		print("[Main] 唤醒结果=", ok)
	_show_feedback("已唤醒" if ok else "未在睡眠")
	if ok:
		_animation.play_action(AnimationController.ANIM_STOP_SLEEP)
	_refresh()


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
