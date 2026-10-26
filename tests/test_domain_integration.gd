extends SceneTree
## 三个领域服务的联合测试：验证共享同一个 PetState、职责边界与依赖方向。
## 运行方式：godot --headless --script res://tests/test_domain_integration.gd


var _passed := 0
var _failed := 0


func _init() -> void:
	var state := PetState.new()
	var config := CharacterConfig.new()
	var survival := SurvivalSystem.new(state, config)
	var growth := GrowthSystem.new(state, config)
	var sleep := SleepSystem.new(state)

	# 1. 三个系统共享同一个 PetState 实例
	_check(state.satiety == 100 and state.health == 100 and state.level == 1, "共享同一 PetState 初始状态")
	state.satiety = 50
	survival.feed(20)
	_check(state.satiety == 70, "SurvivalSystem 写入了共享 state")

	# 2. 喂食不修改等级
	var level_before := state.level
	_check(state.level == level_before, "喂食不影响等级")

	# 3. 升级不直接修改饥饿值
	var satiety_before := state.satiety
	growth.gain_daily_experience("2026-10-19")
	growth.gain_daily_experience("2026-10-20")
	_check(state.level == 2, "两次跨天经验后升级到 2 级")
	_check(state.satiety == satiety_before, "升级不改变饥饿值")

	# 4. 睡眠不直接扣除生命值
	var health_before := state.health
	_check(sleep.start_manual_sleep(_ts(2026, 10, 19, 14, 0)), "可进入主动睡眠")
	_check(state.health == health_before, "睡眠不扣除生命值")
	_check(sleep.is_sleeping(), "已处于睡眠状态")

	# 5. 死亡状态能够限制成长和睡眠
	var s2 := PetState.new()
	s2.is_dead = true
	var growth2 := GrowthSystem.new(s2, config)
	var sleep2 := SleepSystem.new(s2)
	_check(growth2.gain_daily_experience("2026-10-19") == GrowthSystem.GainResult.REJECTED, "死亡限制成长")
	_check(not sleep2.start_manual_sleep(_ts(2026, 10, 19, 14, 0)), "死亡限制睡眠")
	_check(not sleep2.start_auto_sleep(_ts(2026, 10, 19, 23, 0)), "死亡限制自动睡眠")

	# 6. 各系统可独立构造，不存在不必要的直接依赖
	var s3 := PetState.new()
	var only_survival := SurvivalSystem.new(s3, config)
	var only_growth := GrowthSystem.new(s3, config)
	var only_sleep := SleepSystem.new(s3)
	_check(only_survival != null and only_growth != null and only_sleep != null, "各系统可独立构造（仅依赖 state/config）")

	print("")
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


## 构造“本地时间”对应的绝对 Unix 时间戳。
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
