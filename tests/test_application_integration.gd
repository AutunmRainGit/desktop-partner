extends SceneTree
## SaveManager → GameManager → 领域系统 的协作测试。使用独立临时存档路径。
## 运行方式：godot --headless --script res://tests/test_application_integration.gd


const TEST_DIR := "user://app_integration_tests"

var _passed := 0
var _failed := 0


func _init() -> void:
	_clean_test_dir()

	_test_full_roundtrip()
	_test_remainder_survives_restart()
	_test_daily_exp_limit_survives_restart()
	_test_sleep_plan_survives_restart()
	_test_offline_settlement_uses_restored_state()
	_test_no_double_settlement_across_restart()

	print("")
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


## 完整初始化→操作→保存→重启→恢复流程
func _test_full_roundtrip() -> void:
	print("[app1] 完整往返")
	var path := _path("full")
	var gm1 := GameManager.new(SaveManager.new(path), CharacterConfig.new())
	var r1 := gm1.initialize(_ts(2026, 10, 19, 10, 0))
	_check(r1.ok and r1.is_new, "首次初始化新角色")
	gm1.feed_bread(_ts(2026, 10, 19, 10, 0))  # 100 → 100（已满）
	gm1.get_state().satiety = 50
	gm1.feed_bread(_ts(2026, 10, 19, 10, 0))  # 50 → 80
	gm1.click_pet(_ts(2026, 10, 19, 10, 0))   # 经验 +1（与初始化同时刻，避免时间推进消耗）

	var gm2 := GameManager.new(SaveManager.new(path), CharacterConfig.new())
	var r2 := gm2.initialize(_ts(2026, 10, 19, 10, 0))
	_check(r2.ok and not r2.is_new, "重启恢复角色")
	_check(gm2.get_state().satiety == 80 and gm2.get_state().experience == 1, "操作结果已持久化")


## 消耗余数跨重启保留
func _test_remainder_survives_restart() -> void:
	print("[app2] 余数跨重启")
	var path := _path("remainder")
	var sm := SaveManager.new(path)
	var s := PetState.new()
	s.last_settlement_timestamp = _ts(2026, 10, 19, 10, 0)
	s.consumption_remainder = 1800
	sm.save(s)

	var gm := GameManager.new(sm, CharacterConfig.new())
	gm.initialize(_ts(2026, 10, 19, 10, 0))  # now==last，无离线结算
	_check(gm.get_state().consumption_remainder == 1800, "余数跨重启保留")


## 每日经验限制跨重启保留
func _test_daily_exp_limit_survives_restart() -> void:
	print("[app3] 每日经验限制跨重启")
	var path := _path("exp_limit")
	var sm := SaveManager.new(path)
	var s := PetState.new()
	s.last_settlement_timestamp = _ts(2026, 10, 19, 10, 0)
	s.last_exp_date = "2026-10-19"  # 今天已获得经验
	sm.save(s)

	var gm := GameManager.new(sm, CharacterConfig.new())
	gm.initialize(_ts(2026, 10, 19, 10, 0))
	var r := gm.click_pet(_ts(2026, 10, 19, 11, 0))
	_check(r == GameManager.ActionResult.REJECTED, "重启后同日点击仍受每日限制")


## 睡眠计划与周期取消标记跨重启保留
func _test_sleep_plan_survives_restart() -> void:
	print("[app4] 睡眠状态跨重启")
	var path := _path("sleep")
	var sm := SaveManager.new(path)
	var s := PetState.new()
	s.last_settlement_timestamp = _ts(2026, 10, 19, 10, 0)
	s.sleep_type = PetState.SleepType.AUTO_SLEEP
	s.scheduled_wake_timestamp = _ts(2026, 10, 20, 7, 0)
	s.suppressed_auto_sleep_cycle = "2026-10-19"
	sm.save(s)

	var gm := GameManager.new(sm, CharacterConfig.new())
	gm.initialize(_ts(2026, 10, 19, 10, 0))
	_check(gm.get_state().sleep_type == PetState.SleepType.AUTO_SLEEP, "睡眠类型保留")
	_check(gm.get_state().scheduled_wake_timestamp == _ts(2026, 10, 20, 7, 0), "计划苏醒时间保留")
	_check(gm.get_state().suppressed_auto_sleep_cycle == "2026-10-19", "周期取消标记保留")


## 离线结算确实使用恢复的状态
func _test_offline_settlement_uses_restored_state() -> void:
	print("[app5] 离线结算使用恢复状态")
	var path := _path("offline")
	var sm := SaveManager.new(path)
	var s := PetState.new()
	s.last_settlement_timestamp = _ts(2026, 10, 19, 20, 0)
	s.satiety = 100
	sm.save(s)

	var gm := GameManager.new(sm, CharacterConfig.new())
	gm.initialize(_ts(2026, 10, 20, 10, 0))
	_check(gm.get_state().satiety == 66, "离线结算按恢复的时间戳执行（6h清醒+8h睡眠=34点）")


## 完整初始化+保存流程不重复结算
func _test_no_double_settlement_across_restart() -> void:
	print("[app6] 重启不重复结算")
	var path := _path("norepeat")
	var sm := SaveManager.new(path)
	var s := PetState.new()
	s.last_settlement_timestamp = _ts(2026, 10, 19, 20, 0)
	s.satiety = 100
	sm.save(s)

	var gm1 := GameManager.new(sm, CharacterConfig.new())
	gm1.initialize(_ts(2026, 10, 20, 10, 0))  # 结算 → 66 并保存
	_check(gm1.get_state().satiety == 66, "首次结算到 66")

	var gm2 := GameManager.new(SaveManager.new(path), CharacterConfig.new())
	gm2.initialize(_ts(2026, 10, 20, 10, 0))  # 再次初始化，不应重复结算
	_check(gm2.get_state().satiety == 66, "重启不重复结算（仍为 66）")


# --- 工具 ---

func _path(name: String) -> String:
	return "%s/%s.json" % [TEST_DIR, name]


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
