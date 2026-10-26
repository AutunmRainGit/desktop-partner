class_name InteractionController
extends Node
## 表现层：交互控制器。把鼠标/键盘操作转发给 GameManager，并正确解释 ActionResult。
## 不自行实现睡眠计时/唤醒/经验/喂食等业务规则；悬停不唤醒。


const SLEEP_TIP := "角色正在睡觉，任何操作都将唤醒她。"


var _game: GameManager
var _window: WindowController


func setup(game: GameManager, window: WindowController) -> void:
	_game = game
	_window = window


## 点击桌宠。拖动窗口时不视为点击。
func handle_click(now_timestamp: int) -> GameManager.ActionResult:
	if not _ready_to_interact():
		return GameManager.ActionResult.REJECTED
	if _window != null and _window.is_dragging():
		return GameManager.ActionResult.REJECTED  # 拖动不是点击
	return _game.click_pet(now_timestamp)


## 喂食面包。
func handle_feed(now_timestamp: int) -> GameManager.ActionResult:
	if not _ready_to_interact():
		return GameManager.ActionResult.REJECTED
	if _window != null and _window.is_dragging():
		return GameManager.ActionResult.REJECTED
	return _game.feed_bread(now_timestamp)


## 主动睡眠。
func handle_sleep(now_timestamp: int) -> bool:
	if not _ready_to_interact():
		return false
	return _game.start_manual_sleep(now_timestamp)


## 唤醒。
func handle_wake(now_timestamp: int) -> bool:
	if not _ready_to_interact():
		return false
	return _game.wake_up(now_timestamp)


## 悬停提示：睡眠且未死亡时返回提示文本，否则返回空串。
func sleep_tip() -> String:
	if _game == null or not _game.is_initialized():
		return ""
	var state := _game.get_state()
	if state == null or state.is_dead:
		return ""
	if state.sleep_type != PetState.SleepType.AWAKE:
		return SLEEP_TIP
	return ""


## 纯逻辑：ActionResult → 反馈文本。
static func action_feedback_text(result: GameManager.ActionResult) -> String:
	match result:
		GameManager.ActionResult.DONE:
			return "完成"
		GameManager.ActionResult.WOKE_UP:
			return "已唤醒"
		GameManager.ActionResult.LEVELED_UP:
			return "升级！"
		GameManager.ActionResult.REJECTED:
			return "操作被拒绝"
	return ""


func _ready_to_interact() -> bool:
	return _game != null and _game.is_initialized() and _game.get_state() != null and not _game.get_state().is_dead
