extends SceneTree
## TimeSystem 第二轮测试审计：针对边界与“测试通过但实现有缺陷”的补充验证。
## 运行方式：godot --headless --script res://tests/test_time_system_audit.gd


var _passed := 0
var _failed := 0


class Env:
	var state: PetState
	var config: CharacterConfig
	var survival: SurvivalSystem
	var growth: GrowthSystem
	var sleep: SleepSystem
	var time: TimeSystem


func _init() -> void:
	_test_online_forage_below_threshold()
	_test_leaf_restore_zero()
	_test_forage_at_max_satiety()
	_test_threshold_equals_max()
	_test_long_multiple_forage_cycles()
	_test_death_stats_consistency()
	_test_segmentation_with_sleep()
	_test_cross_midnight_experience_date()
	_test_sleep_interval_legality_stale()
	_test_wake_suppression_full()

	print("")
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


## 1. 在线觅食，初始饱食度低于阈值
func _test_online_forage_below_threshold() -> void:
	print("[audit1] 在线觅食：初始饱食度低于阈值")
	var e := _setup()
	e.state.level = 2
	e.state.satiety = 5  # 低于阈值10
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 10, 0)
	var r := e.time.settle(_ts(2026, 10, 19, 11, 0), true)
	_check(e.state.satiety == 12 and r.forage_count == 1 and not e.state.is_dead, "在线低于阈值先觅食回升")

	# 离线模式：低于阈值时下限保护“不抬升”，保持原值（记录为在线/离线差异）
	var e2 := _setup()
	e2.state.level = 2
	e2.state.satiety = 5
	e2.state.last_settlement_timestamp = _ts(2026, 10, 19, 10, 0)
	e2.time.settle(_ts(2026, 10, 19, 11, 0))
	_check(e2.state.satiety == 5, "离线低于阈值保持原值（不抬升）")


## 2. 树叶恢复量为 0
func _test_leaf_restore_zero() -> void:
	print("[audit2] leaf_restore=0")
	for online in [false, true]:
		var e := _setup()
		e.state.level = 2
		e.config.leaf_restore = 0
		e.state.satiety = 12
		e.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
		e.time.settle(_ts(2026, 10, 19, 15, 0), online)
		_check(e.state.satiety == 10 and not e.state.is_dead, "leaf_restore=0 在线=%s 下限保护不循环" % str(online))


## 3. 饱食度达上限，觅食无法实际恢复
func _test_forage_at_max_satiety() -> void:
	print("[audit3] 饱食度达上限觅食恢复受限")
	var e := _setup()
	e.state.level = 2
	e.config.forage_threshold = 95
	e.state.satiety = 100
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e.time.settle(_ts(2026, 10, 19, 16, 0), true)
	_check(e.state.satiety == 99 and e.state.satiety <= e.config.max_satiety, "恢复受上限限制且不越界")


## 4. forage_threshold == max_satiety
func _test_threshold_equals_max() -> void:
	print("[audit4] forage_threshold == max_satiety")
	for online in [false, true]:
		var e := _setup()
		e.state.level = 2
		e.config.forage_threshold = e.config.max_satiety
		e.state.satiety = e.config.max_satiety
		e.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
		e.time.settle(_ts(2026, 10, 19, 15, 0), online)
		_check(e.state.satiety == 100 and not e.state.is_dead, "阈值=上限 在线=%s 不循环不扣穿" % str(online))


## 5. 等级2 长结算、多觅食周期、不同余数不因自然饥饿死亡
func _test_long_multiple_forage_cycles() -> void:
	print("[audit5] 长时间多觅食周期")
	# 40点消耗（13h20min清醒），余数0：satiety 20 -> 10，3次觅食
	var e := _setup()
	e.state.level = 2
	e.state.satiety = 20
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 8, 0)
	var r := e.time.settle(_ts(2026, 10, 19, 21, 20), true)
	_check(e.state.satiety == 10 and r.forage_count == 3 and not e.state.is_dead, "40点消耗3次觅食不死")
	_check(e.state.experience <= 1, "多次觅食经验不超每日1点")

	# 余数3599：仍为40点消耗（3599<3600 不跨整点），余数正确结转，satiety 20 -> 10
	var e2 := _setup()
	e2.state.level = 2
	e2.state.satiety = 20
	e2.state.consumption_remainder = 3599
	e2.state.last_settlement_timestamp = _ts(2026, 10, 19, 8, 0)
	e2.time.settle(_ts(2026, 10, 19, 21, 20), true)
	_check(e2.state.satiety == 10 and e2.state.consumption_remainder == 3599 and not e2.state.is_dead, "余数3599正确结转且不死")


## 6. 结算中死亡，结果统计与实际一致
func _test_death_stats_consistency() -> void:
	print("[audit6] 结算中死亡统计一致")
	var e := _setup()
	e.state.satiety = 1
	e.state.health = 1
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	var sat0 := e.state.satiety
	var hp0 := e.state.health
	var r := e.time.settle(_ts(2026, 10, 19, 15, 0))  # 3点消耗
	_check(e.state.satiety == 0 and e.state.health == 0 and e.state.is_dead, "死亡且数值归零")
	_check(r.satiety_consumed == sat0 - e.state.satiety and r.health_consumed == hp0 - e.state.health, "统计=实际状态变化")
	_check(r.satiety_consumed == 1 and r.health_consumed == 1, "1饱食+1生命（第3点因死亡不生效）")


## 7. 短结算与长结算一致（跨睡眠边界分段）
func _test_segmentation_with_sleep() -> void:
	print("[audit7] 跨睡眠边界分段一致性")
	var whole := _setup()
	whole.state.last_settlement_timestamp = _ts(2026, 10, 19, 20, 0)
	whole.time.settle(_ts(2026, 10, 20, 10, 0))

	var split_boundary := _setup()
	split_boundary.state.last_settlement_timestamp = _ts(2026, 10, 19, 20, 0)
	split_boundary.time.settle(_ts(2026, 10, 19, 23, 0))
	split_boundary.time.settle(_ts(2026, 10, 20, 7, 0))
	split_boundary.time.settle(_ts(2026, 10, 20, 10, 0))

	var split_mid_sleep := _setup()
	split_mid_sleep.state.last_settlement_timestamp = _ts(2026, 10, 19, 20, 0)
	split_mid_sleep.time.settle(_ts(2026, 10, 20, 2, 0))
	split_mid_sleep.time.settle(_ts(2026, 10, 20, 10, 0))

	_check(whole.state.satiety == 66, "整段结算饱食度66")
	_check(split_boundary.state.satiety == whole.state.satiety, "睡眠边界分段一致")
	_check(split_mid_sleep.state.satiety == whole.state.satiety, "睡眠中途分段一致")


## 8. 跨午夜结算的每日经验日期
func _test_cross_midnight_experience_date() -> void:
	print("[audit8] 每日经验日期约定")
	var e := _setup()
	e.state.level = 2
	e.state.satiety = 12
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 10, 0)
	e.time.settle(_ts(2026, 10, 19, 11, 0), true)  # 在线觅食
	_check(e.state.last_exp_date == "2026-10-19", "经验日期为结算结束时刻的本地日期")


## 9. 睡眠区间合法性（含过期状态回归）
func _test_sleep_interval_legality_stale() -> void:
	print("[audit9] 睡眠区间合法性与过期状态")
	# 过期状态：scheduled_wake(15:00) < from(23:30)，不得产生起点早于 from 的越界区间
	var e := _setup()
	e.state.sleep_type = PetState.SleepType.ACTIVE_SLEEP
	e.state.scheduled_wake_timestamp = _ts(2026, 10, 19, 15, 0)
	var from_ts := _ts(2026, 10, 19, 23, 30)
	var to_ts := _ts(2026, 10, 20, 0, 30)
	var intervals := e.sleep.calculate_sleep_intervals(from_ts, to_ts)
	var ok := true
	for iv in intervals:
		var s := int(iv["start"])
		var en := int(iv["end"])
		if s < from_ts or en > to_ts or en <= s:
			ok = false
	_check(ok, "过期状态不产生越界区间")


## 10. 自动睡眠窗口内唤醒后的抑制状态（完整周期）
func _test_wake_suppression_full() -> void:
	print("[audit10] 唤醒抑制完整周期")
	var e := _setup()
	_check(e.sleep.start_auto_sleep(_ts(2026, 10, 19, 23, 0)), "10-19 23:00 自动入睡")
	_check(e.sleep.wake_up(_ts(2026, 10, 19, 23, 30)), "23:30 提前唤醒")
	_check(e.state.suppressed_auto_sleep_cycle == "2026-10-19", "记录被取消周期")
	_check(not e.sleep.start_auto_sleep(_ts(2026, 10, 20, 0, 30)), "00:30 本周期不再入睡")
	_check(not e.sleep.start_auto_sleep(_ts(2026, 10, 20, 6, 30)), "06:30 本周期不再入睡")
	_check(e.sleep.start_auto_sleep(_ts(2026, 10, 20, 23, 0)), "次日 23:00 可正常入睡")

	# 主动睡眠期间在自动窗口内被唤醒，也应取消当次自动睡眠周期
	var e2 := _setup()
	e2.sleep.start_manual_sleep(_ts(2026, 10, 19, 22, 0))
	e2.sleep.wake_up(_ts(2026, 10, 19, 23, 30))
	_check(e2.state.suppressed_auto_sleep_cycle == "2026-10-19", "主动睡眠在自动窗口内唤醒也取消周期")
	_check(not e2.sleep.start_auto_sleep(_ts(2026, 10, 20, 0, 30)), "主动睡眠唤醒后 00:30 不再自动入睡")

	# 自动窗口前唤醒不取消
	var e3 := _setup()
	e3.sleep.start_manual_sleep(_ts(2026, 10, 19, 22, 0))
	e3.sleep.wake_up(_ts(2026, 10, 19, 22, 30))
	_check(e3.state.suppressed_auto_sleep_cycle == "", "自动窗口前唤醒不取消周期")
	_check(e3.sleep.start_auto_sleep(_ts(2026, 10, 19, 23, 0)), "23:00 仍可自动入睡")


# --- 工具 ---

func _setup() -> Env:
	var e := Env.new()
	e.state = PetState.new()
	e.config = CharacterConfig.new()
	e.survival = SurvivalSystem.new(e.state, e.config)
	e.growth = GrowthSystem.new(e.state, e.config)
	e.sleep = SleepSystem.new(e.state)
	e.time = TimeSystem.new(e.state, e.config, e.survival, e.growth, e.sleep)
	return e


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
