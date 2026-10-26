class_name SleepSystem
extends RefCounted
## 领域服务：睡眠系统。
## 负责主动睡眠、自动睡眠、自然苏醒、提前唤醒、自动睡眠周期取消，以及离线睡眠区间判定。
## 只读写共享的 PetState。
## 不依赖 CharacterConfig：睡眠时段（23:00/07:00/18:00/08:00）是固定业务规则，暂不可配置。
## 不负责：扣除饥饿/生命、经验、睡眠动画、UI、存档；区间时长→消耗的换算由 TimeSystem 负责。
## 本地时间换算复用 TimeUtils（见 utils/time_utils.gd）。


# 固定睡眠时段（设备本地时间）
const AUTO_SLEEP_HOUR := 23   # 自动入睡时刻
const AUTO_WAKE_HOUR := 7     # 自动苏醒时刻
const NIGHT_START_HOUR := 18  # 夜间开始（18:00 属于夜间）
const NIGHT_END_HOUR := 8     # 夜间结束（08:00 属于白天）
const DAY_NAP_SECONDS := 3600 # 白天主动睡眠时长（1 小时）


var _state: PetState


func _init(state: PetState) -> void:
	_state = state


## 开始主动睡眠。
## 18:00～次日08:00 之间 → 计划在下一个 08:00 苏醒；08:00～18:00 → 睡眠 1 小时。
## 返回 false：角色死亡或已在睡眠中。
func start_manual_sleep(now_timestamp: int) -> bool:
	if _state.is_dead or is_sleeping():
		return false
	var dt := TimeUtils.local_datetime(now_timestamp)
	if dt["hour"] >= NIGHT_START_HOUR or dt["hour"] < NIGHT_END_HOUR:
		_state.scheduled_wake_timestamp = TimeUtils.next_local_hour(now_timestamp, NIGHT_END_HOUR)
	else:
		_state.scheduled_wake_timestamp = now_timestamp + DAY_NAP_SECONDS
	_state.sleep_type = PetState.SleepType.ACTIVE_SLEEP
	return true


## 开始自动睡眠（23:00 触发，跨午夜至次日 07:00）。
## 返回 false：死亡、已在睡眠（主动睡眠优先）、当前周期已被取消、或不在自动睡眠时段。
func start_auto_sleep(now_timestamp: int) -> bool:
	if _state.is_dead or is_sleeping():
		return false
	var cycle := _auto_cycle_id(now_timestamp)
	if cycle == "":
		return false
	if _state.suppressed_auto_sleep_cycle == cycle:
		return false
	_state.sleep_type = PetState.SleepType.AUTO_SLEEP
	_state.scheduled_wake_timestamp = TimeUtils.next_local_hour(now_timestamp, AUTO_WAKE_HOUR)
	return true


## 自然苏醒检查：到达计划苏醒时间则转为清醒。
## 返回 true 表示发生了自然苏醒（区别于提前唤醒），false 表示无变化。
func update_sleep_state(now_timestamp: int) -> bool:
	if not is_sleeping():
		return false
	if now_timestamp >= _state.scheduled_wake_timestamp:
		_state.sleep_type = PetState.SleepType.AWAKE
		_state.scheduled_wake_timestamp = 0
		return true
	return false


## 玩家提前唤醒：立即苏醒；若处于自动睡眠，则取消当前自动睡眠周期。
## 返回 false 表示本就不在睡眠中（无操作）。
func wake_up(now_timestamp: int) -> bool:
	if not is_sleeping():
		return false
	# 在自动睡眠窗口（23:00～07:00）内被唤醒即取消当次自动睡眠周期；
	# 与睡眠类型（主动/自动）无关，避免主动睡眠期间被唤醒后仍被强制自动入睡。
	var cycle := _auto_cycle_id(now_timestamp)
	if cycle != "":
		_state.suppressed_auto_sleep_cycle = cycle
	_state.sleep_type = PetState.SleepType.AWAKE
	_state.scheduled_wake_timestamp = 0
	return true


## 是否处于睡眠中（主动或自动）。
func is_sleeping() -> bool:
	return _state.sleep_type != PetState.SleepType.AWAKE


## 计算 [from_timestamp, to_timestamp] 内的睡眠区间（供离线结算使用）。
## 约定：调用时 _state 应反映 from_timestamp 时刻的状态（由 SaveManager 在结算前保证）。
## 返回睡眠区间数组，元素为 {"start": int, "end": int, "type": PetState.SleepType}；
## 清醒时段是这些区间的补集，由 TimeSystem 换算消耗。
## 主动睡眠优先：若 from_timestamp 时正在主动睡眠，则持续到其计划苏醒时间，不被自动睡眠覆盖。
func calculate_sleep_intervals(from_timestamp: int, to_timestamp: int) -> Array[Dictionary]:
	var intervals: Array[Dictionary] = []
	if to_timestamp <= from_timestamp or _state.is_dead:
		return intervals

	var cursor := from_timestamp

	# 1) from_timestamp 时若在睡眠，则持续到计划苏醒时间
	if is_sleeping():
		var wake := _state.scheduled_wake_timestamp
		var end := mini(wake, to_timestamp)
		if end > cursor:
			intervals.append(_interval(cursor, end, _state.sleep_type))
		# 防御：若状态过期（wake < from_timestamp），不要回退到结算起点之前，
		# 避免后续窗口产生起点早于 from_timestamp 的越界区间。
		cursor = maxi(wake, from_timestamp)
		if cursor >= to_timestamp:
			return intervals

	# 2) 从 cursor（清醒）起，逐夜处理自动睡眠窗口
	while cursor < to_timestamp:
		var win := _auto_window_for_or_after(cursor)
		var win_start := int(win["start"])
		var win_end := int(win["end"])
		var win_cycle := str(win["cycle"])
		if win_start >= to_timestamp:
			break
		if win_cycle != _state.suppressed_auto_sleep_cycle:
			var s := maxi(win_start, cursor)
			var e := mini(win_end, to_timestamp)
			if e > s:
				intervals.append(_interval(s, e, PetState.SleepType.AUTO_SLEEP))
		cursor = win_end

	return intervals


# --- 睡眠领域工具 ---

## 当前自动睡眠周期标识。返回 "" 表示不在自动睡眠时段。
## 23:00 起属于“今晚”周期（周期 = 当天日期）；00:00～07:00 属于“昨晚”周期（周期 = 昨天日期）。
func _auto_cycle_id(ts: int) -> String:
	var dt := TimeUtils.local_datetime(ts)
	if dt["hour"] >= AUTO_SLEEP_HOUR:
		return TimeUtils.format_date(dt)
	if dt["hour"] < AUTO_WAKE_HOUR:
		return TimeUtils.local_date_str(ts - 86400)
	return ""


## 返回 ts 所处或紧随其后的自动睡眠窗口（23:00～次日07:00）。
## 结果 {"start": int, "end": int, "cycle": String}；cycle 为该窗口的周期日期（23:00 所在日）。
func _auto_window_for_or_after(ts: int) -> Dictionary:
	var dt := TimeUtils.local_datetime(ts)
	var hour: int = dt["hour"]
	var cycle: String
	if hour >= AUTO_SLEEP_HOUR:
		cycle = TimeUtils.format_date(dt)  # 今晚周期
	elif hour < AUTO_WAKE_HOUR:
		cycle = TimeUtils.local_date_str(ts - 86400)  # 昨晚周期（跨午夜）
	else:
		cycle = TimeUtils.format_date(dt)  # 白天：今晚周期
	var start := TimeUtils.unix_of_date_hour(cycle, AUTO_SLEEP_HOUR)
	var end := TimeUtils.next_local_hour(start, AUTO_WAKE_HOUR)
	return {"start": start, "end": end, "cycle": cycle}


func _interval(start: int, end: int, type: PetState.SleepType) -> Dictionary:
	return {"start": start, "end": end, "type": type}
