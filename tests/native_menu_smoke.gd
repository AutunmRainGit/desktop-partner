extends SceneTree
## 显式以GUI运行；不纳入无头测试。全程使用测试存档。

const ActionsTest = preload("res://tests/test_main_actions.gd")
class TestMenuProcess extends "res://scripts/presentation/pet_menu_controller.gd":
	var starts := 0
	func _create_host_process(args: PackedStringArray) -> int:
		starts += 1
		if starts > 1:
			args.append("--pet-menu-test-stage=focus")
		args.remove_at(args.find("res://scenes/pet_menu.tscn"))
		args.insert(0, "res://tests/native_menu_child.gd")
		args.insert(0, "--script")
		return super._create_host_process(args)

var _passed := 0
var _failed := 0
var packets: Array[Dictionary] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	for path in ["res://ai/work/menu-native-report.json", "res://ai/work/menu-native-focus-ready.txt"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.set_script(ActionsTest.TestMain)
	root.add_child(main)
	main.set_process(false)
	main._game.get_state().satiety = 40
	main.dispatch_action(Main.Action.START_SLEEP)
	var menu := TestMenuProcess.new()
	main.add_child(menu)
	main._pet_menu = menu
	menu.bridge_message_sent.connect(func(packet: Dictionary): packets.append({"packet": packet, "satiety": main._game.get_state().satiety}))
	menu.menu_failed.connect(func(message: String): print("NATIVE MENU FAILURE: ", message))
	root.grab_focus()
	root.warp_mouse(main._pet.get_sprite().global_position)
	await create_timer(0.2).timeout
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	event.position = main._pet.get_sprite().global_position
	Input.parse_input_event(event)
	await process_frame
	_check(menu.is_open, "真实鼠标命中路径右键打开菜单")
	var deadline := Time.get_ticks_msec() + 45000
	var advanced := false
	var reopened := false
	var focused := false
	var first_pid: int = menu._pid
	var second_pid := -1
	while Time.get_ticks_msec() < deadline:
		if not advanced and packets.any(func(item): return item.packet.get("type") == "action_result" and item.packet.get("id") == "4"):
			# 留出时间检查睡眠按钮，再触发自然苏醒。
			await create_timer(0.6).timeout
			main.clock += 3600
			main._process(0.0)
			advanced = true
		if FileAccess.file_exists("res://ai/work/menu-native-report.json") and not OS.is_process_running(first_pid) and not reopened:
			_check(not menu.is_open, "WebView聚焦时DOM Esc关闭真实菜单进程")
			menu.open_menu(main, root.position + Vector2i(root.size.x, 30))
			second_pid = menu._pid
			reopened = true
		if FileAccess.file_exists("res://ai/work/menu-native-focus-ready.txt") and not focused:
			root.grab_focus()
			focused = true
		if focused and second_pid > 0 and not OS.is_process_running(second_pid):
			_check(not menu.is_open, "真实原生窗口失焦关闭")
			break
		await process_frame
	_check(reopened and focused, "关闭后重新创建菜单并恢复初始状态")
	if FileAccess.file_exists("res://ai/work/menu-native-report.json"):
		var results: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://ai/work/menu-native-report.json"))
		for name in results:
			_check(results[name] == true, "原生WebView: " + name)
	else:
		_check(false, "原生菜单报告超时；检查pet_menu.log")
	_check(packets.any(func(item): return item.packet.get("status") == "woke_up" and item.satiety == 40), "原生Vue喂食第一次仅唤醒，饱食度不变")
	_check(packets.any(func(item): return item.packet.get("status") == "success" and item.satiety == 70), "原生Vue喂食第二次恢复30")
	_check(not main.get_menu_state().status_bar_visible, "原生Vue隐藏状态栏已执行")
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
