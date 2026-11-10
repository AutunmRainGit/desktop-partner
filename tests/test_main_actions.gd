extends SceneTree

var _passed := 0
var _failed := 0
var changes: Array[Dictionary] = []

class TestMain extends Main:
	var clock := TimeUtils.unix_of_date_hour("2026-11-10", 12)
	func _setup_game() -> void:
		var path := "user://menu_action_tests/save.json"
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		_game = GameManager.new(SaveManager.new(path), CharacterConfig.new())
	func _now() -> int:
		return clock


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.set_script(TestMain)
	root.add_child(main)
	main.set_process(false)
	main.menu_state_changed.connect(func(state: Dictionary): changes.append(state))
	var pet: PetController = main.get_node("PetController")
	var sprite := pet.get_sprite()
	var state: PetState = main._game.get_state()
	state.satiety = 40
	_check(not main.get_menu_state().is_sleeping and main.get_menu_state().status_bar_visible, "初始菜单状态")
	_check(main.get_menu_state().health == 100 and main.get_menu_state().satiety == 40 and main.get_menu_state().required_exp == 2, "菜单状态来自真实生命、饱食度和成长阈值")
	_check(main.dispatch_action(Main.Action.START_SLEEP).status == "success", "统一入口主动睡眠")
	_check(changes.size() == 1 and changes[-1].is_sleeping, "睡眠变化发布状态")
	var before := state.last_settlement_timestamp
	_check(main.dispatch_action(Main.Action.SET_STATUS_BAR_VISIBLE, {"visible": false}).status == "success", "睡眠时可隐藏状态栏")
	_check(main.dispatch_action(Main.Action.SET_STATUS_BAR_VISIBLE, {"visible": false}).status == "success", "重复设置false成功")
	_check(changes.size() == 2 and not pet.is_status_bar_visible() and state.sleep_type != PetState.SleepType.AWAKE, "显隐幂等且不唤醒")
	_check(state.last_settlement_timestamp == before, "表现操作不结算时间")
	main.clock += 1
	main._process(0.0)
	_check(not pet.is_status_bar_visible() and changes.size() == 2, "定时刷新保持隐藏且不重复发信号")
	var f := InputEventKey.new()
	f.pressed = true
	f.keycode = KEY_F
	main._unhandled_key_input(f)
	_check(state.sleep_type == PetState.SleepType.AWAKE and state.satiety == 40, "睡眠按F只唤醒不喂食")
	_check(sprite.animation == &"stop_sleep" and changes.size() == 3, "仅唤醒保留动画和状态通知")
	_check(main.dispatch_action(Main.Action.FEED_BREAD).status == "success" and state.satiety == 70, "第二次喂食恢复30")
	_check(sprite.animation == &"eat_bread", "喂食动画保留")
	_check(changes[-1].satiety == 70 and not changes[-1].status_bar_visible, "隐藏状态栏后仍推送最新数值")
	var s := InputEventKey.new()
	s.pressed = true
	s.keycode = KEY_S
	main._unhandled_key_input(s)
	_check(state.sleep_type != PetState.SleepType.AWAKE, "S走统一入口睡眠")
	var r: Dictionary = main.dispatch_action(Main.Action.FEED_BREAD)
	_check(r.status == "woke_up" and not r.state.is_sleeping and state.satiety == 70, "显式返回仅唤醒结果")
	main.dispatch_action(Main.Action.START_SLEEP)
	var w := InputEventKey.new()
	w.pressed = true
	w.keycode = KEY_W
	main._unhandled_key_input(w)
	_check(not main.get_menu_state().is_sleeping, "W走统一入口唤醒")
	_check(main.dispatch_action(Main.Action.WAKE_UP).status == "rejected", "清醒时唤醒按真实结果拒绝")
	_check(main.dispatch_action(999).status == "rejected", "未知操作拒绝")
	_check(main.dispatch_action(Main.Action.SET_STATUS_BAR_VISIBLE, {"visible": "false"}).status == "rejected", "不接受字符串布尔值")
	_check(not pet.is_status_bar_visible(), "非法请求不更改显隐")
	main.dispatch_action(Main.Action.SET_STATUS_BAR_VISIBLE, {"visible": true})
	_check(pet.is_status_bar_visible(), "显式显示状态栏")
	main.dispatch_action(Main.Action.START_SLEEP)
	main.clock += 3600
	main._process(0.0)
	_check(not changes[-1].is_sleeping, "自然苏醒同步菜单状态")
	main.clock = TimeUtils.unix_of_date_hour("2026-11-10", 23)
	main._process(0.0)
	_check(changes[-1].is_sleeping, "自动入睡同步菜单状态")
	main.clock += 1
	main._window._potential_drag = true
	main._window._dragging = true
	main._window._on_release()
	_check(state.sleep_type != PetState.SleepType.AWAKE, "左键拖动释放不触发点击唤醒")
	main._on_pet_clicked()
	_check(state.sleep_type == PetState.SleepType.AWAKE, "左键点击仍可唤醒")
	main.queue_free()
	await process_frame
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  ok    " + label)
	else:
		_failed += 1
		print("  FAIL  " + label)
