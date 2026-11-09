class_name GrowthSystem
extends RefCounted
## 领域服务：成长系统。
## 负责经验增长、每日经验限制、等级提升、最高等级限制与自我觅食能力判断。
## 只读写共享的 PetState；CharacterConfig 只读。
## 不负责：修改饥饿/生命、执行觅食、睡眠、升级动画、UI、存档。


## 每日经验获取结果。
## 仅作为方法返回值使用，不持久化，故无需显式枚举值。
enum GainResult {
	REJECTED,   ## 未获得经验：日期非法 / 死亡 / 当日已获得
	GAINED,     ## 获得 1 点经验，未升级
	LEVELED_UP, ## 获得经验并触发升级
}


var _state: PetState
var _config: CharacterConfig


func _init(state: PetState, config: CharacterConfig) -> void:
	_state = state
	_config = config


## 尝试获得每日经验（每天最多 1 点）。current_date 为本地日期 "YYYY-MM-DD"，
## 由调用方传入以保持可测试性，避免依赖系统时钟。
## 日期非法、角色死亡或当日已获得时返回 REJECTED。
## 满级后停止获取经验；升级扣除所需经验，保留余量并支持连续升级。
func gain_daily_experience(current_date: String) -> GainResult:
	if not DateUtils.is_valid_date(current_date):
		return GainResult.REJECTED
	if _state.is_dead or is_max_level():
		return GainResult.REJECTED
	if _state.last_exp_date == current_date:
		return GainResult.REJECTED
	_state.last_exp_date = current_date
	_state.experience += 1
	if normalize_experience() > 0:
		return GainResult.LEVELED_UP
	return GainResult.GAINED


## 经验曲线唯一入口；满级返回 0，供 UI 展示 MAX。
func required_exp(level: int) -> int:
	return 0 if level >= _config.max_level else level * _config.level_up_exp


## 将已有经验折算到新曲线，返回提升的等级数。
## 初始化旧档与获取经验共用；不授予新经验、不改每日日期，重复调用无副作用。
func normalize_experience() -> int:
	var previous_level := _state.level
	while not is_max_level() and _state.experience >= required_exp(_state.level):
		_state.experience -= required_exp(_state.level)
		_state.level += 1
	if is_max_level():
		_state.experience = 0
	return _state.level - previous_level


## 是否已解锁自我觅食能力。只判断等级与死亡，不判断饥饿阈值、不执行觅食。
func can_auto_forage() -> bool:
	return not _state.is_dead and _state.level >= _config.forage_unlock_level


## 是否已达最高等级。
func is_max_level() -> bool:
	return _state.level >= _config.max_level
