extends SceneTree
## SurvivalSystem 单元测试。
## 运行方式：godot --headless --script res://tests/test_survival_system.gd


var _passed := 0
var _failed := 0


func _init() -> void:
	var state := PetState.new()
	var config := CharacterConfig.new()
	var sys := SurvivalSystem.new(state, config)

	# 1. 正常喂食
	state.satiety = 50
	_check(sys.feed(10) and state.satiety == 60, "正常喂食 +10")

	# 2. 饥饿值达到上限
	state.satiety = 90
	_check(sys.feed(30) and state.satiety == 100, "喂食封顶 max_satiety")

	# 3. 饥饿值不足时扣除生命
	state.satiety = 2
	state.health = 100
	_check(sys.apply_consumption(5) and state.satiety == 0 and state.health == 97, "饥饿不足扣生命（2 饥饿 + 3 生命）")

	# 4. 饥饿值刚好抵扣消耗
	state.satiety = 3
	state.health = 100
	_check(sys.apply_consumption(3) and state.satiety == 0 and state.health == 100, "饥饿刚好抵扣")

	# 5. 消耗量为 0
	state.satiety = 40
	state.health = 80
	_check(sys.apply_consumption(0) and state.satiety == 40 and state.health == 80, "消耗 0 无变化")

	# 6. 负数消耗量
	_check(not sys.apply_consumption(-1) and state.satiety == 40, "负数消耗被拒绝")

	# 7. 负数喂食量
	_check(not sys.feed(-5) and state.satiety == 40, "负数喂食被拒绝")

	# 8. 生命值降至 0
	var s2 := PetState.new()
	var sys2 := SurvivalSystem.new(s2, config)
	s2.satiety = 0
	s2.health = 3
	_check(sys2.apply_consumption(5) and s2.health == 0 and s2.is_dead, "生命归零则死亡")

	# 9. 死亡后禁止喂食
	_check(not sys2.feed(10), "死亡后禁止喂食")

	# 10. 死亡后禁止继续消耗
	_check(not sys2.apply_consumption(1), "死亡后禁止继续消耗")

	print("")
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok    " + label)
	else:
		_failed += 1
		print("  FAIL  " + label)
