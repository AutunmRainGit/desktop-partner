extends SceneTree
## GameManager 单元测试。使用独立临时存档路径（user://game_manager_tests/）。
## 运行方式：godot --headless --script res://tests/test_game_manager.gd


const TEST_DIR := "user://game_manager_tests"

var _passed := 0
var _failed := 0


class Env:
	var sm: SaveManager
	var config: CharacterConfig
	var gm: GameManager


func _init() -> void:
	_clean_test_dir()

	_test_new_character()
	_test_restore()
	_test_offline_settlement()
	_test_no_double_settlement()
	_test_shared_state()
	_test_feed_bread()
	_test_click_pet_daily_limit()
	_test_sleep_wake()
	_test_settle_saves()
	_test_corrupt_save()
	_test_save_failure_surfaced()
	_test_death_handling()
	_test_before_init()
	_test_null_dependency()
	_test_wake_only_feed()
	_test_wake_only_click()
	_test_sleep_expired()

	print("")
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


## 1. 无存档时创建新角色
func _test_new_character() -> void:
	print("[gm1] 无存档创建新角色")
	var e := _make_env("new")
	var r := e.gm.initialize(_ts(2026, 10, 19, 10, 0))
	_check(r.ok and r.is_new, "新角色创建成功")
	_check(e.gm.get_state().last_settlement_timestamp == _ts(2026, 10, 19, 10, 0), "新角色结算时间=显式 now")
	_check(e.gm.get_state().satiety == 100 and e.gm.get_state().level == 1, "初始状态正确")


## 2. 有存档时恢复角色
func _test_restore() -> void:
	print("[gm2] 恢复角色")
	var sm := SaveManager.new(_path("restore"))
	var s := PetState.new()
	s.satiety = 42
	s.level = 2
	s.last_settlement_timestamp = _ts(2026, 10, 19, 10, 0)
	sm.save(s)
	var gm := GameManager.new(sm, CharacterConfig.new())
	var r := gm.initialize(_ts(2026, 10, 19, 10, 0))
	_check(r.ok and not r.is_new, "恢复角色成功")
	_check(gm.get_state().satiety == 42 and gm.get_state().level == 2, "恢复字段正确")


## 3. 恢复不覆盖原结算时间戳，且正确执行离线结算
func _test_offline_settlement() -> void:
	print("[gm3] 离线结算")
	var sm := SaveManager.new(_path("offline"))
	var s := PetState.new()
	s.last_settlement_timestamp = _ts(2026, 10, 19, 20, 0)
	s.satiety = 100
	sm.save(s)
	var gm := GameManager.new(sm, CharacterConfig.new())
	var r := gm.initialize(_ts(2026, 10, 20, 10, 0))
	_check(r.ok, "初始化成功")
	_check(gm.get_state().satiety == 66, "离线结算正确（原时间戳未被覆盖）")
	_check(gm.get_state().last_settlement_timestamp == _ts(2026, 10, 20, 10, 0), "结算后时间戳=now")


## 4. 不会重复结算同一段离线时间
func _test_no_double_settlement() -> void:
	print("[gm4] 不重复结算")
	var gm := GameManager.new(SaveManager.new(_path("offline")), CharacterConfig.new())
	var r := gm.initialize(_ts(2026, 10, 20, 10, 0))
	_check(r.ok and gm.get_state().satiety == 66, "二次初始化不重复结算")


## 5. 所有领域服务引用同一个 PetState
func _test_shared_state() -> void:
	print("[gm5] 共享状态")
	var e := _make_env("shared")
	e.gm.initialize(_ts(2026, 10, 19, 10, 0))
	var st := e.gm.get_state()
	e.gm.get_survival().apply_consumption(10)
	_check(st.satiety == 90, "SurvivalSystem 写入共享 state")
	e.gm.get_sleep().start_manual_sleep(_ts(2026, 10, 19, 14, 0))
	_check(st.sleep_type == PetState.SleepType.ACTIVE_SLEEP, "SleepSystem 写入共享 state")
	_check(not e.gm.get_growth().can_auto_forage(), "GrowthSystem 读取共享 state")


## 6. 喂食操作（清醒）
func _test_feed_bread() -> void:
	print("[gm6] 喂食操作")
	var e := _make_env("feed")
	e.gm.initialize(_ts(2026, 10, 19, 10, 0))
	e.gm.get_state().satiety = 50
	_check(e.gm.feed_bread(_ts(2026, 10, 19, 10, 0)) == GameManager.ActionResult.DONE, "清醒时喂食成功")
	_check(e.gm.get_state().satiety == 80, "面包恢复 30 点")


## 7. 点击经验遵守每日上限
func _test_click_pet_daily_limit() -> void:
	print("[gm7] 点击经验每日上限")
	var e := _make_env("click")
	e.gm.initialize(_ts(2026, 10, 19, 10, 0))
	var r1 := e.gm.click_pet(_ts(2026, 10, 19, 11, 0))
	_check(r1 == GameManager.ActionResult.DONE, "首次点击获得经验")
	var r2 := e.gm.click_pet(_ts(2026, 10, 19, 12, 0))
	_check(r2 == GameManager.ActionResult.REJECTED, "同日再次点击被拒绝")


## 8. 睡眠与唤醒
func _test_sleep_wake() -> void:
	print("[gm8] 睡眠与唤醒")
	var e := _make_env("sleep")
	e.gm.initialize(_ts(2026, 10, 19, 10, 0))
	_check(e.gm.start_manual_sleep(_ts(2026, 10, 19, 14, 0)), "主动睡眠")
	_check(e.gm.get_state().sleep_type == PetState.SleepType.ACTIVE_SLEEP, "已入睡")
	_check(e.gm.wake_up(_ts(2026, 10, 19, 14, 30)), "唤醒")
	_check(e.gm.get_state().sleep_type == PetState.SleepType.AWAKE, "已清醒")


## 9. 结算后保存
func _test_settle_saves() -> void:
	print("[gm9] 结算后保存")
	var e := _make_env("settle_save")
	e.gm.initialize(_ts(2026, 10, 19, 10, 0))
	e.gm.get_state().satiety = 100
	e.gm.settle(_ts(2026, 10, 19, 11, 0))
	_check(e.gm.get_state().satiety == 97, "在线结算正确")
	var r := e.sm.load()
	_check(r.ok and r.state.satiety == 97, "结算后已保存")


## 10. 存档损坏时明确策略
func _test_corrupt_save() -> void:
	print("[gm10] 存档损坏")
	var sm := SaveManager.new(_path("corrupt"))
	_write_raw(sm.get_save_path(), "{ not json")
	var gm := GameManager.new(sm, CharacterConfig.new())
	var r := gm.initialize(_ts(2026, 10, 19, 10, 0))
	_check(not r.ok and r.error == GameManager.InitError.SAVE_CORRUPT, "损坏存档返回 SAVE_CORRUPT")


## 11. 保存失败错误传递给调用方
func _test_save_failure_surfaced() -> void:
	print("[gm11] 保存失败传递")
	var blocker := _path("blocker")
	_write_raw(blocker, "x")
	var gm := GameManager.new(SaveManager.new(blocker + "/save.json"), CharacterConfig.new())
	var r := gm.initialize(_ts(2026, 10, 19, 10, 0))
	_check(not r.ok and r.error == GameManager.InitError.SAVE_FAILED, "保存失败返回 SAVE_FAILED")
	_check(gm.last_save_error == SaveManager.SaveError.WRITE_FAILED, "错误码传递给调用方")


## 12. 死亡状态处理
func _test_death_handling() -> void:
	print("[gm12] 死亡状态处理")
	var sm := SaveManager.new(_path("dead"))
	var s := PetState.new()
	s.is_dead = true
	s.satiety = 0
	s.health = 0
	s.last_settlement_timestamp = _ts(2026, 10, 19, 10, 0)
	sm.save(s)
	var gm := GameManager.new(sm, CharacterConfig.new())
	var r := gm.initialize(_ts(2026, 10, 19, 11, 0))
	_check(r.ok and gm.get_state().is_dead, "死亡角色可加载且保持死亡")
	_check(gm.feed_bread(_ts(2026, 10, 19, 11, 0)) == GameManager.ActionResult.REJECTED, "死亡角色无法喂食")
	_check(gm.click_pet(_ts(2026, 10, 19, 11, 0)) == GameManager.ActionResult.REJECTED, "死亡角色无法点击")


## 13. 初始化前调用各公开方法
func _test_before_init() -> void:
	print("[gm13] 初始化前调用")
	var gm := GameManager.new(SaveManager.new(_path("before_init")), CharacterConfig.new())
	var r_settle := gm.settle(_ts(2026, 10, 19, 10, 0))
	_check(not r_settle.settled, "未初始化 settle 返回未结算")
	_check(gm.save() != SaveManager.SaveError.OK, "未初始化 save 返回错误")
	_check(gm.feed_bread(_ts(2026, 10, 19, 10, 0)) == GameManager.ActionResult.REJECTED, "未初始化 feed 返回 REJECTED")
	_check(gm.click_pet(_ts(2026, 10, 19, 10, 0)) == GameManager.ActionResult.REJECTED, "未初始化 click 返回 REJECTED")
	_check(not gm.start_manual_sleep(_ts(2026, 10, 19, 10, 0)), "未初始化 start_manual_sleep 返回 false")
	_check(not gm.wake_up(_ts(2026, 10, 19, 10, 0)), "未初始化 wake_up 返回 false")
	_check(gm.get_state() == null, "未初始化 state 为 null")


## 14. null 依赖
func _test_null_dependency() -> void:
	print("[gm14] null 依赖")
	var gm := GameManager.new(null, CharacterConfig.new())
	var r := gm.initialize(_ts(2026, 10, 19, 10, 0))
	_check(not r.ok and r.error == GameManager.InitError.SAVE_CORRUPT, "null SaveManager 初始化失败不崩溃")


## 15. 睡眠时第一次喂食只唤醒、不喂食
func _test_wake_only_feed() -> void:
	print("[gm15] 睡眠中喂食只唤醒")
	var e := _make_env("wake_feed")
	e.gm.initialize(_ts(2026, 10, 19, 10, 0))
	e.gm.start_manual_sleep(_ts(2026, 10, 19, 10, 0))  # 白天小睡到 11:00
	e.gm.get_state().satiety = 50
	var r := e.gm.feed_bread(_ts(2026, 10, 19, 10, 0))  # 仍在睡眠
	_check(r == GameManager.ActionResult.WOKE_UP, "睡眠中喂食返回 WOKE_UP")
	_check(e.gm.get_state().satiety == 50, "未喂食（饱食度不变）")
	_check(e.gm.get_state().sleep_type == PetState.SleepType.AWAKE, "已唤醒")


## 16. 睡眠时第一次点击只唤醒、不获得经验
func _test_wake_only_click() -> void:
	print("[gm16] 睡眠中点击只唤醒")
	var e := _make_env("wake_click")
	e.gm.initialize(_ts(2026, 10, 19, 10, 0))
	e.gm.start_manual_sleep(_ts(2026, 10, 19, 10, 0))
	var r := e.gm.click_pet(_ts(2026, 10, 19, 10, 0))
	_check(r == GameManager.ActionResult.WOKE_UP, "睡眠中点击返回 WOKE_UP")
	_check(e.gm.get_state().experience == 0, "未获得经验")
	_check(e.gm.get_state().sleep_type == PetState.SleepType.AWAKE, "已唤醒")


## 17. 睡眠计划已过期时，操作按正确时间状态执行
func _test_sleep_expired() -> void:
	print("[gm17] 睡眠计划过期后操作")
	var e := _make_env("sleep_expired")
	e.gm.initialize(_ts(2026, 10, 19, 10, 0))
	e.gm.start_manual_sleep(_ts(2026, 10, 19, 10, 0))  # 小睡到 11:00
	e.gm.get_state().satiety = 50
	var r := e.gm.feed_bread(_ts(2026, 10, 19, 11, 0))  # 11:00 已自然清醒
	_check(r == GameManager.ActionResult.DONE, "睡眠过期后喂食正常执行")
	_check(e.gm.get_state().satiety == 78, "推进 1 小时睡眠(扣2)后喂食 +30 = 78")
	_check(e.gm.get_state().sleep_type == PetState.SleepType.AWAKE, "已清醒")


# --- 工具 ---

func _make_env(name: String) -> Env:
	var e := Env.new()
	e.config = CharacterConfig.new()
	e.sm = SaveManager.new(_path(name))
	e.gm = GameManager.new(e.sm, e.config)
	return e


func _path(name: String) -> String:
	return "%s/%s.json" % [TEST_DIR, name]


func _write_raw(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


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
