class_name GameManager
extends RefCounted
## 应用层：游戏管理器。
## 负责：创建/恢复唯一的 PetState、注入共享配置与领域服务、组织初始化与离线结算、
## 提供玩家操作入口（操作前统一推进时间与睡眠状态）、按统一策略保存状态、向表现层暴露接口。
## 不复制任何领域业务规则，不直接解析 JSON，不操作场景树/UI。


## 初始化错误码。
enum InitError {
	OK = 0,
	CONFIG_INVALID,
	SAVE_CORRUPT,
	SAVE_VERSION_UNSUPPORTED,
	SAVE_FAILED,
}


## 初始化结果。
class InitResult:
	var ok: bool = false
	var error: InitError = InitError.OK
	var is_new: bool = false  ## 是否新建角色


## 玩家操作结果（业务层；保存结果通过 last_save_error 单独暴露）。
enum ActionResult {
	REJECTED = 0,  ## 未执行：死亡/未初始化/条件不满足
	WOKE_UP,       ## 角色在睡眠，本次仅唤醒
	DONE,          ## 操作成功（喂食 / 获得经验）
	LEVELED_UP,    ## 点击后升级
}


const DEFAULT_CONFIG_PATH := "res://resources/character_config.tres"


var _state: PetState
var _config: CharacterConfig
var _survival: SurvivalSystem
var _growth: GrowthSystem
var _sleep: SleepSystem
var _time: TimeSystem
var _save: SaveManager

var _initialized := false
var last_save_error: SaveManager.SaveError = SaveManager.SaveError.OK


func _init(save_manager: SaveManager, config: CharacterConfig) -> void:
	_save = save_manager
	_config = config


## 加载默认配置资源（供启动引导调用）。
static func load_default_config() -> CharacterConfig:
	return load(DEFAULT_CONFIG_PATH) as CharacterConfig


## 初始化：校验依赖与配置 → 加载/创建状态 → 构建服务 → 离线结算 → 保存 → 标记初始化。
## now_timestamp 为显式提供的当前时间（新角色初始时间来源、离线结算终点）。
## 失败时 _initialized 保持 false，可重新调用 initialize 重试（不会留下不可重试的半初始化状态）。
func initialize(now_timestamp: int) -> InitResult:
	var result := InitResult.new()
	_initialized = false

	if _save == null:
		result.error = InitError.SAVE_CORRUPT  # 缺少存档管理器（依赖未注入）
		return result
	if _config == null or not _config.validate().is_empty():
		result.error = InitError.CONFIG_INVALID
		return result

	# 加载或创建状态（先完整校验，再使用，避免半恢复）
	var load_result := _save.load(_config)
	if load_result.ok:
		_state = load_result.state
		result.is_new = false
	elif load_result.error == SaveManager.SaveError.NOT_FOUND:
		_state = PetState.new()
		_state.last_settlement_timestamp = now_timestamp  # 明确初始化时间来源
		result.is_new = true
	elif load_result.error == SaveManager.SaveError.VERSION_UNSUPPORTED:
		result.error = InitError.SAVE_VERSION_UNSUPPORTED
		return result
	else:
		result.error = InitError.SAVE_CORRUPT
		return result

	# 构建全部领域服务（共享同一 PetState 与配置）
	_build_services()

	# 离线结算（新角色 now==last 结算 0 秒；恢复角色结算 [last, now]）
	_time.settle(now_timestamp, false)

	# 保存结算后状态，避免下次启动重复结算
	var save_err := _save.save(_state)
	if save_err != SaveManager.SaveError.OK:
		last_save_error = save_err
		result.error = InitError.SAVE_FAILED
		return result

	_initialized = true
	result.ok = true
	return result


## 在线结算（主循环调用）：结算 + 保存。
## 未初始化时返回 settled=false 的空结果，不崩溃。
func settle(now_timestamp: int) -> TimeSystem.SettlementResult:
	if not _initialized:
		return TimeSystem.SettlementResult.new()
	var r := _time.settle(now_timestamp, true)
	_auto_save()
	return r


## 喂食面包。先推进时间/睡眠状态；若仍睡眠则本次仅唤醒，不喂食。
func feed_bread(now_timestamp: int) -> ActionResult:
	if not _initialized or _state.is_dead:
		return ActionResult.REJECTED
	_advance_time(now_timestamp)
	if _state.is_dead:
		_auto_save()
		return ActionResult.REJECTED
	if _sleep.is_sleeping():
		_sleep.wake_up(now_timestamp)
		_auto_save()
		return ActionResult.WOKE_UP
	_survival.feed(_config.bread_restore)
	_auto_save()
	return ActionResult.DONE


## 玩家点击角色。先推进时间；若仍睡眠则本次仅唤醒，不获得经验。
func click_pet(now_timestamp: int) -> ActionResult:
	if not _initialized or _state.is_dead:
		return ActionResult.REJECTED
	_advance_time(now_timestamp)
	if _state.is_dead:
		_auto_save()
		return ActionResult.REJECTED
	if _sleep.is_sleeping():
		_sleep.wake_up(now_timestamp)
		_auto_save()
		return ActionResult.WOKE_UP
	var gain := _growth.gain_daily_experience(TimeUtils.local_date_str(now_timestamp))
	_auto_save()
	match gain:
		GrowthSystem.GainResult.LEVELED_UP:
			return ActionResult.LEVELED_UP
		GrowthSystem.GainResult.GAINED:
			return ActionResult.DONE
	return ActionResult.REJECTED


## 主动让角色睡觉。先推进时间。
func start_manual_sleep(now_timestamp: int) -> bool:
	if not _initialized:
		return false
	_advance_time(now_timestamp)
	var ok := _sleep.start_manual_sleep(now_timestamp)
	_auto_save()
	return ok


## 唤醒角色。先推进时间（睡眠已自然结束则已清醒，返回 false）。
func wake_up(now_timestamp: int) -> bool:
	if not _initialized:
		return false
	_advance_time(now_timestamp)
	var ok := _sleep.wake_up(now_timestamp)
	_auto_save()
	return ok


## 显式保存。返回 SaveError。
func save() -> SaveManager.SaveError:
	if _save == null or _state == null:
		return SaveManager.SaveError.WRITE_FAILED
	return _save.save(_state)


## 是否已完成初始化。
func is_initialized() -> bool:
	return _initialized


## 是否已有存档。
func has_save() -> bool:
	return _save != null and _save.has_save()


# --- 状态访问器（供表现层 / 测试） ---

func get_state() -> PetState:
	return _state


func get_config() -> CharacterConfig:
	return _config


func get_survival() -> SurvivalSystem:
	return _survival


func get_growth() -> GrowthSystem:
	return _growth


func get_sleep() -> SleepSystem:
	return _sleep


func get_time() -> TimeSystem:
	return _time


func get_save_manager() -> SaveManager:
	return _save


# --- 内部 ---

func _build_services() -> void:
	_survival = SurvivalSystem.new(_state, _config)
	_growth = GrowthSystem.new(_state, _config)
	_sleep = SleepSystem.new(_state)
	_time = TimeSystem.new(_state, _config, _survival, _growth, _sleep)


## 推进时间与睡眠状态到 now（在线，模拟觅食），不在此保存——由操作后统一保存。
func _advance_time(now_timestamp: int) -> void:
	_time.settle(now_timestamp, true)


func _auto_save() -> void:
	last_save_error = _save.save(_state)
