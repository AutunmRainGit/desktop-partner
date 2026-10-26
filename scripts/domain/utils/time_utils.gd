class_name TimeUtils
extends RefCounted
## 时间工具：本地时区的通用时间换算（Unix 时间戳 ↔ 本地时间分量 / 日期字符串）。
## 纯静态工具，不依赖场景树或系统时钟（仅读取设备时区偏移）。
##
## 技术风险（DST）：使用“当前时区偏移”作用于任意时间戳，并假定一天恒为 86400 秒。
## 在存在夏令时的地区，跨 DST 切换日计算历史时间戳可能产生 1 小时误差；无 DST 平台不受影响。
## 若未来面向多时区/夏令时地区，需统一引入带历史时区规则的时间库解决。


## 本地时区偏移（秒）。Godot 的 bias 语义：本地 = UTC + bias 分钟。
static func local_offset_seconds() -> int:
	return int(Time.get_time_zone_from_system()["bias"]) * 60


## 绝对 Unix 时间戳 → 本地时间分量字典（含 year/month/day/hour/minute/second）。
static func local_datetime(ts: int) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(ts + local_offset_seconds())


## 本地时间分量字典 → 绝对 Unix 时间戳（仅使用日期与时分秒字段）。
static func local_unix(dt: Dictionary) -> int:
	var clean := {
		"year": dt["year"], "month": dt["month"], "day": dt["day"],
		"hour": dt["hour"], "minute": dt["minute"], "second": dt["second"],
	}
	return int(Time.get_unix_time_from_datetime_dict(clean)) - local_offset_seconds()


## 绝对 Unix 时间戳 → 本地日期字符串 "YYYY-MM-DD"。
static func local_date_str(ts: int) -> String:
	return format_date(local_datetime(ts))


## 本地时间分量字典 → "YYYY-MM-DD"。
static func format_date(dt: Dictionary) -> String:
	return "%04d-%02d-%02d" % [dt["year"], dt["month"], dt["day"]]


## "YYYY-MM-DD" 日期 + 小时（本地）→ 绝对 Unix 时间戳。
static func unix_of_date_hour(date_str: String, hour: int) -> int:
	return local_unix({
		"year": date_str.substr(0, 4).to_int(),
		"month": date_str.substr(5, 2).to_int(),
		"day": date_str.substr(8, 2).to_int(),
		"hour": hour, "minute": 0, "second": 0,
	})


## 返回 ts 之后最近的 hour:00:00（本地）。若 ts 已过该时刻，返回次日同一时刻。
## 注：跨日按 +86400 秒处理，未处理 DST 导致的 23/25 小时日。
static func next_local_hour(ts: int, hour: int) -> int:
	var dt := local_datetime(ts)
	dt["hour"] = hour
	dt["minute"] = 0
	dt["second"] = 0
	var wake := local_unix(dt)
	if wake <= ts:
		wake += 86400
	return wake
