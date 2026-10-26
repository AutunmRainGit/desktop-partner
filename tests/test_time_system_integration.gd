extends SceneTree
## TimeSystem 领域层集成测试：以真实构造函数组装全部领域服务，共享同一 PetState。
## 运行方式：godot --headless --script res://tests/test_time_system_integration.gd
## 全部使用固定本地时间戳，不依赖真实时钟、等待或随机。


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
	_test_A_basic()
	_test_B_consumption()
	_test_C_survival_death()
	_test_D_forage()
	_test_E_sleep()
	_test_F_collaboration()

	print("")
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


# --- A. 基本时间结算（1~6） ---

func _test_A_basic() -> void:
	print("[A] 基本时间结算")

	# A1 正常结算
	var e := _setup()
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	var r := e.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(r.settled and e.state.satiety == 97, "A1 正常结算消耗3点")

	# A2 重复结算
	var sat := e.state.satiety
	var r2 := e.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(not r2.settled and e.state.satiety == sat, "A2 重复结算不重复扣除")

	# A3 时间倒退
	var r3 := e.time.settle(_ts(2026, 10, 19, 13, 0))
	_check(not r3.settled and e.state.satiety == sat, "A3 时间倒退无负消耗")

	# A4 相同时间
	var r4 := e.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(not r4.settled, "A4 相同时间无有效结算")

	# A5 结算结果字段
	var e5 := _setup()
	e5.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	var r5 := e5.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(r5.settled and r5.from_timestamp == _ts(2026, 10, 19, 14, 0) and r5.to_timestamp == _ts(2026, 10, 19, 15, 0) and r5.satiety_consumed == 3 and r5.health_consumed == 0 and not r5.is_dead, "A5 结算结果字段正确")

	# A6 已死亡角色
	var e6 := _setup()
	e6.state.is_dead = true
	e6.state.satiety = 40
	e6.state.health = 50
	e6.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	var r6 := e6.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(r6.settled and r6.satiety_consumed == 0 and r6.health_consumed == 0 and e6.state.satiety == 40 and e6.state.health == 50 and e6.state.last_settlement_timestamp == _ts(2026, 10, 19, 15, 0), "A6 死亡角色不消耗且推进时间戳")


# --- B. 饱食度消耗与余数（7~13） ---

func _test_B_consumption() -> void:
	print("[B] 饱食度消耗与余数")

	# B7 清醒消耗3/h
	var e := _setup()
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(e.state.satiety == 97, "B7 清醒1h消耗3点")

	# B8 睡眠消耗2/h
	var e8 := _setup()
	var now := _ts(2026, 10, 20, 0, 0)
	e8.state.last_settlement_timestamp = now - 3600
	e8.state.sleep_type = PetState.SleepType.ACTIVE_SLEEP
	e8.state.scheduled_wake_timestamp = now
	e8.time.settle(now)
	_check(e8.state.satiety == 98, "B8 睡眠1h消耗2点")

	# B9 余数保留
	var e9 := _setup()
	e9.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e9.time.settle(_ts(2026, 10, 19, 14, 10))
	_check(e9.state.consumption_remainder == 1800 and e9.state.satiety == 100, "B9 600秒余数1800不丢")

	# B10 跨结算累计
	var e10 := _setup()
	e10.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e10.time.settle(_ts(2026, 10, 19, 14, 10))
	e10.time.settle(_ts(2026, 10, 19, 14, 20))
	_check(e10.state.satiety == 99 and e10.state.consumption_remainder == 0, "B10 两次600秒累计1点")

	# B11 混合区间
	var e11 := _setup()
	e11.state.last_settlement_timestamp = _ts(2026, 10, 19, 22, 40)
	var r11 := e11.time.settle(_ts(2026, 10, 19, 23, 20))
	_check(r11.awake_seconds == 1200 and r11.sleep_seconds == 1200 and e11.state.satiety == 99 and e11.state.consumption_remainder == 2400, "B11 混合区间速率正确")

	# B12 余数边界
	var e12a := _setup()
	e12a.state.consumption_remainder = -100
	e12a.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e12a.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(e12a.state.satiety == 97, "B12 负余数被重置后正常结算")

	var e12b := _setup()
	e12b.state.consumption_remainder = 4000
	e12b.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e12b.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(e12b.state.satiety == 97, "B12 超范围余数被重置后正常结算")

	# B13 属性上限
	var e13 := _setup()
	e13.state.satiety = 95
	e13.survival.feed(30)
	_check(e13.state.satiety == 100, "B13 喂食不超过上限")
	e13.state.health = 95
	e13.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e13.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(e13.state.satiety >= 0 and e13.state.health >= 0, "B13 结算后无非负")


# --- C. 生存与死亡（14~18） ---

func _test_C_survival_death() -> void:
	print("[C] 生存与死亡")

	# C14 饱食充足只扣饱食
	var e := _setup()
	e.state.satiety = 50
	e.state.health = 100
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	var r := e.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(e.state.satiety == 47 and e.state.health == 100 and r.health_consumed == 0, "C14 饱食充足只扣饱食")

	# C15 饱食不足扣生命
	var e15 := _setup()
	e15.state.satiety = 2
	e15.state.health = 100
	e15.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	var r15 := e15.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(e15.state.satiety == 0 and e15.state.health == 99 and r15.health_consumed == 1, "C15 饱食不足按1:1扣生命")

	# C16 生命归零死亡标记一致
	var e16 := _setup()
	e16.state.satiety = 0
	e16.state.health = 2
	e16.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e16.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(e16.state.health == 0 and e16.state.is_dead == (e16.state.health == 0), "C16 生命归零死亡标记一致")

	# C17 死亡后不再消耗
	var sat_dead := e16.state.satiety
	var hp_dead := e16.state.health
	var r17 := e16.time.settle(_ts(2026, 10, 19, 16, 0))
	_check(r17.settled and r17.satiety_consumed == 0 and r17.health_consumed == 0 and e16.state.satiety == sat_dead and e16.state.health == hp_dead, "C17 死亡后不再消耗")

	# C18 统计与实际一致
	var e18 := _setup()
	e18.state.satiety = 2
	e18.state.health = 100
	e18.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	var sat0 := e18.state.satiety
	var hp0 := e18.state.health
	var r18 := e18.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(r18.satiety_consumed == sat0 - e18.state.satiety and r18.health_consumed == hp0 - e18.state.health, "C18 统计与实际状态变化一致")


# --- D. 自动觅食（19~30） ---

func _test_D_forage() -> void:
	print("[D] 自动觅食")

	# D19 未解锁等级不觅食
	var e19 := _setup()
	e19.state.satiety = 2
	e19.state.health = 100
	e19.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e19.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(e19.state.satiety == 0 and e19.state.health == 99, "D19 未解锁不觅食按普通规则")

	# D20 解锁判断
	var e20 := _setup()
	_check(not e20.growth.can_auto_forage(), "D20 1级未解锁")
	e20.state.level = 2
	_check(e20.growth.can_auto_forage(), "D20 2级已解锁")

	# D21 离线简化模式
	var e21 := _setup()
	e21.state.level = 2
	e21.state.satiety = 12
	e21.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	var r21 := e21.time.settle(_ts(2026, 10, 20, 0, 0))
	_check(e21.state.satiety == 10 and r21.forage_occurred and r21.forage_count == 0, "D21 离线下限10且forage_occurred")

	# D22 在线逐次模拟调用feed恢复
	var e22 := _setup()
	e22.state.level = 2
	e22.state.satiety = 12
	e22.state.last_settlement_timestamp = _ts(2026, 10, 19, 10, 0)
	var r22 := e22.time.settle(_ts(2026, 10, 19, 11, 0), true)
	_check(e22.state.satiety == 19 and r22.forage_count == 1, "D22 在线逐次模拟恢复饱食")

	# D23 恢复受上限限制
	var e23 := _setup()
	e23.state.level = 2
	e23.config.forage_threshold = 95
	e23.state.satiety = 100
	e23.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e23.time.settle(_ts(2026, 10, 19, 16, 0), true)
	_check(e23.state.satiety == 99 and e23.state.satiety <= e23.config.max_satiety, "D23 恢复受上限限制")

	# D24 经验每日上限
	var e24 := _setup()
	e24.state.level = 2
	e24.state.satiety = 12
	e24.state.last_settlement_timestamp = _ts(2026, 10, 19, 10, 0)
	e24.time.settle(_ts(2026, 10, 19, 11, 0), true)
	_check(e24.state.experience == 1, "D24 在线觅食获得1点经验")
	e24.time.settle(_ts(2026, 10, 19, 15, 0), true)
	_check(e24.state.experience == 1, "D24 同日觅食不超每日1点")

	# D25 每日经验共享（点击与觅食）
	var e25 := _setup()
	e25.state.level = 2
	e25.state.satiety = 12
	e25.state.last_settlement_timestamp = _ts(2026, 10, 19, 10, 0)
	e25.growth.gain_daily_experience("2026-10-19")  # 模拟点击
	e25.time.settle(_ts(2026, 10, 19, 11, 0), true)  # 在线觅食
	_check(e25.state.experience == 1, "D25 点击与觅食共享每日限制")

	# D26 leaf_restore=0 不循环
	var e26 := _setup()
	e26.state.level = 2
	e26.config.leaf_restore = 0
	e26.state.satiety = 12
	e26.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e26.time.settle(_ts(2026, 10, 19, 15, 0), true)
	_check(e26.state.satiety == 10, "D26 leaf_restore=0 下限保护不循环")

	# D27 无进展恢复退出
	var e27 := _setup()
	e27.state.level = 2
	e27.config.forage_threshold = e27.config.max_satiety
	e27.state.satiety = e27.config.max_satiety
	e27.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e27.time.settle(_ts(2026, 10, 19, 15, 0), true)
	_check(e27.state.satiety == 100, "D27 无进展恢复不循环不扣穿")

	# D28 阈值边界（高于/等于/低于）
	var e28 := _setup()
	e28.state.level = 2
	e28.state.satiety = 11
	e28.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e28.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(e28.state.satiety == 10, "D28 高于阈值消耗到下限")
	var e28b := _setup()
	e28b.state.level = 2
	e28b.state.satiety = 10
	e28b.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e28b.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(e28b.state.satiety == 10, "D28 等于阈值保持")
	var e28c := _setup()
	e28c.state.level = 2
	e28c.state.satiety = 5
	e28c.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e28c.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(e28c.state.satiety == 5, "D28 低于阈值不再下降")

	# D29 最高等级觅食正常
	var e29 := _setup()
	e29.state.level = 2
	e29.state.satiety = 12
	e29.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e29.time.settle(_ts(2026, 10, 20, 0, 0))
	_check(e29.state.satiety == 10 and e29.state.health == 100, "D29 2级(最高)觅食正常")

	# D30 长时间结算不无限循环
	var e30 := _setup()
	e30.state.level = 2
	e30.state.satiety = 50
	e30.state.last_settlement_timestamp = _ts(2026, 10, 19, 0, 0)
	e30.time.settle(_ts(2026, 10, 25, 0, 0))
	_check(e30.state.satiety == 10 and not e30.state.is_dead, "D30 长结算不循环不死")


# --- E. 睡眠与时间区间（31~38） ---

func _test_E_sleep() -> void:
	print("[E] 睡眠与时间区间")

	# E31 自动睡眠23:00~07:00
	var e := _setup()
	var iv := e.sleep.calculate_sleep_intervals(_ts(2026, 10, 19, 23, 0), _ts(2026, 10, 20, 7, 0))
	_check(iv.size() == 1 and int(iv[0]["start"]) == _ts(2026, 10, 19, 23, 0) and int(iv[0]["end"]) == _ts(2026, 10, 20, 7, 0), "E31 自动睡眠区间")

	# E32 白天主动睡眠1小时
	var e32 := _setup()
	_check(e32.sleep.start_manual_sleep(_ts(2026, 10, 19, 14, 0)) and e32.state.scheduled_wake_timestamp == _ts(2026, 10, 19, 15, 0), "E32 白天主动睡1小时")

	# E33 夜间主动睡眠次日08:00
	var e33 := _setup()
	e33.sleep.start_manual_sleep(_ts(2026, 10, 19, 19, 0))
	_check(e33.state.scheduled_wake_timestamp == _ts(2026, 10, 20, 8, 0), "E33 夜间主动睡到次日08:00")

	# E34 跨午夜
	var e34 := _setup()
	e34.state.last_settlement_timestamp = _ts(2026, 10, 19, 20, 0)
	var r34 := e34.time.settle(_ts(2026, 10, 20, 10, 0))
	_check(r34.sleep_seconds == 8 * 3600 and r34.awake_seconds == 6 * 3600, "E34 跨午夜正确区分")

	# E35 跨多天
	var e35 := _setup()
	e35.state.last_settlement_timestamp = _ts(2026, 10, 19, 20, 0)
	var r35 := e35.time.settle(_ts(2026, 10, 21, 10, 0))
	_check(r35.sleep_seconds == 16 * 3600, "E35 跨多天不重不漏")

	# E36 区间合法性
	var e36 := _setup()
	var from_ts := _ts(2026, 10, 19, 20, 0)
	var to_ts := _ts(2026, 10, 21, 10, 0)
	var intervals := e36.sleep.calculate_sleep_intervals(from_ts, to_ts)
	var total := 0
	var prev_end := from_ts
	var legal := true
	for x in intervals:
		var s := int(x["start"])
		var en := int(x["end"])
		if en <= s or s < prev_end or s < from_ts or en > to_ts:
			legal = false
		total += en - s
		prev_end = en
	_check(legal and total <= to_ts - from_ts, "E36 区间合法（无负/倒序/重叠/越界/总时长不超）")

	# E37 唤醒抑制
	var e37 := _setup()
	e37.sleep.start_auto_sleep(_ts(2026, 10, 19, 23, 0))
	e37.sleep.wake_up(_ts(2026, 10, 19, 23, 30))
	_check(e37.state.suppressed_auto_sleep_cycle == "2026-10-19" and not e37.sleep.start_auto_sleep(_ts(2026, 10, 20, 0, 30)), "E37 唤醒后本周期抑制")

	# E38 最终状态同步
	var e38 := _setup()
	e38.state.last_settlement_timestamp = _ts(2026, 10, 19, 20, 0)
	e38.time.settle(_ts(2026, 10, 20, 2, 0))
	_check(e38.state.sleep_type == PetState.SleepType.AUTO_SLEEP and e38.state.scheduled_wake_timestamp == _ts(2026, 10, 20, 7, 0), "E38 结算后睡眠状态同步")


# --- F. 结算结果与模块协作（39~45） ---

func _test_F_collaboration() -> void:
	print("[F] 结算结果与模块协作")

	# F39 结果字段
	var e := _setup()
	e.state.last_settlement_timestamp = _ts(2026, 10, 19, 20, 0)
	var r := e.time.settle(_ts(2026, 10, 20, 10, 0))
	_check(r.settled and r.from_timestamp == _ts(2026, 10, 19, 20, 0) and r.to_timestamp == _ts(2026, 10, 20, 10, 0) and r.awake_seconds == 6 * 3600 and r.sleep_seconds == 8 * 3600 and r.satiety_consumed == 34 and r.health_consumed == 0 and not r.is_dead and not r.forage_occurred and r.forage_count == 0, "F39 结果字段完整正确")

	# F40 睡眠区间与消耗一致
	_check(r.sleep_seconds * 2 + r.awake_seconds * 3 == r.satiety_consumed * 3600, "F40 睡眠区间与消耗一致")

	# F41 消耗作用于共享 state（经 SurvivalSystem）
	var e41 := _setup()
	var sat0 := e41.state.satiety
	e41.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e41.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(e41.state.satiety == sat0 - 3, "F41 消耗作用于共享state")

	# F42 经验经 GrowthSystem
	var e42 := _setup()
	e42.state.level = 2
	e42.state.satiety = 12
	e42.state.last_settlement_timestamp = _ts(2026, 10, 19, 10, 0)
	e42.time.settle(_ts(2026, 10, 19, 11, 0), true)
	_check(e42.state.experience == 1, "F42 在线觅食经验经GrowthSystem")

	# F43 睡眠状态由 SleepSystem 维护
	var e43 := _setup()
	e43.state.last_settlement_timestamp = _ts(2026, 10, 19, 20, 0)
	e43.time.settle(_ts(2026, 10, 20, 2, 0))
	_check(e43.state.sleep_type == PetState.SleepType.AUTO_SLEEP, "F43 睡眠状态由SleepSystem维护")

	# F44 重复调用无额外扣除
	var e44 := _setup()
	e44.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	e44.time.settle(_ts(2026, 10, 19, 15, 0))
	var sat44 := e44.state.satiety
	e44.time.settle(_ts(2026, 10, 19, 15, 0))
	_check(e44.state.satiety == sat44, "F44 重复调用无额外扣除")

	# F45 短结算与长结算一致
	var a := _setup()
	a.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	a.time.settle(_ts(2026, 10, 19, 15, 10))
	var b := _setup()
	b.state.last_settlement_timestamp = _ts(2026, 10, 19, 14, 0)
	b.time.settle(_ts(2026, 10, 19, 14, 35))
	b.time.settle(_ts(2026, 10, 19, 15, 10))
	_check(a.state.satiety == b.state.satiety and a.state.consumption_remainder == b.state.consumption_remainder, "F45 短结算与长结算一致")


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
