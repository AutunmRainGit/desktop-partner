class_name PetController
extends Node2D
## 表现层：桌宠状态显示控制器。
## 将 PetState 只读地转换为可见状态与文本；不做任何业务性修正，不修改领域状态。


const STATE_DEAD := "dead"
const STATE_SLEEPING := "sleeping"
const STATE_AWAKE := "awake"


@onready var _sprite: AnimatedSprite2D = $CharacterSprite
@onready var _level_label: Label = $StatusDisplay/LevelLabel
@onready var _satiety_label: Label = $StatusDisplay/SatietyLabel
@onready var _health_label: Label = $StatusDisplay/HealthLabel
@onready var _state_label: Label = $StatusDisplay/StateLabel
@onready var _tooltip: Label = $Tooltip
@onready var _feedback: Label = $Feedback


## 刷新显示（初始化、操作完成、时间结算后调用）。
func refresh(state: PetState, config: CharacterConfig) -> void:
	if state == null:
		_level_label.text = "等级: -"
		_satiety_label.text = "饱食度: -/-"
		_health_label.text = "生命值: -/-"
		_state_label.text = "未知"
		return
	_level_label.text = "等级: %d" % state.level
	_satiety_label.text = "饱食度: %d/%d" % [state.satiety, config.max_satiety]
	_health_label.text = "生命值: %d/%d" % [state.health, config.max_health]
	_state_label.text = state_text(state)


## 设置动画帧资源（由 Main 注入 SpriteFrames）。
func set_sprite_frames(frames: SpriteFrames) -> void:
	if _sprite != null:
		_sprite.sprite_frames = frames


func get_sprite() -> AnimatedSprite2D:
	return _sprite


## 显示/隐藏悬停提示（空文本则隐藏）。
func show_tip(text: String) -> void:
	if _tooltip == null:
		return
	if text == "":
		_tooltip.hide()
	else:
		_tooltip.text = text
		_tooltip.show()


## 显示操作反馈（喂食/唤醒/升级/拒绝等），短暂显示后自动隐藏。
func flash_feedback(text: String) -> void:
	if _feedback == null or text == "":
		return
	_feedback.text = text
	_feedback.show()
	var timer := get_tree().create_timer(1.5)
	timer.timeout.connect(_feedback.hide)


## 纯逻辑：将状态映射为展示状态（dead/sleeping/awake）。
static func describe_state(state: PetState) -> String:
	if state == null:
		return STATE_AWAKE
	if state.is_dead:
		return STATE_DEAD
	if state.sleep_type != PetState.SleepType.AWAKE:
		return STATE_SLEEPING
	return STATE_AWAKE


## 纯逻辑：状态的中文描述文本。
static func state_text(state: PetState) -> String:
	if state == null:
		return "未知"
	if state.is_dead:
		return "已死亡"
	if state.sleep_type == PetState.SleepType.ACTIVE_SLEEP:
		return "主动睡眠"
	if state.sleep_type == PetState.SleepType.AUTO_SLEEP:
		return "自动睡眠"
	return "清醒"
