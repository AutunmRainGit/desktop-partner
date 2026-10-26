class_name CharacterConfig
extends Resource
## 领域层静态配置：角色的业务规则参数（数据驱动）。
## 与 PetState 严格区分：PetState 保存运行时状态，本类保存不随运行变化的规则参数。
## 本类不继承 Node、不使用 Autoload、不依赖场景树，也不保存任何运行时状态。

## Resource 共享说明：
## Godot 的 Resource 按引用共享，同一份 .tres 可被多个对象同时持有。
## 本项目约定：CharacterConfig 在运行时只读——
## SurvivalSystem、GrowthSystem 等领域服务只读取配置，不修改它；
## 多个领域服务可共享同一个 CharacterConfig 实例，无需 duplicate()。
## 本次不实现复杂的不可变机制，仅依赖约定。


# --- 生存配置 ---

## 角色生命值上限
@export_range(1, 9999) var max_health: int = 100

## 角色饥饿值（饱食度）上限
@export_range(1, 9999) var max_satiety: int = 100

## 清醒时每小时消耗的饥饿值（单位：点/小时）
@export_range(0, 9999) var awake_consumption: int = 3

## 睡眠时每小时消耗的饥饿值（单位：点/小时）
@export_range(0, 9999) var sleep_consumption: int = 2


# --- 食物配置 ---

## 面包恢复的饥饿值
@export_range(0, 9999) var bread_restore: int = 30

## 自我觅食时，叶子恢复的饥饿值
@export_range(0, 9999) var leaf_restore: int = 10


# --- 成长配置 ---

## 角色最高等级
@export_range(1, 9999) var max_level: int = 2

## 从 1 级提升至 2 级需要的经验值
@export_range(1, 9999) var level_up_exp: int = 2


# --- 自我觅食配置 ---

## 解锁自我觅食能力所需的等级
@export_range(1, 9999) var forage_unlock_level: int = 2

## 触发自我觅食的饥饿值阈值
@export_range(0, 9999) var forage_threshold: int = 10


## 校验配置是否合法。只检查、不修改任何状态。
## 返回错误信息数组；数组为空表示配置合法。
## 注意：@export_range 仅约束 Inspector 输入，无法保证字段间关系，
## 例如 forage_threshold <= max_satiety 需在此处校验。
func validate() -> Array[String]:
	var errors: Array[String] = []
	if max_health <= 0:
		errors.append("max_health 必须大于 0")
	if max_satiety <= 0:
		errors.append("max_satiety 必须大于 0")
	if awake_consumption < 0:
		errors.append("awake_consumption 不得小于 0")
	if sleep_consumption < 0:
		errors.append("sleep_consumption 不得小于 0")
	if bread_restore < 0:
		errors.append("bread_restore 不得小于 0")
	if leaf_restore < 0:
		errors.append("leaf_restore 不得小于 0")
	if max_level < 1:
		errors.append("max_level 必须大于等于 1")
	if level_up_exp <= 0:
		errors.append("level_up_exp 必须大于 0")
	if forage_unlock_level < 1 or forage_unlock_level > max_level:
		errors.append("forage_unlock_level 必须处于 1 到 max_level 之间")
	if forage_threshold < 0 or forage_threshold > max_satiety:
		errors.append("forage_threshold 应处于 0 到 max_satiety 之间")
	return errors
