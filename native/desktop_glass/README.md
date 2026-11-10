# 可选桌面玻璃适配

菜单本身仍由 Vue + Godot WRY 渲染。CSS 的 backdrop-filter 只能模糊网页内部的背景；这个适配层在菜单自己的 macOS 窗口中插入 NSVisualEffectView，提供真正的窗口后方模糊，不截取或保存桌面截图。

目前提供已编译并实测的 macOS universal 二进制；Windows 分支仅为源码，未编译、未实测，宿主目前只在 macOS 调用。缺少适配层时仍使用透明 WebView 和 CSS 玻璃样式。正式 Windows 分发需单独处理适配层的构建与平台导出过滤，不能视为已支持原生模糊。

构建（需要 Apple Command Line Tools）：

```sh
python3 native/desktop_glass/build_macos.py
```

输出：addons/desktop_glass/bin/libdesktop_glass.macos.dylib。开发构建使用临时签名；正式发布时按发布渠道签名。适配层只在菜单进程中应用，不修改桌宠生命系统或主窗口。

公开方法：DesktopGlass.apply(window_handle: int) -> bool。句柄由 Godot 的 DisplayServer 提供，不向 Vue 暴露。空句柄安全返回 false。

gdextension_interface.h 来自 Godot 官方 4.5-stable，保留原始 MIT 许可说明：
https://github.com/godotengine/godot/blob/4.5-stable/core/extension/gdextension_interface.h

验证：test_desktop_glass.gd 检查注册和空句柄，native_menu_smoke.gd 检查真实窗口材质及 WebView 布局。
