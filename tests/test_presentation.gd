extends SceneTree
## 表现层逻辑测试（无头）：验证状态映射、动画映射、交互委派（经真实 GameManager）。
## 窗口透明/拖动等运行时行为需在真实窗口环境验证，不在此测试。
## 运行方式：godot --headless --script res://tests/test_presentation.gd


const TEST_DIR := "user://presentation_tests"

var _passed := 0
var _failed := 0


func _init() -> void:
	_clean_test_dir()

	_test_pet_state_mapping()
	_test_pet_state_text()
	_test_animation_mapping()
	_test_interaction_click_feed()
	_test_interaction_sleep_wake_only()
	_test_interaction_sleep_tip()
	_test_drag_threshold()
	_test_feedback_text()
	_test_frames_resource()
	_test_hungry_weak()

	print("")
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


## 状态 → 展示状态映射
func _test_pet_state_mapping() -> void:
	print("[pres1] 状态映射")
	_check(PetController.describe_state(null) == PetController.STATE_AWAKE, "null → awake")

	var s := PetState.new()
	_check(PetController.describe_state(s) == PetController.STATE_AWAKE, "清醒 → awake")

	s.sleep_type = PetState.SleepType.ACTIVE_SLEEP
	_check(PetController.describe_state(s) == PetController.STATE_SLEEPING, "主动睡眠 → sleeping")

	s.sleep_type = PetState.SleepType.AUTO_SLEEP
	_check(PetController.describe_state(s) == PetController.STATE_SLEEPING, "自动睡眠 → sleeping")

	s.is_dead = true
	_check(PetController.describe_state(s) == PetController.STATE_DEAD, "死亡 → dead（优先）")


## 状态中文文本
func _test_pet_state_text() -> void:
	print("[pres2] 状态文本")
	_check(PetController.state_text(null) == "未知", "null → 未知")
	var s := PetState.new()
	_check(PetController.state_text(s) == "清醒", "清醒文本")
	s.sleep_type = PetState.SleepType.AUTO_SLEEP
	_check(PetController.state_text(s) == "自动睡眠", "自动睡眠文本")
	s.is_dead = true
	_check(PetController.state_text(s) == "已死亡", "死亡文本优先")


## 动画映射
func _test_animation_mapping() -> void:
	print("[pres3] 动画映射")
	_check(AnimationController.state_to_animation(null) == AnimationController.ANIM_IDLE, "null → idle")
	var s := PetState.new()
	_check(AnimationController.state_to_animation(s) == AnimationController.ANIM_IDLE, "清醒 → idle")
	s.sleep_type = PetState.SleepType.ACTIVE_SLEEP
	_check(AnimationController.state_to_animation(s) == AnimationController.ANIM_SLEEP, "睡眠 → sleep")
	s.is_dead = true
	_check(AnimationController.state_to_animation(s) == AnimationController.ANIM_DEAD, "死亡 → dead")


## 交互委派：点击/喂食（清醒）
func _test_interaction_click_feed() -> void:
	print("[pres4] 交互委派")
	var e := _make_interaction("click_feed")
	e.gm.initialize(_ts(2026, 10, 19, 10, 0))
	var c := e.controller

	# 清醒点击 → 获得经验
	_check(c.handle_click(_ts(2026, 10, 19, 10, 0)) == GameManager.ActionResult.DONE, "清醒点击 DONE")
	_check(e.gm.get_state().experience == 1, "点击获得经验")

	# 清醒喂食
	e.gm.get_state().satiety = 50
	_check(c.handle_feed(_ts(2026, 10, 19, 10, 0)) == GameManager.ActionResult.DONE, "清醒喂食 DONE")
	_check(e.gm.get_state().satiety == 80, "喂食恢复 30 点")


## 睡眠中首次操作仅唤醒
func _test_interaction_sleep_wake_only() -> void:
	print("[pres5] 睡眠中仅唤醒")
	var e := _make_interaction("wake_only")
	e.gm.initialize(_ts(2026, 10, 19, 10, 0))
	var c := e.controller

	# 进入睡眠（白天小睡到 11:00）
	_check(c.handle_sleep(_ts(2026, 10, 19, 10, 0)), "主动睡眠成功")
	_check(e.gm.get_state().sleep_type == PetState.SleepType.ACTIVE_SLEEP, "已睡眠")

	# 第一次点击只唤醒，不获得经验
	_check(c.handle_click(_ts(2026, 10, 19, 10, 0)) == GameManager.ActionResult.WOKE_UP, "睡眠中点击 WOKE_UP")
	_check(e.gm.get_state().experience == 0, "未获得经验")
	_check(e.gm.get_state().sleep_type == PetState.SleepType.AWAKE, "已唤醒")

	# 再次睡眠，第一次喂食只唤醒，不喂食
	c.handle_sleep(_ts(2026, 10, 19, 10, 0))
	e.gm.get_state().satiety = 50
	_check(c.handle_feed(_ts(2026, 10, 19, 10, 0)) == GameManager.ActionResult.WOKE_UP, "睡眠中喂食 WOKE_UP")
	_check(e.gm.get_state().satiety == 50, "未喂食（饱食度不变）")

	# 唤醒后再次点击正常执行
	_check(c.handle_click(_ts(2026, 10, 19, 10, 0)) == GameManager.ActionResult.DONE, "唤醒后点击 DONE")
	_check(e.gm.get_state().experience == 1, "唤醒后点击获得经验")


## 悬停提示
func _test_interaction_sleep_tip() -> void:
	print("[pres6] 悬停提示")
	var e := _make_interaction("tip")
	e.gm.initialize(_ts(2026, 10, 19, 10, 0))
	var c := e.controller
	_check(c.sleep_tip() == "", "清醒时无提示")
	c.handle_sleep(_ts(2026, 10, 19, 10, 0))
	_check(c.sleep_tip() == InteractionController.SLEEP_TIP, "睡眠时显示提示")
	c.handle_wake(_ts(2026, 10, 19, 10, 0))
	_check(c.sleep_tip() == "", "唤醒后无提示")


## 拖动阈值判定（纯逻辑）
func _test_drag_threshold() -> void:
	print("[pres7] 拖动阈值")
	_check(WindowController.is_drag(Vector2.ZERO, Vector2(10, 0)), "位移 10px > 阈值 → 拖动")
	_check(not WindowController.is_drag(Vector2.ZERO, Vector2(1, 0)), "位移 1px < 阈值 → 非拖动")
	_check(not WindowController.is_drag(Vector2.ZERO, Vector2.ZERO), "零位移 → 非拖动")


## 操作反馈文本映射（纯逻辑）
func _test_feedback_text() -> void:
	print("[pres8] 反馈文本")
	_check(InteractionController.action_feedback_text(GameManager.ActionResult.DONE) == "完成", "DONE → 完成")
	_check(InteractionController.action_feedback_text(GameManager.ActionResult.WOKE_UP) == "已唤醒", "WOKE_UP → 已唤醒")
	_check(InteractionController.action_feedback_text(GameManager.ActionResult.LEVELED_UP) == "升级！", "LEVELED_UP → 升级！")
	_check(InteractionController.action_feedback_text(GameManager.ActionResult.REJECTED) == "操作被拒绝", "REJECTED → 操作被拒绝")


## 动画资源（SpriteFrames）校验
func _test_frames_resource() -> void:
	print("[pres9] 动画资源")
	var frames := load("res://resources/animate/character_frames.tres") as SpriteFrames
	_check(frames != null, "动画资源加载成功")
	if frames == null:
		return
	_check(frames.has_animation("idle") and frames.get_frame_count("idle") == 7, "idle 7 帧")
	_check(frames.has_animation("sleep") and frames.get_frame_count("sleep") == 9, "sleep 9 帧")
	_check(frames.has_animation("dead") and frames.get_frame_count("dead") == 7, "dead 7 帧")
	_check(frames.has_animation("eat_bread") and frames.get_frame_count("eat_bread") == 13, "eat_bread 13 帧")
	_check(frames.get_animation_loop("idle"), "idle 循环")
	_check(not frames.get_animation_loop("eat_bread"), "eat_bread 不循环（一次性）")
	_check(frames.has_animation("hungry") and frames.get_frame_count("hungry") == 7, "hungry 7 帧")
	_check(frames.has_animation("weak") and frames.get_frame_count("weak") == 7, "weak 7 帧")


## 饥饿/虚弱状态映射（纯逻辑）
func _test_hungry_weak() -> void:
	print("[pres10] 饥饿/虚弱映射")
	var config := CharacterConfig.new()
	var s := PetState.new()
	_check(AnimationController.state_to_animation(s, config) == AnimationController.ANIM_IDLE, "满状态 → idle")
	s.satiety = config.forage_threshold
	_check(AnimationController.state_to_animation(s, config) == AnimationController.ANIM_HUNGRY, "饱食度<=阈值 → hungry")
	s.health = int(config.max_health * 0.4)
	_check(AnimationController.state_to_animation(s, config) == AnimationController.ANIM_WEAK, "低生命 → weak（优先于 hungry）")
	s.sleep_type = PetState.SleepType.ACTIVE_SLEEP
	_check(AnimationController.state_to_animation(s, config) == AnimationController.ANIM_SLEEP, "睡眠覆盖 hungry/weak")
	s.is_dead = true
	_check(AnimationController.state_to_animation(s, config) == AnimationController.ANIM_DEAD, "死亡最高优先")
	var s2 := PetState.new()
	s2.satiety = 1
	_check(AnimationController.state_to_animation(s2) == AnimationController.ANIM_IDLE, "无 config 不细分（回 idle）")


# --- 工具 ---

class Env:
	var sm: SaveManager
	var config: CharacterConfig
	var gm: GameManager
	var controller: InteractionController


func _make_interaction(name: String) -> Env:
	var e := Env.new()
	e.config = CharacterConfig.new()
	e.sm = SaveManager.new("%s/%s.json" % [TEST_DIR, name])
	e.gm = GameManager.new(e.sm, e.config)
	e.controller = InteractionController.new()
	e.controller.setup(e.gm, null)
	return e


func _clean_test_dir() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var dir := DirAccess.open(TEST_DIR)
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)


func _ts(year: int, month: int, day: int, hour: int, minute: int = 0) -> int:
	var offset := int(Time.get_time_zone_from_system()["bias"]) * 60
	return int(Time.get_unix_time_from_datetime_dict({
		"year": year, "month": month, "day": day,
		"hour": hour, "minute": minute, "second": 0,
	})) - offset


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok    " + label)
	else:
		_failed += 1
		print("  FAIL  " + label)
