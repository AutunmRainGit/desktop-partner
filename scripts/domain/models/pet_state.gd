class_name PetState
extends RefCounted
## 领域层核心状态模型。
## PetState 仅负责持有并表达角色（桌面宠物）的状态，不包含任何业务规则：
## 生存 / 成长 / 睡眠的具体计算与调度，由后续领域服务（SurvivalSystem、
## GrowthSystem、SleepSystem 等）负责，它们共享同一个 PetState 实例来协同。
## 本类不依赖表现层、应用层与基础设施层，不使用 Autoload，不继承 Node。


## 睡眠类型。
## 采用枚举而非字符串，理由：
##   1. 编译期类型安全，杜绝字符串拼写错误；
##   2. 枚举值集中声明，新增类型只需一行，维护成本低；
##   3. 枚举在运行时本质是 int，JSON 序列化为稳定、紧凑的数字，适合持久化。
##   4. 显式赋值固定编码（0/1/2），避免日后调整枚举顺序导致已存档数据错位。
enum SleepType {
	AWAKE = 0,        ## 清醒
	ACTIVE_SLEEP = 1, ## 主动睡眠
	AUTO_SLEEP = 2,   ## 自动睡眠
}


# --- 生存状态 ---

## 当前生命值
var health: int = 100

## 当前饥饿值（饱食度）
var satiety: int = 100

## 角色是否死亡
var is_dead: bool = false


# --- 成长状态 ---

## 角色当前等级
var level: int = 1

## 角色当前经验值
var experience: int = 0

## 上一次获得每日经验的日期
var last_exp_date: String = ""


# --- 睡眠状态 ---

## 当前睡眠类型
var sleep_type: SleepType = SleepType.AWAKE

## 计划苏醒的 Unix 时间戳（秒）
var scheduled_wake_timestamp: int = 0

## 被提前唤醒后取消的自动睡眠周期标识
var suppressed_auto_sleep_cycle: String = ""


# --- 时间结算状态 ---

## 上一次完成生存状态结算的 Unix 时间戳（秒）
var last_settlement_timestamp: int

## 不足一个完整饥饿消耗单位的累计余量（0..3599）
var consumption_remainder: int = 0


func _init() -> void:
	# 初始化为“当前时间”，使新角色的第一次结算只从此刻起累计消耗，
	# 而不是从 Unix 时间戳 0（1970-01-01）开始累积出异常大的数值。
	# 从存档恢复时，由 SaveManager 在构造完成后再覆盖该字段；
	# _init 只在构造时执行一次，不会重复运行，因此不会覆盖已恢复的数据。
	last_settlement_timestamp = int(Time.get_unix_time_from_system())
