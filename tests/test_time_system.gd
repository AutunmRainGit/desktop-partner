extends SceneTree
## TimeSystem 单元测试。
## 运行方式：godot --headless --script res://tests/test_time_system.gd
## 使用固定“本地时间戳”，不依赖真实时钟。


var _passed := 0
var _failed := 0


func _init() -> void:
	_test_awake_one_hour()
	_test_sleep_one_hour()
	_test_awake_20min()
	_test_awake_10min_remainder()
	_test_awake_10min_again()
	_test_mixed_remainder()
	_test_offline_basic()
	_test_active_sleep_priority()
	_test_suppressed_auto_sleep()
	_test_no_double_settlement()
	_test_negative_time()
	_test_satiety_drain_health()
	_test_death()
	_test_forage_no_death()
	_test_forage_floor_offline()
	_test_leaf_restore_zero()
	_test_dead_no_consume()
	_test_multi_day_sleep()
	_test_intervals_in_range()
	_test_state_sync()
	_test_online_forage_experience()
	_test_offline_forage_no_experience()
	_test_no_negative()
	_test_segmentation_consistency()

	print("")
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


## 测试1：清醒1小时，消耗3点饱食度
func _test_awake_one_hour() -> void:
	print("[test1] 清醒1小时")
	var e := _setup()
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	var r := e.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(r.settled and r.awake_seconds == 3600 and r.sleep_seconds == 0, "清醒1小时")
	_check(e.state.satiety == 97 and r.satiety_consumed == 3, "消耗3点饱食度")


## 测试2：睡眠1小时，消耗2点饱食度
func _test_sleep_one_hour() -> void:
	print("[test2] 睡眠1小时")
	var e := _setup()
	var now := _ts(2026, 10, 20, 0, 0)
	e.state.last_settlement_timestamp = now - 3600
	e.state.sleep_type = PetState.SleepType.ACTIVE_SLEEP
	e.state.scheduled_wake_timestamp = now
	var r := e.time.settle(now)
	_check(r.settled and r.sleep_seconds == 3600 and r.awake_seconds == 0, "睡眠1小时")
	_check(e.state.satiety == 98 and r.satiety_consumed == 2, "消耗2点饱食度")


## 测试3：清醒20分钟，消耗1点
func _test_awake_20min() -> void:
	print("[test3] 清醒20分钟")
	var e := _setup()
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	var r := e.time.settle(_ts(2026, 10, 19, 14, 20))
	_check(e.state.satiety == 99 and r.satiety_consumed == 1, "清醒20分钟消耗1点")
	_check(e.state.consumption_remainder == 0, "余数为0")


## 测试4：清醒10分钟，保留余数1800
func _test_awake_10min_remainder() -> void:
	print("[test4] 清醒10分钟余数")
	var e := _setup()
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	var r := e.time.settle(_ts(2026, 10, 19, 14, 10))
	_check(e.state.satiety == 100 and r.satiety_consumed == 0, "清醒10分钟不扣点")
	_check(e.state.consumption_remainder == 1800, "余数1800")


## 测试5：再清醒10分钟，累计消耗1点
func _test_awake_10min_again() -> void:
	print("[test5] 再清醒10分钟")
	var e := _setup()
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e.time.settle(_ts(2026, 10, 19, 14, 10))
	e.time.settle(_ts(2026, 10, 19, 14, 20))
	_check(e.state.satiety == 99, "累计消耗1点")
	_check(e.state.consumption_remainder == 0, "余数归零")


## 测试6：睡眠/清醒切换，余数正确累计
func _test_mixed_remainder() -> void:
	print("[test6] 睡眠清醒混合余数")
	var e := _setup()
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 22, 40)
	var r := e.time.settle(_ts(2026, 10, 19, 23, 20))
	# 22:40~23:00 清醒(20min*3=3600)，23:00~23:20 睡眠(20min*2=2400)，合计6000单位→1点，余数2400
	_check(r.awake_seconds == 1200 and r.sleep_seconds == 1200, "清醒1200s+睡眠1200s")
	_check(e.state.satiety == 99, "消耗1点")
	_check(e.state.consumption_remainder == 2400, "余数2400")


## 测试7：20:00关闭、次日10:00打开（清醒6h+睡眠8h，消耗34点）
func _test_offline_basic() -> void:
	print("[test7] 离线基本场景")
	var e := _setup()
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 20, 0)
	var r := e.time.settle(_ts(2026, 10, 20, 10, 0))
	_check(r.awake_seconds == 6 * 3600, "清醒6小时")
	_check(r.sleep_seconds == 8 * 3600, "睡眠8小时")
	_check(r.satiety_consumed == 34, "总消耗34点")
	_check(e.state.satiety == 66, "饱食度66")


## 测试8：22:00主动睡眠，22:30关闭，次日10:00打开，主动睡眠持续到08:00
func _test_active_sleep_priority() -> void:
	print("[test8] 主动睡眠优先")
	var e := _setup()
	e.state.sleep_type = PetState.SleepType.ACTIVE_SLEEP
	e.state.scheduled_wake_timestamp = _ts(2026, 10, 20, 8, 0)
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 22, 30)
	var r := e.time.settle(_ts(2026, 10, 20, 10, 0))
	# 22:30~08:00 睡眠 = 9.5h；08:00~10:00 清醒 = 2h
	_check(r.sleep_seconds == 9 * 3600 + 1800, "主动睡眠持续到08:00（9.5小时）")
	_check(r.awake_seconds == 2 * 3600, "08:00后清醒2小时")
	_check(e.state.sleep_type == PetState.SleepType.AWAKE, "结算后清醒")


## 测试9：自动睡眠被提前唤醒，本周期不再自动睡眠
func _test_suppressed_auto_sleep() -> void:
	print("[test9] 被取消的自动睡眠周期")
	var e := _setup()
	e.state.suppressed_auto_sleep_cycle = "2026-10-19"
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 23, 30)
	var r := e.time.settle(_ts(2026, 10, 20, 10, 0))
	_check(r.sleep_seconds == 0, "被取消周期无睡眠")


## 测试10：连续调用同一时间不重复扣除
func _test_no_double_settlement() -> void:
	print("[test10] 禁止重复结算")
	var e := _setup()
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 9, 0)
	e.time.settle(_ts(2026, 10, 19, 10, 0))
	var satiety_after_first := e.state.satiety
	var r2 := e.time.settle(_ts(2026, 10, 19, 10, 0))
	_check(not r2.settled, "第二次同时间不结算")
	_check(e.state.satiety == satiety_after_first, "不重复扣除")
	e.time.settle(_ts(2026, 10, 19, 10, 1))
	_check(e.state.satiety == satiety_after_first, "10:01只结算新增1分钟（不足1点）")


## 测试11：早于上次结算的时间不产生负消耗
func _test_negative_time() -> void:
	print("[test11] 时间回拨")
	var e := _setup()
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 10, 0)
	var satiety_before := e.state.satiety
	var r := e.time.settle(_ts(2026, 10, 19, 9, 0))
	_check(not r.settled, "拒绝回拨结算")
	_check(e.state.satiety == satiety_before, "无负消耗")


## 测试12：一级角色饱食度耗尽，生命值1:1下降
func _test_satiety_drain_health() -> void:
	print("[test12] 饱食度耗尽扣生命")
	var e := _setup()
	e.state.satiety = 2
	e.state.health = 100
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	var r := e.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(e.state.satiety == 0, "饱食度归零")
	_check(e.state.health == 99 and r.health_consumed == 1, "生命值1:1下降")


## 测试13：一级角色生命值归零死亡
func _test_death() -> void:
	print("[test13] 生命值归零死亡")
	var e := _setup()
	e.state.satiety = 0
	e.state.health = 2
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	var r := e.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(e.state.health == 0 and e.state.is_dead, "死亡")
	_check(r.is_dead, "结果报告死亡")


## 测试14：二级角色自动觅食，自然饥饿不致死
func _test_forage_no_death() -> void:
	print("[test14] 二级角色觅食不死")
	var e := _setup()
	e.state.level = 2
	e.state.satiety = 12
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	var r := e.time.settle(_ts(2026, 10, 20, 0, 0))  # 10小时清醒
	_check(e.state.satiety == 10, "饱食度下限10")
	_check(e.state.health == 100 and not e.state.is_dead, "未死亡")
	_check(r.forage_occurred, "报告发生觅食")


## 测试15：二级角色离线很长时间，饱食度下限10
func _test_forage_floor_offline() -> void:
	print("[test15] 离线觅食下限")
	var e := _setup()
	e.state.level = 2
	e.state.satiety = 50
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e.time.settle(_ts(2026, 10, 20, 14, 0))  # 24小时清醒
	_check(e.state.satiety == 10, "饱食度下限10")
	_check(e.state.health == 100 and not e.state.is_dead, "未死亡")


## 测试16：leaf_restore=0 不无限循环
func _test_leaf_restore_zero() -> void:
	print("[test16] leaf_restore=0 不循环")
	var e := _setup()
	e.state.level = 2
	e.config.leaf_restore = 0
	e.state.satiety = 12
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e.time.settle(_ts(2026, 10, 19, 15, 0), true)  # 在线模拟
	_check(e.state.satiety == 10, "在线模拟 leaf_restore=0 下限保护（不扣穿阈值）")


## 测试17：死亡后后续结算不消耗
func _test_dead_no_consume() -> void:
	print("[test17] 死亡后不再消耗")
	var e := _setup()
	e.state.satiety = 0
	e.state.health = 1
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e.time.settle(_ts(2026, 10, 19, 15, 0))  # 死亡
	var satiety_dead := e.state.satiety
	var health_dead := e.state.health
	var r := e.time.settle(_ts(2026, 10, 19, 16, 0))
	_check(r.settled and r.satiety_consumed == 0 and r.health_consumed == 0, "死亡后无消耗")
	_check(e.state.satiety == satiety_dead and e.state.health == health_dead, "状态不变")


## 测试18：跨多日自动睡眠，睡眠区间不重叠不遗漏
func _test_multi_day_sleep() -> void:
	print("[test18] 跨多日睡眠")
	var e := _setup()
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 20, 0)
	var r := e.time.settle(_ts(2026, 10, 21, 10, 0))
	_check(r.sleep_seconds == 16 * 3600, "两晚共睡眠16小时")
	_check(r.awake_seconds == 22 * 3600, "清醒22小时")


## 测试19：睡眠区间都在结算范围内
func _test_intervals_in_range() -> void:
	print("[test19] 区间在结算范围内")
	var e := _setup()
	var from_ts := _ts(2026, 10, 19, 20, 0)
	var to_ts := _ts(2026, 10, 21, 10, 0)
	e.state.last_settlement_timestamp = from_ts
	var intervals := e.sleep.calculate_sleep_intervals(from_ts, to_ts)
	var ok := true
	for iv in intervals:
		var s := int(iv["start"])
		var en := int(iv["end"])
		if s < from_ts or en > to_ts or en <= s:
			ok = false
	_check(ok and intervals.size() == 2, "区间均在范围内且不重叠")


## 测试20：离线结算后睡眠状态与当前时间一致
func _test_state_sync() -> void:
	print("[test20] 睡眠状态同步")
	var e := _setup()
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 20, 0)
	e.time.settle(_ts(2026, 10, 20, 2, 0))  # 次日凌晨2点，应在自动睡眠
	_check(e.state.sleep_type == PetState.SleepType.AUTO_SLEEP, "凌晨2点处于自动睡眠")
	_check(e.state.scheduled_wake_timestamp == _ts(2026, 10, 20, 7, 0), "计划07:00苏醒")


## 测试21：在线觅食获得经验，遵守每日1点限制
func _test_online_forage_experience() -> void:
	print("[test21] 在线觅食经验")
	var e := _setup()
	e.state.level = 2
	e.state.satiety = 12
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 10, 0)
	e.time.settle(_ts(2026, 10, 19, 11, 0), true)  # 1小时清醒，触发觅食
	_check(e.state.experience == 1, "在线觅食获得1点经验")
	# 同日再次觅食（3小时清醒），不再获得经验
	e.time.settle(_ts(2026, 10, 19, 14, 0), true)
	_check(e.state.experience == 1, "同日重复觅食不超每日1点")


## 测试22：离线简化觅食不产生经验
func _test_offline_forage_no_experience() -> void:
	print("[test22] 离线觅食无经验")
	var e := _setup()
	e.state.level = 2
	e.state.satiety = 12
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	var r := e.time.settle(_ts(2026, 10, 20, 0, 0))  # 离线10小时
	_check(r.forage_occurred, "离线觅食发生（兜底）")
	_check(e.state.experience == 0, "离线不产生经验")


## 测试23：饱食度与生命值不出现负数
func _test_no_negative() -> void:
	print("[test23] 数值不为负")
	var e := _setup()
	e.state.satiety = 1
	e.state.health = 1
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e.time.settle(_ts(2026, 10, 20, 14, 0))  # 很长清醒
	_check(e.state.satiety >= 0 and e.state.health >= 0, "饱食度/生命值非负")
	_check(e.state.health == 0 and e.state.is_dead, "最终死亡且生命为0")


## 测试24：不同分段在无业务事件差异时消耗一致
func _test_segmentation_consistency() -> void:
	print("[test24] 分段一致性")
	var a := _setup()
	a.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	a.time.settle(_ts(2026, 10, 19, 15, 10))  # 一次70分钟

	var b := _setup()
	b.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	b.time.settle(_ts(2026, 10, 19, 14, 35))  # 两段
	b.time.settle(_ts(2026, 10, 19, 15, 10))

	_check(a.state.satiety == b.state.satiety, "两段与一段饱食度一致")
	_check(a.state.consumption_remainder == b.state.consumption_remainder, "余数一致")


# --- 工具 ---

class Env:
	var state: PetState
	var config: CharacterConfig
	var survival: SurvivalSystem
	var growth: GrowthSystem
	var sleep: SleepSystem
	var time: TimeSystem


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
