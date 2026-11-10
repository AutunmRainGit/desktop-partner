extends SceneTree
## 验证可选原生扩展的注册和安全空句柄路径；真实材质由GUI测试验证。

func _init() -> void:
	if OS.get_name() != "macOS":
		print("SKIP: macOS glass binary unavailable on this platform")
		quit()
		return
	var path := "res://addons/desktop_glass/desktop_glass.gdextension"
	var status := GDExtensionManager.load_extension(path)
	if status != GDExtensionManager.LOAD_STATUS_OK and status != GDExtensionManager.LOAD_STATUS_ALREADY_LOADED:
		print("RESULT: 0 passed, 1 failed")
		quit(1)
		return
	var glass := ClassDB.instantiate("DesktopGlass") as RefCounted
	var valid: bool = glass != null and glass.has_method("apply") and glass.call("apply", 0) == false
	print("RESULT: %d passed, %d failed" % [1 if valid else 0, 0 if valid else 1])
	quit(0 if valid else 1)
