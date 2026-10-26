class_name SurvivalSystem
extends RefCounted
## 领域服务：生存系统。
## 负责饥饿值恢复、饥饿值消耗、生命值扣除与死亡状态维护。
## 只读写共享的 PetState；CharacterConfig 只读。
## 不负责：时间换算、睡眠判断、等级提升、进食动画、UI、存档。


var _state: PetState
var _config: CharacterConfig


func _init(state: PetState, config: CharacterConfig) -> void:
	_state = state
	_config = config


## 喂食：增加饥饿值，最多到 max_satiety。
## 返回 false 表示被拒绝（角色已死亡，或 amount 为负数）。amount == 0 为合法无操作。
func feed(amount: int) -> bool:
	if _state.is_dead or amount < 0:
		return false
	if amount == 0:
		return true
	_state.satiety = mini(_state.satiety + amount, _config.max_satiety)
	return true


## 应用饥饿消耗：先扣饥饿值，不足部分按 1:1 扣除生命值；生命值归零则死亡。
## amount 表示需要扣除的饥饿值点数（非负）。返回 false 表示被拒绝（死亡或负数）。
func apply_consumption(amount: int) -> bool:
	if _state.is_dead or amount < 0:
		return false
	if amount == 0:
		return true
	if _state.satiety >= amount:
		_state.satiety -= amount
	else:
		var overflow := amount - _state.satiety
		_state.satiety = 0
		_state.health = maxi(_state.health - overflow, 0)
	if _state.health <= 0:
		_state.health = 0
		_state.is_dead = true
	return true
