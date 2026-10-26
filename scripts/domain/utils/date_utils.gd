class_name DateUtils
extends RefCounted
## 日期工具：提供 "YYYY-MM-DD" 日期字符串的格式与日历合法性校验。
## 纯静态工具，不依赖场景树或系统时钟。


## 校验日期是否为 "YYYY-MM-DD" 格式且是真实存在的日历日期（含闰年）。
static func is_valid_date(date: String) -> bool:
	if date.length() != 10 or date[4] != "-" or date[7] != "-":
		return false
	for i in 10:
		if i == 4 or i == 7:
			continue
		var code := date.unicode_at(i)
		if code < 48 or code > 57:  # '0' ~ '9'
			return false
	var year := date.substr(0, 4).to_int()
	var month := date.substr(5, 2).to_int()
	var day := date.substr(8, 2).to_int()
	if year < 1 or month < 1 or month > 12 or day < 1:
		return false
	var leap := (year % 4 == 0 and year % 100 != 0) or year % 400 == 0
	var days := 31
	match month:
		4, 6, 9, 11:
			days = 30
		2:
			days = 29 if leap else 28
	return day <= days
