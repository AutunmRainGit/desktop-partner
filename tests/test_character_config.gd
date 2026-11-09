extends SceneTree
## CharacterConfig 单元测试。
## 运行方式：godot --headless --script res://tests/test_character_config.gd


var _passed := 0
var _failed := 0


func _init() -> void:
	_test_defaults()
	_test_resource_load()
	_test_validate()
	_test_sharing()
	_test_independence()
	print("")
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


## 测试1：默认配置
func _test_defaults() -> void:
	print("[test1] 默认配置")
	var c := CharacterConfig.new()
	_check(c.max_health == 100, "max_health == 100")
	_check(c.max_satiety == 100, "max_satiety == 100")
	_check(c.awake_consumption == 3, "awake_consumption == 3")
	_check(c.sleep_consumption == 2, "sleep_consumption == 2")
	_check(c.bread_restore == 30, "bread_restore == 30")
	_check(c.leaf_restore == 10, "leaf_restore == 10")
	_check(c.max_level == 10, "max_level == 10")
	_check(c.level_up_exp == 2, "level_up_exp == 2")
	_check(c.forage_unlock_level == 2, "forage_unlock_level == 2")
	_check(c.forage_threshold == 10, "forage_threshold == 10")


## 测试2：配置资源加载
func _test_resource_load() -> void:
	print("[test2] 配置资源加载")
	var res := ResourceLoader.load("res://resources/character_config.tres") as CharacterConfig
	_check(res != null, "资源存在、加载成功且类型为 CharacterConfig")
	if res == null:
		return
	_check(res.get_script() != null, "脚本已附加")
	_check(res.max_health == 100 and res.max_satiety == 100 and res.awake_consumption == 3, "加载后配置值正确")


## 测试3：配置合法性
func _test_validate() -> void:
	print("[test3] 配置合法性校验")
	var ok := CharacterConfig.new()
	_check(ok.validate().is_empty(), "默认配置合法（validate 为空）")

	_expect_error("max_health", 0, "max_health <= 0")
	_expect_error("max_satiety", 0, "max_satiety <= 0")
	_expect_error("awake_consumption", -1, "awake_consumption < 0")
	_expect_error("sleep_consumption", -1, "sleep_consumption < 0")
	_expect_error("bread_restore", -1, "bread_restore < 0")
	_expect_error("leaf_restore", -1, "leaf_restore < 0")
	_expect_error("max_level", 0, "max_level < 1")
	_expect_error("level_up_exp", 0, "level_up_exp <= 0")
	_expect_error("forage_unlock_level", 0, "forage_unlock_level < 1")
	_expect_error("forage_unlock_level", 11, "forage_unlock_level > max_level")
	_expect_error("forage_threshold", 200, "forage_threshold > max_satiety")


## 测试4：Resource 共享
func _test_sharing() -> void:
	print("[test4] Resource 共享")
	var a := ResourceLoader.load("res://resources/character_config.tres") as CharacterConfig
	var b := ResourceLoader.load("res://resources/character_config.tres") as CharacterConfig
	_check(a != null and b != null, "两次加载均成功")
	if a == null or b == null:
		return
	_check(a == b, "相同路径返回同一实例（引用共享）")
	_check(a.max_satiety == b.max_satiety and a.max_satiety == 100, "共享实例读到相同配置值")


## 测试5：独立性
func _test_independence() -> void:
	print("[test5] 独立性")
	var c := CharacterConfig.new()
	_check(c != null, "可直接实例化，无需 PetState/场景/其它系统")
	_check(c is Resource, "继承自 Resource")
	_check(c.max_level == 10, "实例化后具备默认配置")


## 辅助：校验错误数组中是否包含指定字段名
func _has_error(errors: Array[String], field: String) -> bool:
	for e in errors:
		if e.contains(field):
			return true
	return false


## 辅助：构造非法配置并断言能检出对应错误
func _expect_error(prop: String, value: int, label: String) -> void:
	var c := CharacterConfig.new()
	c.set(prop, value)
	_check(_has_error(c.validate(), prop), label)


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok    " + label)
	else:
		_failed += 1
		print("  FAIL  " + label)
