class_name AnimationController
extends Node
## 表现层：动画控制器。把展示状态映射到循环动画，并支持一次性动作动画（播放完回到状态动画）。
## 优先级：死亡 > 睡眠 > 虚弱 > 饥饿 > 待机。不直接修改 PetState。


const ANIM_IDLE := "idle"
const ANIM_SLEEP := "sleep"
const ANIM_DEAD := "dead"
const ANIM_HUNGRY := "hungry"
const ANIM_WEAK := "weak"
const ANIM_EAT_BREAD := "eat_bread"
const ANIM_EAT_LEAF := "eat_leaf"
const ANIM_LEVEL_UP := "level_up"
const ANIM_START_SLEEP := "start_sleep"
const ANIM_STOP_SLEEP := "stop_sleep"

## 生命值低于该比例视为“虚弱”（占位阈值，可按需调整）。
const WEAK_HEALTH_RATIO := 0.5


var _sprite: AnimatedSprite2D
var _config: CharacterConfig
var _current_state_anim := ANIM_IDLE
var _playing_action := false


func setup(sprite: AnimatedSprite2D, config: CharacterConfig = null) -> void:
	_sprite = sprite
	_config = config
	if _sprite != null and _sprite.sprite_frames != null:
		_sprite.animation_finished.connect(_on_animation_finished)


## 纯逻辑：状态 → 循环动画名。
## config 非空时，清醒状态会进一步区分“虚弱/饥饿/待机”。
static func state_to_animation(state: PetState, config: CharacterConfig = null) -> String:
	if state == null:
		return ANIM_IDLE
	if state.is_dead:
		return ANIM_DEAD
	if state.sleep_type != PetState.SleepType.AWAKE:
		return ANIM_SLEEP
	if config != null:
		if state.health <= config.max_health * WEAK_HEALTH_RATIO:
			return ANIM_WEAK
		if state.satiety <= config.forage_threshold:
			return ANIM_HUNGRY
	return ANIM_IDLE


## 根据状态切换循环动画；相同动画不重复重启；动作播放中不打断。
func set_state(state: PetState) -> void:
	if _sprite == null:
		return
	var anim := state_to_animation(state, _config)
	_current_state_anim = anim
	if _playing_action:
		return
	if _sprite.animation != anim:
		_sprite.play(anim)


## 播放一次性动作动画（进食/升级/入睡/唤醒），播放结束后自动回到状态动画。
func play_action(anim: String) -> void:
	if _sprite == null or _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(anim):
		push_warning("AnimationController: 动画 '%s' 不存在，跳过。" % anim)
		return
	_playing_action = true
	_sprite.play(anim)


func _on_animation_finished() -> void:
	_playing_action = false
	if _sprite.animation != _current_state_anim:
		_sprite.play(_current_state_anim)
