extends SceneTree
## 使用独立测试存档和真实主场景，覆盖旧档、UI、点击和觅食升级动画。

const TEST_DIR := "user://growth_integration_tests"
var _passed := 0
var _failed := 0


class TestMain extends Main:
	var clock: int
	var test_path: String

	func _setup_game() -> void:
		_game = GameManager.new(SaveManager.new(test_path), CharacterConfig.new())

	func _now() -> int:
		return clock


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var dir := DirAccess.open(TEST_DIR)
	for file in dir.get_files():
		dir.remove(file)
	_test_migration()
	_test_scene()
	# 让场景和反馈定时器正常退出。
	await process_frame
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_migration() -> void:
	var now := TimeUtils.unix_of_date_hour("2026-11-09", 12)
	for case in [[1, 1, 1, 1], [2, 3, 2, 3], [2, 13, 4, 3], [2, 88, 10, 0], [10, 0, 10, 0]]:
		var path := "%s/migrate_%d_%d.json" % [TEST_DIR, case[0], case[1]]
		var sm := SaveManager.new(path)
		var original := PetState.new()
		original.level = case[0]
		original.experience = case[1]
		original.last_exp_date = "2026-11-09"
		original.last_settlement_timestamp = now
		original.health = 88
		original.satiety = 42
		original.consumption_remainder = 123
		_check(sm.save(original) == SaveManager.SaveError.OK, "准备v1存档")
		# 直接读取保留原值，应用层再调用成长系统进行折算。
		var raw := sm.load(CharacterConfig.new())
		_check(raw.ok and raw.state.level == case[0] and raw.state.experience == case[1], "v1结构兼容且不在基础设施层计算经验")
		var gm := GameManager.new(sm, CharacterConfig.new())
		_check(gm.initialize(now).ok, "旧档初始化成功")
		var state := gm.get_state()
		_check(state.level == case[2] and state.experience == case[3], "旧档Lv.%d EXP%d合理折算" % [case[0], case[1]])
		_check(state.last_exp_date == original.last_exp_date and state.health == 88 and state.satiety == 42 and state.consumption_remainder == 123, "不改变每日记录和生存字段")
		var restored := GameManager.new(sm, CharacterConfig.new())
		_check(restored.initialize(now).ok and restored.get_state().level == case[2] and restored.get_state().experience == case[3], "重启不重复折算")
		_check(restored.click_pet(now) == GameManager.ActionResult.REJECTED, "重启保留每日经验限制")
	var sample := PetState.new()
	sample.level = 3
	sample.experience = 4
	_check(PetController.growth_text(sample, CharacterConfig.new()) == "Lv.3 EXP 4/6", "经验进度使用成长系统阈值")
	sample.level = 10
	_check(PetController.growth_text(sample, CharacterConfig.new()) == "Lv.10 MAX", "满级显示MAX")


func _test_scene() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.set_script(TestMain)
	main.test_path = TEST_DIR + "/scene.json"
	main.clock = TimeUtils.unix_of_date_hour("2026-11-09", 12)
	root.add_child(main)
	main.set_process(false)
	var sprite: AnimatedSprite2D = main.get_node("PetController/CharacterSprite")
	var label: Label = main.get_node("PetController/StatusDisplay/LevelLabel")
	_check(main._game.is_initialized(), "真实主场景用测试存档初始化")
	_prepare(main, 1, 1)
	main._on_pet_clicked()
	_check(main._game.get_state().level == 2 and sprite.animation == &"level_up", "点击升级播放level_up")
	_check(label.text == "Lv.2 EXP 0/4", "点击后真实标签刷新")
	main._animation._on_animation_finished()
	_check(sprite.animation == &"hungry", "升级动作结束回到真实饥饿状态")

	_prepare(main, 2, 3)
	main.clock += 1200
	main._process(0.0)
	_check(main._game.get_state().level == 3 and sprite.animation == &"level_up", "定时在线觅食升级优先播放level_up")
	_check(label.text == "Lv.3 EXP 0/6", "觅食后进度刷新")
	_check(main._game.click_pet(main.clock) == GameManager.ActionResult.REJECTED and main._game.get_state().experience == 0, "觅食后点击共享每日上限")

	_prepare(main, 2, 3)
	main.clock += 1200
	main._do_feed()
	_check(main._game.get_state().level == 3 and sprite.animation == &"level_up", "喂食前结算觅食升级不被吃面包动画覆盖")

	_prepare(main, 2, 3)
	main.clock += 1200
	main._on_pet_clicked()
	_check(main._game.get_state().level == 3 and sprite.animation == &"level_up", "点击前觅食消耗每日额度仍播放升级")

	_prepare(main, 10, 0)
	main.clock += 1200
	main._process(0.0)
	_check(main._game.get_state().satiety > 10 and main._game.get_state().experience == 0, "满级觅食继续恢复饱食度但不积累经验")
	_check(label.text == "Lv.10 MAX" and sprite.animation == &"eat_leaf", "满级显示MAX且正常播放觅食动画")
	main.queue_free()


func _prepare(main, level: int, experience: int) -> void:
	var state: PetState = main._game.get_state()
	state.level = level
	state.experience = experience
	state.satiety = 10
	state.last_exp_date = ""
	state.last_settlement_timestamp = main.clock
	state.consumption_remainder = 0
	main._displayed_level = level
	main._refresh()
	main._animation._on_animation_finished()


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  ok    " + label)
	else:
		_failed += 1
		print("  FAIL  " + label)
