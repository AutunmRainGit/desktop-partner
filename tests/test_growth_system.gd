extends SceneTree
## GrowthSystem 单元测试。
## 运行方式：godot --headless --script res://tests/test_growth_system.gd


var _passed := 0
var _failed := 0


func _init() -> void:
	var c := CharacterConfig.new()

	# 1. 初始等级
	var s := PetState.new()
	_check(s.level == 1 and s.experience == 0, "初始等级 1、经验 0")

	# 2. 正常获得经验
	var g := GrowthSystem.new(s, c)
	_check(g.gain_daily_experience("2026-10-19") == GrowthSystem.GainResult.GAINED, "首次获得经验返回 GAINED")
	_check(s.experience == 1 and s.level == 1, "经验 +1 且未升级")

	# 3. 同一天重复获得经验
	_check(g.gain_daily_experience("2026-10-19") == GrowthSystem.GainResult.REJECTED, "同日重复获得被拒绝")
	_check(s.experience == 1, "经验未重复累加")

	# 4. 跨天获得经验（较大阈值，跨天但不升级）
	var s4 := PetState.new()
	var c4 := CharacterConfig.new()
	c4.level_up_exp = 5
	var g4 := GrowthSystem.new(s4, c4)
	g4.gain_daily_experience("2026-10-19")
	_check(g4.gain_daily_experience("2026-10-20") == GrowthSystem.GainResult.GAINED and s4.experience == 2, "跨天可再次获得经验")

	# 5. 达到升级条件
	var s5 := PetState.new()
	var g5 := GrowthSystem.new(s5, c)
	g5.gain_daily_experience("2026-10-19")
	var r5 := g5.gain_daily_experience("2026-10-20")
	_check(r5 == GrowthSystem.GainResult.LEVELED_UP and s5.level == 2 and s5.experience == 0, "经验达标升级且经验清零")

	# 6. 达到最高等级后仍可继续获取经验（但不升级）
	var r6 := g5.gain_daily_experience("2026-10-21")
	_check(r6 == GrowthSystem.GainResult.GAINED and s5.level == 2 and s5.experience == 1, "最高等级仍可获取经验且不升级")

	# 7. 死亡后禁止获得经验
	var s7 := PetState.new()
	s7.is_dead = true
	var g7 := GrowthSystem.new(s7, c)
	_check(g7.gain_daily_experience("2026-10-19") == GrowthSystem.GainResult.REJECTED, "死亡后禁止获得经验")

	# 8. 未解锁自我觅食
	var s8 := PetState.new()
	var g8 := GrowthSystem.new(s8, c)
	_check(not g8.can_auto_forage(), "等级不足未解锁觅食")

	# 9. 已解锁自我觅食
	s8.level = 2
	_check(g8.can_auto_forage(), "达到等级解锁觅食")

	# 10. 点击与觅食共享每日限制
	var s10 := PetState.new()
	var g10 := GrowthSystem.new(s10, c)
	g10.gain_daily_experience("2026-10-19")  # 模拟“点击”获得经验
	_check(g10.gain_daily_experience("2026-10-19") == GrowthSystem.GainResult.REJECTED, "同日觅食不再获得经验（共享限制）")

	# 11. 日期合法性检查
	var sd := PetState.new()
	var gd := GrowthSystem.new(sd, c)
	_check(gd.gain_daily_experience("2026-13-01") == GrowthSystem.GainResult.REJECTED, "月份越界(13)被拒绝")
	_check(gd.gain_daily_experience("2026-02-30") == GrowthSystem.GainResult.REJECTED, "2月30日被拒绝")
	_check(gd.gain_daily_experience("2023-02-29") == GrowthSystem.GainResult.REJECTED, "非闰年2月29日被拒绝")
	_check(gd.gain_daily_experience("2026-04-31") == GrowthSystem.GainResult.REJECTED, "4月31日被拒绝")
	_check(gd.gain_daily_experience("not-a-date") == GrowthSystem.GainResult.REJECTED, "格式非法被拒绝")
	_check(gd.gain_daily_experience("2026/10/19") == GrowthSystem.GainResult.REJECTED, "分隔符非法被拒绝")
	_check(sd.experience == 0 and sd.last_exp_date == "", "非法日期不改变状态")
	_check(gd.gain_daily_experience("2024-02-29") == GrowthSystem.GainResult.GAINED, "闰年2月29日合法可获得经验")

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
