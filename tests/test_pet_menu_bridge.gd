extends SceneTree

const MenuController = preload("res://scripts/presentation/pet_menu_controller.gd")
const ActionTest = preload("res://tests/test_main_actions.gd")
var _passed := 0
var _failed := 0
var packets: Array[Dictionary] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.set_script(ActionTest.TestMain)
	root.add_child(main)
	main.set_process(false)
	var menu := MenuController.new()
	main.add_child(menu)
	menu.setup(main)
	menu.bridge_message_sent.connect(func(packet: Dictionary): packets.append(packet))
	var state: PetState = main._game.get_state()
	state.satiety = 40
	main.dispatch_action(Main.Action.START_SLEEP)
	var before := state.last_settlement_timestamp
	_check(menu.handle_message('{"type":"action","id":"1","action":"feed_bread","params":{}}').status == "rejected", "握手前操作拒绝")
	var ready: Dictionary = menu.handle_message('{"type":"ready"}')
	_check(ready.type == "initial_state" and ready.state.is_sleeping and state.sleep_type != PetState.SleepType.AWAKE, "ready查询不唤醒，返回当前状态")
	_check(menu.handle_message('{"type":"action","id":"status","action":"set_status_bar_visible","params":{"visible":false}}').status == "success", "桥接隐藏状态栏")
	_check(menu.handle_message('{"type":"action","id":"status2","action":"set_status_bar_visible","params":{"visible":false}}').status == "success", "连续显式隐藏幂等")
	_check(state.sleep_type != PetState.SleepType.AWAKE and state.last_settlement_timestamp == before, "显示操作不打扰睡眠")
	var request := '{"type":"action","id":"feed1","action":"feed_bread","params":{}}'
	_check(menu.handle_message(request).status == "woke_up" and state.satiety == 40, "桥接喂食第一次只唤醒")
	_check(menu.handle_message(request).status == "woke_up" and state.satiety == 40, "重复请求不重复执行喂食")
	_check(menu.handle_message('{"type":"action","id":"feed2","action":"feed_bread","params":{}}').status == "success" and state.satiety == 70, "第二次新操作正常喂食")
	for invalid in ['[]', 'null', '{', '{"type":5}', '{"type":"execute_script"}', '{"type":"ready","extra":1}', '{"type":"action","id":"x","action":"feed_bread","params":[]}', '{"type":"action","id":"x","action":"set_status_bar_visible","params":{"visible":"false"}}', '{"type":"action","id":"x","action":"delete_node","params":{}}', '{"type":"action","id":"feed2","action":"wake_up","params":{}}']:
		_check(menu.handle_message(invalid).status == "rejected", "非法消息或重复编号被拒绝")
	_check(state.satiety == 70 and not main.get_menu_state().status_bar_visible, "非法消息没有业务副作用")
	_check(menu.handle_message("x".repeat(4097)).status == "rejected", "过长消息拒绝")
	var usable := Rect2i(100, 50, 800, 600)
	var menu_size := Vector2i(320, 470)
	for anchor in [Vector2i(110, 60), Vector2i(899, 649), Vector2i(100, 649), Vector2i(899, 50)]:
		var position := MenuController.fit_position(anchor, menu_size, usable)
		_check(usable.encloses(Rect2i(position, menu_size)), "屏幕四角菜单保持可见")
	menu.is_open = true
	main.dispatch_action(Main.Action.START_SLEEP)
	_check(packets[-1].type == "state" and packets[-1].state.is_sleeping, "打开菜单后状态变化实时推送")
	menu.handle_message('{"type":"close"}')
	_check(not menu.is_open, "网页关闭消息关闭菜单")
	# 无头模式不创建原生WebView，可验证缺少扩展时的降级。
	_check(not menu.open_menu(main, Vector2i.ZERO) and not menu.is_open, "扩展不可用时菜单关闭且不崩溃")
	main.dispatch_action(Main.Action.WAKE_UP)
	_check(main.dispatch_action(Main.Action.FEED_BREAD).status == "success", "菜单不可用后操作入口仍正常")
	main.queue_free()
	await process_frame
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  ok    " + label)
	else:
		_failed += 1
		print("  FAIL  " + label)
