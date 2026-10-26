extends SceneTree
## SleepSystem 单元测试。
## 运行方式：godot --headless --script res://tests/test_sleep_system.gd
## 使用固定“本地时间戳”构造测试输入，不依赖运行时的真实日期/时间。


var _passed := 0
var _failed := 0


func _init() -> void:
	# 1. 白天主动睡眠 1 小时
	var s1 := PetState.new()
	var sys1 := SleepSystem.new(s1)
	_check(sys1.start_manual_sleep(_ts(2026, 10, 19, 14, 0)), "白天 14:00 可主动睡眠")
	_check(s1.sleep_type == PetState.SleepType.ACTIVE_SLEEP, "睡眠类型为主动睡眠")
	_check(s1.scheduled_wake_timestamp == _ts(2026, 10, 19, 15, 0), "14:00 睡 1 小时 → 15:00 醒")

	# 2. 晚上主动睡眠至次日 08:00
	var s2 := PetState.new()
	var sys2 := SleepSystem.new(s2)
	sys2.start_manual_sleep(_ts(2026, 10, 19, 19, 0))
	_check(s2.scheduled_wake_timestamp == _ts(2026, 10, 20, 8, 0), "19:00 主动睡眠 → 次日 08:00 醒")

	# 3. 凌晨主动睡眠至当天 08:00
	var s3 := PetState.new()
	var sys3 := SleepSystem.new(s3)
	sys3.start_manual_sleep(_ts(2026, 10, 20, 1, 0))
	_check(s3.scheduled_wake_timestamp == _ts(2026, 10, 20, 8, 0), "01:00 主动睡眠 → 当天 08:00 醒")

	# 4. 23:00 自动入睡
	var s4 := PetState.new()
	var sys4 := SleepSystem.new(s4)
	_check(sys4.start_auto_sleep(_ts(2026, 10, 19, 23, 0)), "23:00 自动入睡")
	_check(s4.sleep_type == PetState.SleepType.AUTO_SLEEP, "类型为自动睡眠")
	_check(s4.scheduled_wake_timestamp == _ts(2026, 10, 20, 7, 0), "计划次日 07:00 醒")

	# 5. 07:00 自动苏醒
	_check(sys4.update_sleep_state(_ts(2026, 10, 20, 7, 0)), "07:00 自然苏醒返回 true")
	_check(s4.sleep_type == PetState.SleepType.AWAKE, "苏醒后为清醒")

	# 6. 自动睡眠跨午夜
	var s6 := PetState.new()
	var sys6 := SleepSystem.new(s6)
	sys6.start_auto_sleep(_ts(2026, 10, 19, 23, 0))
	_check(sys6.is_sleeping(), "自动睡眠已开始")
	_check(not sys6.update_sleep_state(_ts(2026, 10, 20, 0, 30)), "00:30 未到苏醒时间")
	_check(sys6.is_sleeping(), "00:30 仍睡眠")
	_check(sys6.update_sleep_state(_ts(2026, 10, 20, 7, 0)), "07:00 跨午夜后自然苏醒")

	# 7. 主动睡眠优先于自动睡眠
	var s7 := PetState.new()
	var sys7 := SleepSystem.new(s7)
	sys7.start_manual_sleep(_ts(2026, 10, 19, 22, 0))
	_check(s7.scheduled_wake_timestamp == _ts(2026, 10, 20, 8, 0), "22:00 主动睡眠计划 08:00 醒")
	_check(not sys7.start_auto_sleep(_ts(2026, 10, 19, 23, 0)), "23:00 不覆盖主动睡眠")
	_check(s7.sleep_type == PetState.SleepType.ACTIVE_SLEEP, "仍为主动睡眠")
	_check(not sys7.update_sleep_state(_ts(2026, 10, 20, 7, 0)), "07:00 不按自动睡眠苏醒")
	_check(s7.sleep_type == PetState.SleepType.ACTIVE_SLEEP, "07:00 仍为主动睡眠")
	_check(sys7.update_sleep_state(_ts(2026, 10, 20, 8, 0)), "08:00 按主动睡眠计划苏醒")

	# 8. 玩家提前唤醒
	var s8 := PetState.new()
	var sys8 := SleepSystem.new(s8)
	sys8.start_auto_sleep(_ts(2026, 10, 19, 23, 0))
	_check(sys8.wake_up(_ts(2026, 10, 19, 23, 30)), "提前唤醒返回 true")
	_check(s8.sleep_type == PetState.SleepType.AWAKE, "提前唤醒后清醒")
	_check(s8.suppressed_auto_sleep_cycle == "2026-10-19", "记录被取消的自动睡眠周期")

	# 9. 提前唤醒后禁止当晚再次自动入睡
	_check(not sys8.start_auto_sleep(_ts(2026, 10, 20, 0, 30)), "00:30 不再次自动入睡")
	_check(not sys8.start_auto_sleep(_ts(2026, 10, 20, 6, 30)), "06:30 不再次自动入睡")
	_check(s8.sleep_type == PetState.SleepType.AWAKE, "始终保持清醒")

	# 10. 下一晚可以正常自动入睡
	_check(sys8.start_auto_sleep(_ts(2026, 10, 20, 23, 0)), "下一晚 23:00 可正常自动入睡")

	# 11. 死亡角色无法睡眠
	var s11 := PetState.new()
	s11.is_dead = true
	var sys11 := SleepSystem.new(s11)
	_check(not sys11.start_manual_sleep(_ts(2026, 10, 19, 14, 0)), "死亡后无法主动睡眠")
	_check(not sys11.start_auto_sleep(_ts(2026, 10, 19, 23, 0)), "死亡后无法自动睡眠")

	# 12. 睡眠状态查询
	var s12 := PetState.new()
	var sys12 := SleepSystem.new(s12)
	_check(not sys12.is_sleeping(), "初始清醒")
	sys12.start_manual_sleep(_ts(2026, 10, 19, 14, 0))
	_check(sys12.is_sleeping(), "主动睡眠后 is_sleeping 为 true")

	# 13. 08:00 与 18:00 边界
	var s13 := PetState.new()
	var sys13 := SleepSystem.new(s13)
	sys13.start_manual_sleep(_ts(2026, 10, 19, 8, 0))
	_check(s13.scheduled_wake_timestamp == _ts(2026, 10, 19, 9, 0), "08:00 属于白天 → 睡 1 小时")
	var s13b := PetState.new()
	var sys13b := SleepSystem.new(s13b)
	sys13b.start_manual_sleep(_ts(2026, 10, 19, 18, 0))
	_check(s13b.scheduled_wake_timestamp == _ts(2026, 10, 20, 8, 0), "18:00 属于夜间 → 次日 08:00 醒")

	# 14. 23:00 与 07:00 边界
	var s14 := PetState.new()
	var sys14 := SleepSystem.new(s14)
	sys14.start_manual_sleep(_ts(2026, 10, 19, 23, 0))
	_check(s14.scheduled_wake_timestamp == _ts(2026, 10, 20, 8, 0), "23:00 主动睡眠 → 次日 08:00 醒")
	var s14b := PetState.new()
	var sys14b := SleepSystem.new(s14b)
	sys14b.start_manual_sleep(_ts(2026, 10, 20, 7, 0))
	_check(s14b.scheduled_wake_timestamp == _ts(2026, 10, 20, 8, 0), "07:00 主动睡眠 → 当天 08:00 醒")

	# 15. 时间戳异常/时间倒退
	var s15 := PetState.new()
	var sys15 := SleepSystem.new(s15)
	sys15.start_manual_sleep(_ts(2026, 10, 19, 14, 0))
	_check(not sys15.update_sleep_state(_ts(2026, 10, 19, 13, 0)), "时间倒退不触发苏醒")
	_check(sys15.is_sleeping(), "倒退后仍睡眠")
	_check(sys15.update_sleep_state(_ts(2026, 10, 19, 15, 0)), "到达计划时间正常苏醒")

	_test_offline_intervals()

	print("")
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


## 构造“本地时间”对应的绝对 Unix 时间戳，保证测试不依赖真实时钟与机器时区。
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


## 离线睡眠区间判定测试。
func _test_offline_intervals() -> void:
	print("[test] 离线睡眠区间")

	# 1. 基本离线场景：20:00 关闭、次日 10:00 打开，期间全程清醒
	var s1 := PetState.new()
	var sys1 := SleepSystem.new(s1)
	var iv1 := sys1.calculate_sleep_intervals(_ts(2026, 10, 19, 20, 0), _ts(2026, 10, 20, 10, 0))
	_check(iv1.size() == 1, "基本场景：1 个睡眠区间")
	if iv1.size() == 1:
		_check(int(iv1[0]["start"]) == _ts(2026, 10, 19, 23, 0) and int(iv1[0]["end"]) == _ts(2026, 10, 20, 7, 0), "23:00~07:00 自动睡眠")

	# 2. 主动睡眠优先：22:00 主动睡眠（08:00 醒），不被 23:00 自动睡眠覆盖
	var s2 := PetState.new()
	s2.sleep_type = PetState.SleepType.ACTIVE_SLEEP
	s2.scheduled_wake_timestamp = _ts(2026, 10, 20, 8, 0)
	var sys2 := SleepSystem.new(s2)
	var iv2 := sys2.calculate_sleep_intervals(_ts(2026, 10, 19, 22, 0), _ts(2026, 10, 20, 10, 0))
	_check(iv2.size() == 1, "主动睡眠优先：1 个睡眠区间")
	if iv2.size() == 1:
		_check(int(iv2[0]["start"]) == _ts(2026, 10, 19, 22, 0) and int(iv2[0]["end"]) == _ts(2026, 10, 20, 8, 0), "22:00~08:00 主动睡眠")

	# 3. 提前唤醒后抑制当晚
	var s3 := PetState.new()
	s3.suppressed_auto_sleep_cycle = "2026-10-19"
	var sys3 := SleepSystem.new(s3)
	_check(sys3.calculate_sleep_intervals(_ts(2026, 10, 19, 23, 30), _ts(2026, 10, 20, 10, 0)).size() == 0, "被抑制的当晚无睡眠区间")

	# 4. 下一晚可以正常自动入睡
	var s4 := PetState.new()
	s4.suppressed_auto_sleep_cycle = "2026-10-19"
	var sys4 := SleepSystem.new(s4)
	_check(sys4.calculate_sleep_intervals(_ts(2026, 10, 20, 23, 0), _ts(2026, 10, 21, 7, 0)).size() == 1, "下一晚正常自动睡眠")

	# 5. 跨两天的离线
	var s5 := PetState.new()
	var sys5 := SleepSystem.new(s5)
	_check(sys5.calculate_sleep_intervals(_ts(2026, 10, 19, 20, 0), _ts(2026, 10, 21, 10, 0)).size() == 2, "跨两天：2 个睡眠区间")

	# 6. 死亡角色无睡眠区间
	var s6 := PetState.new()
	s6.is_dead = true
	var sys6 := SleepSystem.new(s6)
	_check(sys6.calculate_sleep_intervals(_ts(2026, 10, 19, 20, 0), _ts(2026, 10, 20, 10, 0)).size() == 0, "死亡角色无睡眠区间")

	# 7. 时间倒置/空区间
	var s7 := PetState.new()
	var sys7 := SleepSystem.new(s7)
	_check(sys7.calculate_sleep_intervals(_ts(2026, 10, 20, 10, 0), _ts(2026, 10, 19, 20, 0)).size() == 0, "时间倒置返回空")
