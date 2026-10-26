class_name TimeSystem
extends RefCounted
## 领域服务：时间结算系统。
## 把 [last_settlement_timestamp, now_timestamp] 的经过时间，按睡眠/清醒区间换算成饥饿消耗
## （整数累计、余数保留），调用 SurvivalSystem 应用消耗，并处理自动觅食与最终睡眠状态同步。
## 只编排调用其它领域服务，不自行实现生存/成长/睡眠规则；不依赖场景树、UI、动画或存档。
## 当前时间由调用方显式传入，不直接读取系统时钟。
##
## 在线/离线觅食差异：核心时间结算算法完全一致，仅“自动觅食”处理不同——
##   - simulate_forage=false（离线简化，默认）：具备觅食能力者饱食度下限为 forage_threshold，不产生经验；
##   - simulate_forage=true（在线）：逐次模拟觅食（feed(leaf_restore) + 尝试获取每日经验）。


## 结算结果（仅供上层通知，不是另一份可变的角色状态）。
class SettlementResult:
	var settled: bool = false          ## 是否发生有效结算（now > last_settlement_timestamp）
	var from_timestamp: int = 0        ## 结算开始时间（上次结算时间戳）
	var to_timestamp: int = 0          ## 结算结束时间（本次传入的 now）
	var awake_seconds: int = 0         ## 清醒秒数
	var sleep_seconds: int = 0         ## 睡眠秒数
	var satiety_consumed: int = 0      ## 自然消耗扣除的饱食度点数
	var health_consumed: int = 0       ## 自然消耗扣除的生命值点数
	var is_dead: bool = false          ## 结算结束时角色是否死亡
	var forage_occurred: bool = false  ## 是否发生自动觅食（含离线兜底）
	var forage_count: int = 0          ## 自动觅食次数（仅逐次模拟时有效）


const UNITS_PER_POINT := 3600           # 3600 消耗单位 = 1 点饥饿值
const FORAGE_SIMULATION_LIMIT := 10000  # 逐次觅食模拟的安全上限，防止死循环


var _state: PetState
var _config: CharacterConfig
var _survival: SurvivalSystem
var _growth: GrowthSystem
var _sleep: SleepSystem


func _init(state: PetState, config: CharacterConfig, survival: SurvivalSystem, growth: GrowthSystem, sleep: SleepSystem) -> void:
	_state = state
	_config = config
	_survival = survival
	_growth = growth
	_sleep = sleep


## 时间结算入口。
## 若 now_timestamp <= last_settlement_timestamp 则不结算（返回 settled=false），
## 避免时间回拨或重复调用导致同一时间段被重复扣除。
func settle(now_timestamp: int, simulate_forage: bool = false) -> SettlementResult:
	var result := SettlementResult.new()
	result.to_timestamp = now_timestamp

	if now_timestamp <= _state.last_settlement_timestamp:
		return result  # settled=false

	result.settled = true
	result.from_timestamp = _state.last_settlement_timestamp

	# 已死亡：仅推进时间戳，不产生消耗
	if _state.is_dead:
		_state.last_settlement_timestamp = now_timestamp
		result.is_dead = true
		return result

	# 有限修复：余量越界则重置（余量是派生数据，重置无副作用）
	if _state.consumption_remainder < 0 or _state.consumption_remainder >= UNITS_PER_POINT:
		_state.consumption_remainder = 0

	var from_ts := _state.last_settlement_timestamp
	var elapsed := now_timestamp - from_ts

	# 1) 睡眠/清醒秒数（睡眠区间由 SleepSystem 判定）
	var sleep_seconds := _sum_sleep_seconds(_sleep.calculate_sleep_intervals(from_ts, now_timestamp))
	var awake_seconds := elapsed - sleep_seconds
	result.sleep_seconds = sleep_seconds
	result.awake_seconds = awake_seconds

	# 2) 累计消耗单位并取整，保留余数（整数运算）
	var units := awake_seconds * _config.awake_consumption \
			+ sleep_seconds * _config.sleep_consumption \
			+ _state.consumption_remainder
	var consumption_points := units / UNITS_PER_POINT
	_state.consumption_remainder = units % UNITS_PER_POINT

	# 3) 应用消耗（含自动觅食与死亡）
	_apply_consumption(consumption_points, simulate_forage, result, now_timestamp)

	# 4) 同步最终睡眠状态到 now（死亡时跳过，死亡复位由上层处理）
	if not _state.is_dead:
		_sleep.update_sleep_state(now_timestamp)
		if not _sleep.is_sleeping():
			_sleep.start_auto_sleep(now_timestamp)

	# 5) 更新结算时间戳
	_state.last_settlement_timestamp = now_timestamp
	return result


## 汇总睡眠区间总秒数（区间已由 SleepSystem 保证合法，仅做 e>s 防御）。
func _sum_sleep_seconds(intervals: Array[Dictionary]) -> int:
	var total := 0
	for iv in intervals:
		var s := int(iv["start"])
		var e := int(iv["end"])
		if e > s:
			total += e - s
	return total


## 应用消耗点数，处理自动觅食与死亡，并把结果写回 result。
func _apply_consumption(points: int, simulate_forage: bool, result: SettlementResult, now_timestamp: int) -> void:
	if points <= 0:
		return

	if not _growth.can_auto_forage():
		# 普通角色：饱食度 → 生命值 → 死亡
		var sat_before := _state.satiety
		var hp_before := _state.health
		_survival.apply_consumption(points)
		result.satiety_consumed = sat_before - _state.satiety
		result.health_consumed = hp_before - _state.health
		result.is_dead = _state.is_dead
		return

	# 具备觅食能力：自然消耗的饱食度下限为 forage_threshold
	if not simulate_forage:
		var actual := _consume_to_floor(points)
		result.satiety_consumed = actual
		result.health_consumed = 0
		result.forage_occurred = points > actual
		result.is_dead = _state.is_dead
		return

	# 在线逐次模拟：feed(leaf_restore) + 经验；无进展时回退到下限保护
	var remaining := points
	var date_str := TimeUtils.local_date_str(now_timestamp)
	var sat_consumed := 0
	var safety := 0
	while remaining > 0 and not _state.is_dead and safety < FORAGE_SIMULATION_LIMIT:
		safety += 1
		var to_threshold := _state.satiety - _config.forage_threshold
		if to_threshold <= 0:
			if not _try_forage(result, date_str):
				break  # 无进展（恢复量为0或已达上限），退出
			continue
		var step := mini(remaining, to_threshold)
		var s0 := _state.satiety
		_survival.apply_consumption(step)
		sat_consumed += s0 - _state.satiety
		remaining -= step
		if remaining > 0 and _state.satiety <= _config.forage_threshold:
			if not _try_forage(result, date_str):
				break

	# 剩余消耗回退到“下限保护”：具备觅食能力者不应因自然消耗致死
	if remaining > 0 and not _state.is_dead:
		sat_consumed += _consume_to_floor(remaining)

	result.satiety_consumed = sat_consumed
	result.is_dead = _state.is_dead


## 尝试一次觅食：feed(leaf_restore) +（在线）尝试每日经验。
## 返回 true 表示饱食度实际增加（有进展），false 表示无进展（恢复量为0或已达上限）。
func _try_forage(result: SettlementResult, date_str: String) -> bool:
	var before := _state.satiety
	_survival.feed(_config.leaf_restore)
	if _state.satiety <= before:
		return false
	result.forage_count += 1
	result.forage_occurred = true
	_growth.gain_daily_experience(date_str)
	return true


## 应用“下限保护”消耗：饱食度最多降到 forage_threshold，返回实际扣除的饱食度点数。
func _consume_to_floor(points: int) -> int:
	var actual := mini(points, maxi(_state.satiety - _config.forage_threshold, 0))
	if actual > 0:
		_survival.apply_consumption(actual)
	return actual
