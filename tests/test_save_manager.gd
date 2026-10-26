extends SceneTree
## SaveManager 单元测试。使用独立临时存档路径（user://save_manager_tests/），不触碰真实存档。
## 运行方式：godot --headless --script res://tests/test_save_manager.gd


const TEST_DIR := "user://save_manager_tests"

var _passed := 0
var _failed := 0


func _init() -> void:
	_clean_test_dir()

	_test_roundtrip()
	_test_all_fields()
	_test_not_found()
	_test_invalid_json()
	_test_missing_field()
	_test_wrong_type()
	_test_illegal_values()
	_test_invalid_sleep_type()
	_test_version_unsupported()
	_test_save_failure()
	_test_load_no_partial_state()
	_test_remainder_and_dates_preserved()
	_test_repeated_save_load()
	_test_upper_bounds()
	_test_version_distinction()
	_test_no_path()

	print("")
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


## 1. 正常保存与加载
func _test_roundtrip() -> void:
	print("[save1] 正常保存与加载")
	var sm := SaveManager.new(_path("roundtrip"))
	var state := PetState.new()
	state.satiety = 55
	_check(sm.save(state) == SaveManager.SaveError.OK, "保存成功")
	_check(sm.has_save(), "存档存在")
	var r := sm.load()
	_check(r.ok and r.state != null, "加载成功")
	if r.ok:
		_check(r.state.satiety == 55, "状态恢复正确")


## 2. 所有字段往返一致
func _test_all_fields() -> void:
	print("[save2] 所有字段往返")
	var sm := SaveManager.new(_path("all_fields"))
	var state := PetState.new()
	state.health = 88
	state.satiety = 77
	state.is_dead = false
	state.level = 2
	state.experience = 1
	state.last_exp_date = "2026-10-19"
	state.sleep_type = PetState.SleepType.AUTO_SLEEP
	state.scheduled_wake_timestamp = 123456
	state.suppressed_auto_sleep_cycle = "2026-10-18"
	state.last_settlement_timestamp = 999999
	state.consumption_remainder = 1234
	sm.save(state)
	var r := sm.load()
	_check(r.ok, "加载成功")
	if r.ok:
		var s := r.state
		_check(s.health == 88 and s.satiety == 77 and s.is_dead == false, "生存字段一致")
		_check(s.level == 2 and s.experience == 1 and s.last_exp_date == "2026-10-19", "成长字段一致")
		_check(s.sleep_type == PetState.SleepType.AUTO_SLEEP and s.scheduled_wake_timestamp == 123456 and s.suppressed_auto_sleep_cycle == "2026-10-18", "睡眠字段一致")
		_check(s.last_settlement_timestamp == 999999 and s.consumption_remainder == 1234, "结算字段一致")


## 3. 文件不存在
func _test_not_found() -> void:
	print("[save3] 文件不存在")
	var sm := SaveManager.new(_path("nope"))
	var r := sm.load()
	_check(not r.ok and r.error == SaveManager.SaveError.NOT_FOUND, "返回 NOT_FOUND")


## 4. 非法 JSON
func _test_invalid_json() -> void:
	print("[save4] 非法 JSON")
	var sm := SaveManager.new(_path("bad_json"))
	_write_raw(sm.get_save_path(), "not valid { json")
	var r := sm.load()
	_check(not r.ok and r.error == SaveManager.SaveError.INVALID_JSON, "返回 INVALID_JSON")


## 5. 必填字段缺失
func _test_missing_field() -> void:
	print("[save5] 必填字段缺失")
	var d := _full_dict()
	d.erase("satiety")
	_write_save("missing_field", d)
	var r := SaveManager.new(_path("missing_field")).load()
	_check(not r.ok and r.error == SaveManager.SaveError.INVALID_DATA, "缺字段返回 INVALID_DATA")


## 6. 字段类型错误
func _test_wrong_type() -> void:
	print("[save6] 字段类型错误")
	var d := _full_dict()
	d["health"] = "abc"
	_write_save("wrong_type", d)
	var r := SaveManager.new(_path("wrong_type")).load()
	_check(not r.ok and r.error == SaveManager.SaveError.INVALID_DATA, "类型错误返回 INVALID_DATA")


## 7. 非法数据（负数/等级0等）
func _test_illegal_values() -> void:
	print("[save7] 非法数据")
	var cases := [
		["neg_health", "health", -1],
		["neg_satiety", "satiety", -5],
		["level_zero", "level", 0],
		["neg_exp", "experience", -2],
		["neg_remainder", "consumption_remainder", -1],
		["remainder_too_big", "consumption_remainder", 3600],
	]
	for c in cases:
		var d := _full_dict()
		d[c[1]] = c[2]
		_write_save(c[0], d)
		var r := SaveManager.new(_path(c[0])).load()
		_check(not r.ok and r.error == SaveManager.SaveError.INVALID_DATA, "%s 非法被拒绝" % c[0])


## 8. 无效睡眠类型
func _test_invalid_sleep_type() -> void:
	print("[save8] 无效睡眠类型")
	for st in [3, -1, 99]:
		var d := _full_dict()
		d["sleep_type"] = st
		_write_save("bad_sleep_%d" % st, d)
		var r := SaveManager.new(_path("bad_sleep_%d" % st)).load()
		_check(not r.ok and r.error == SaveManager.SaveError.INVALID_DATA, "sleep_type=%d 非法被拒绝" % st)


## 9. 不支持的版本
func _test_version_unsupported() -> void:
	print("[save9] 版本不支持")
	var sm := SaveManager.new(_path("old_version"))
	_write_raw(sm.get_save_path(), JSON.stringify({"save_version": 99, "pet_state": _full_dict()}))
	var r := sm.load()
	_check(not r.ok and r.error == SaveManager.SaveError.VERSION_UNSUPPORTED, "返回 VERSION_UNSUPPORTED")


## 10. 保存失败（无路径 / 父路径为文件）
func _test_save_failure() -> void:
	print("[save10] 保存失败")
	var no_path := SaveManager.new("")
	_check(no_path.save(PetState.new()) == SaveManager.SaveError.NO_PATH, "空路径返回 NO_PATH")

	# 父路径是文件 → 无法创建目录/写入
	var blocker := _path("blocker")
	_write_raw(blocker, "x")  # 创建一个文件作为“目录”
	var sm := SaveManager.new(blocker + "/save.json")
	_check(sm.save(PetState.new()) == SaveManager.SaveError.WRITE_FAILED, "父路径为文件返回 WRITE_FAILED")


## 11. 加载失败不留下半恢复状态
func _test_load_no_partial_state() -> void:
	print("[save11] 加载失败不半恢复")
	var sm := SaveManager.new(_path("partial"))
	_write_raw(sm.get_save_path(), "{ broken")
	var r := sm.load()
	_check(not r.ok and r.state == null, "失败时无状态对象返回")


## 12. 余数/日期/取消标记保留
func _test_remainder_and_dates_preserved() -> void:
	print("[save12] 关键字段跨存读保留")
	var sm := SaveManager.new(_path("key_fields"))
	var state := PetState.new()
	state.consumption_remainder = 3599
	state.last_exp_date = "2026-10-20"
	state.suppressed_auto_sleep_cycle = "2026-10-19"
	sm.save(state)
	var r := sm.load()
	_check(r.ok and r.state.consumption_remainder == 3599 and r.state.last_exp_date == "2026-10-20" and r.state.suppressed_auto_sleep_cycle == "2026-10-19", "余数/日期/取消标记保留")


## 13. 重复保存加载不改状态
func _test_repeated_save_load() -> void:
	print("[save13] 重复保存加载")
	var sm := SaveManager.new(_path("repeat"))
	var state := PetState.new()
	state.satiety = 66
	sm.save(state)
	sm.save(state)
	var r := sm.load()
	_check(r.ok and r.state.satiety == 66 and r.state.consumption_remainder == 0, "重复保存加载状态不变")


## 14. 业务上限校验（依赖 CharacterConfig）
func _test_upper_bounds() -> void:
	print("[save14] 业务上限校验")
	var config := CharacterConfig.new()
	var cases := [
		["health_over", "health", config.max_health + 1],
		["satiety_over", "satiety", config.max_satiety + 1],
		["level_over", "level", config.max_level + 1],
	]
	for c in cases:
		var d := _full_dict()
		d[c[1]] = c[2]
		_write_save(c[0], d)
		var r := SaveManager.new(_path(c[0])).load(config)
		_check(not r.ok and r.error == SaveManager.SaveError.INVALID_DATA, "%s 超上限被拒绝" % c[0])


## 15. 版本字段缺失/类型错误 与 版本不支持 的区分
func _test_version_distinction() -> void:
	print("[save15] 版本字段区分")
	_write_raw(_path("no_version"), JSON.stringify({"pet_state": _full_dict()}))
	var r1 := SaveManager.new(_path("no_version")).load()
	_check(not r1.ok and r1.error == SaveManager.SaveError.INVALID_DATA, "版本字段缺失 → INVALID_DATA")

	_write_raw(_path("bad_version_type"), JSON.stringify({"save_version": "1", "pet_state": _full_dict()}))
	var r2 := SaveManager.new(_path("bad_version_type")).load()
	_check(not r2.ok and r2.error == SaveManager.SaveError.INVALID_DATA, "版本字段类型错误 → INVALID_DATA")


## 16. 未设置路径 → NO_PATH
func _test_no_path() -> void:
	print("[save16] 未设置路径")
	var sm := SaveManager.new("")
	_check(sm.save(PetState.new()) == SaveManager.SaveError.NO_PATH, "save 返回 NO_PATH")
	_check(sm.load().error == SaveManager.SaveError.NO_PATH, "load 返回 NO_PATH")


# --- 工具 ---

func _path(name: String) -> String:
	return "%s/%s.json" % [TEST_DIR, name]


func _full_dict() -> Dictionary:
	return {
		"health": 100, "satiety": 100, "is_dead": false, "level": 1,
		"experience": 0, "last_exp_date": "", "sleep_type": 0,
		"scheduled_wake_timestamp": 0, "suppressed_auto_sleep_cycle": "",
		"last_settlement_timestamp": 1000, "consumption_remainder": 0,
	}


func _write_save(name: String, pet_state: Dictionary) -> void:
	_write_raw(_path(name), JSON.stringify({"save_version": 1, "pet_state": pet_state}))


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


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok    " + label)
	else:
		_failed += 1
		print("  FAIL  " + label)
