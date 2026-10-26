class_name SaveManager
extends RefCounted
## 基础设施层：存档管理。
## 负责 PetState ↔ JSON ↔ 文件的序列化、反序列化与校验；不实现任何业务规则。
## 存档路径可注入。load 可传入 CharacterConfig 用于补全“业务不变量”上限校验（健康/饱食/等级）。
## 时间戳统一约束为 >= 0（本项目仅面向现代桌宠运行场景，不涉及 1970 年之前的时间）。


enum SaveError {
	OK = 0,               ## 成功
	NOT_FOUND,            ## 存档不存在
	READ_FAILED,          ## 读取失败
	WRITE_FAILED,         ## 写入失败
	INVALID_JSON,         ## JSON 无效
	VERSION_UNSUPPORTED,  ## 版本合法但不支持
	INVALID_DATA,         ## 字段缺失/类型错误/取值非法/格式非法
	NO_PATH,              ## 未设置存档路径
}


## 加载结果：ok + 恢复出的状态（或错误码）。
class LoadResult:
	var ok: bool = false
	var error: SaveError = SaveError.OK
	var state: PetState = null


const SAVE_VERSION := 1
const KEY_VERSION := "save_version"
const KEY_PET_STATE := "pet_state"

# 每 3600 消耗单位 = 1 点饥饿值，余数合法范围为 [0, 3600)
const REMAINDER_MAX := 3600


var _path: String = ""


func _init(path: String = "") -> void:
	_path = path


func set_save_path(path: String) -> void:
	_path = path


func get_save_path() -> String:
	return _path


## 存档是否存在。
func has_save() -> bool:
	return _path != "" and FileAccess.file_exists(_path)


## 保存 PetState 到 JSON 文件。返回 SaveError。
## 采用“临时文件 + 备份 + 替换”策略，避免先删除唯一有效存档：
##   旧存档 → .bak（保留恢复能力）；.tmp → 正式文件；成功后再删除 .bak；替换失败则恢复 .bak。
## 说明：这仍不是严格跨平台原子替换，但任何一步失败都不会把旧存档置于“已删除且无恢复”的状态。
func save(state: PetState) -> SaveError:
	if _path == "":
		return SaveError.NO_PATH

	var data := {
		KEY_VERSION: SAVE_VERSION,
		KEY_PET_STATE: _state_to_dict(state),
	}
	var json_string := JSON.stringify(data)
	if json_string.is_empty():
		return SaveError.WRITE_FAILED

	var dir_path := _path.get_base_dir()
	if dir_path != "" and dir_path != ".":
		var mk_err := DirAccess.make_dir_recursive_absolute(dir_path)
		if mk_err != OK:
			push_warning("SaveManager: 无法创建存档目录: " + dir_path)
			return SaveError.WRITE_FAILED

	# 先完整写入临时文件
	var tmp_path := _path + ".tmp"
	var tmp := FileAccess.open(tmp_path, FileAccess.WRITE)
	if tmp == null:
		return SaveError.WRITE_FAILED
	tmp.store_string(json_string)
	tmp.close()

	var dir := DirAccess.open(dir_path)
	if dir == null:
		return SaveError.WRITE_FAILED
	var file_name := _path.get_file()
	var tmp_name := file_name + ".tmp"
	var bak_name := file_name + ".bak"

	# 清理可能存在的陈旧备份
	if dir.file_exists(bak_name):
		dir.remove(bak_name)
	# 旧存档改名为备份（不是删除，保留恢复能力）
	if dir.file_exists(file_name):
		if dir.rename(file_name, bak_name) != OK:
			_remove_if_exists(dir, tmp_name)  # 清理临时文件
			return SaveError.WRITE_FAILED
	# 临时文件替换为正式文件
	if dir.rename(tmp_name, file_name) != OK:
		# 失败：从备份恢复旧存档，并清理临时文件
		if dir.file_exists(bak_name):
			dir.rename(bak_name, file_name)
		_remove_if_exists(dir, tmp_name)
		return SaveError.WRITE_FAILED
	# 成功：删除备份
	if dir.file_exists(bak_name):
		dir.remove(bak_name)
	return SaveError.OK


## 清理临时/备份文件（存在则删除）。
func _remove_if_exists(dir: DirAccess, name: String) -> void:
	if dir.file_exists(name):
		dir.remove(name)


## 读取、解析并校验存档。返回 LoadResult。
## config 非空时，额外校验业务上限（health<=max_health、satiety<=max_satiety、level<=max_level）。
## 仅在全部校验通过后才构建 PetState，失败时不留下半恢复的状态。
func load(config: CharacterConfig = null) -> LoadResult:
	var result := LoadResult.new()
	if _path == "":
		result.error = SaveError.NO_PATH
		return result
	if not FileAccess.file_exists(_path):
		result.error = SaveError.NOT_FOUND
		return result

	var f := FileAccess.open(_path, FileAccess.READ)
	if f == null:
		result.error = SaveError.READ_FAILED
		return result
	var text := f.get_as_text()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		result.error = SaveError.INVALID_JSON
		return result

	# 版本字段缺失/类型错误 = 格式错误；版本合法但不支持 = 版本错误
	if not _has_int(parsed, KEY_VERSION):
		result.error = SaveError.INVALID_DATA
		return result
	if int(parsed[KEY_VERSION]) != SAVE_VERSION:
		result.error = SaveError.VERSION_UNSUPPORTED
		return result

	var state := _dict_to_state(parsed.get(KEY_PET_STATE, null), config)
	if state == null:
		result.error = SaveError.INVALID_DATA
		return result

	result.ok = true
	result.state = state
	return result


# --- 序列化 ---

func _state_to_dict(state: PetState) -> Dictionary:
	return {
		"health": state.health,
		"satiety": state.satiety,
		"is_dead": state.is_dead,
		"level": state.level,
		"experience": state.experience,
		"last_exp_date": state.last_exp_date,
		"sleep_type": int(state.sleep_type),
		"scheduled_wake_timestamp": state.scheduled_wake_timestamp,
		"suppressed_auto_sleep_cycle": state.suppressed_auto_sleep_cycle,
		"last_settlement_timestamp": state.last_settlement_timestamp,
		"consumption_remainder": state.consumption_remainder,
	}


## 校验并构建 PetState；任一字段不合法返回 null（不做半恢复）。
## 结构校验：类型、下限、枚举/余数范围、日期格式、时间戳 >= 0。
## 业务上限校验：仅在 config 非空时执行（health/satiety/level 上限）。
## 说明：experience 仅校验 >= 0——领域模型中满级后经验可无限累计、升级时归零，无干净上限。
func _dict_to_state(dict, config) -> PetState:
	if typeof(dict) != TYPE_DICTIONARY:
		return null
	if not _has_int(dict, "health") or int(dict["health"]) < 0:
		return null
	if not _has_int(dict, "satiety") or int(dict["satiety"]) < 0:
		return null
	if not _has_bool(dict, "is_dead"):
		return null
	if not _has_int(dict, "level") or int(dict["level"]) < 1:
		return null
	if not _has_int(dict, "experience") or int(dict["experience"]) < 0:
		return null
	if not _has_str(dict, "last_exp_date") or not _valid_date_or_empty(str(dict["last_exp_date"])):
		return null
	if not _has_int(dict, "sleep_type") or int(dict["sleep_type"]) < 0 or int(dict["sleep_type"]) > 2:
		return null
	if not _has_int(dict, "scheduled_wake_timestamp") or int(dict["scheduled_wake_timestamp"]) < 0:
		return null
	if not _has_str(dict, "suppressed_auto_sleep_cycle") or not _valid_date_or_empty(str(dict["suppressed_auto_sleep_cycle"])):
		return null
	if not _has_int(dict, "last_settlement_timestamp") or int(dict["last_settlement_timestamp"]) < 0:
		return null
	if not _has_int(dict, "consumption_remainder") or int(dict["consumption_remainder"]) < 0 or int(dict["consumption_remainder"]) >= REMAINDER_MAX:
		return null

	if config != null:
		if int(dict["health"]) > config.max_health:
			return null
		if int(dict["satiety"]) > config.max_satiety:
			return null
		if int(dict["level"]) > config.max_level:
			return null

	var state := PetState.new()
	state.health = int(dict["health"])
	state.satiety = int(dict["satiety"])
	state.is_dead = bool(dict["is_dead"])
	state.level = int(dict["level"])
	state.experience = int(dict["experience"])
	state.last_exp_date = str(dict["last_exp_date"])
	state.sleep_type = int(dict["sleep_type"])
	state.scheduled_wake_timestamp = int(dict["scheduled_wake_timestamp"])
	state.suppressed_auto_sleep_cycle = str(dict["suppressed_auto_sleep_cycle"])
	state.last_settlement_timestamp = int(dict["last_settlement_timestamp"])
	state.consumption_remainder = int(dict["consumption_remainder"])
	return state


# --- 校验辅助 ---

func _has_int(dict: Dictionary, key: String) -> bool:
	if not dict.has(key):
		return false
	var v = dict[key]
	if typeof (v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		return v == int(v)  # 仅接受整数值的浮点
	return false


func _has_bool(dict: Dictionary, key: String) -> bool:
	return dict.has(key) and typeof(dict[key]) == TYPE_BOOL


func _has_str(dict: Dictionary, key: String) -> bool:
	return dict.has(key) and typeof(dict[key]) == TYPE_STRING


func _valid_date_or_empty(s: String) -> bool:
	return s == "" or DateUtils.is_valid_date(s)
