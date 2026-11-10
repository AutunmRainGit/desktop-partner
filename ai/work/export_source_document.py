"""Export the project's current on-disk source to a standalone Markdown document."""
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo
import hashlib
import re

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "ai/work/desktop-partner-完整源代码文档.md"
EXTENSIONS = {".gd", ".py", ".tscn", ".tres", ".godot", ".cfg", ".json", ".csv", ".svg", ".uid", ".import", ".md", ".txt", ".vue", ".js", ".mjs", ".html", ".css", ".gdextension", ".plist"}
TEXT_NAMES = {".gitignore", ".gitattributes", ".editorconfig", ".gdignore", "LICENSE", "CodeResources"}
SKIP = {".git", ".godot", ".claude", ".codex", ".agents", "__pycache__", "node_modules", "exports", "test-results", "playwright-report"}
sources, assets = [], []
for path in ROOT.rglob("*"):
    rel = path.relative_to(ROOT)
    if not path.is_file() or any(part in SKIP for part in rel.parts) or path.name == ".DS_Store":
        continue
    if rel.parts[0] == "ai":
        # Process logs, prior exports and conversation memory are not project source.
        if not (rel.parts[:2] == ("ai", "work") and path.suffix == ".py"):
            continue
    if path.suffix in EXTENSIONS or path.name in TEXT_NAMES:
        try:
            source = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            assets.append((rel.as_posix(), path.stat().st_size, hashlib.sha256(path.read_bytes()).hexdigest()))
            continue
        sources.append((rel.as_posix(), source))
    else:
        assets.append((rel.as_posix(), path.stat().st_size, hashlib.sha256(path.read_bytes()).hexdigest()))

def order(item):
    name = item[0]
    groups = ["project.godot", "scripts/domain/", "scripts/application/", "scripts/infrastructure/", "scripts/presentation/", "scenes/", "ui/", "resources/", "tests/", "addons/", "ai/"]
    return (next((i for i, prefix in enumerate(groups) if name.startswith(prefix)), len(groups)), name)

sources.sort(key=order)
assets.sort()
stamp = datetime.now(ZoneInfo("Asia/Shanghai")).strftime("%Y-%m-%d %H:%M:%S")
lines = sum(len(text.splitlines()) for _, text in sources)
parts = [
    "# desktop-partner 完整源代码文档\n",
    f"更新时间：{stamp}（北京时间，UTC+08:00）\n\n项目路径：`{ROOT}`\n",
    "本文是当前磁盘文件的源码快照，包含尚未提交的修改；不读取编辑器中未保存的内容。\n",
    f"收录 {len(sources)} 个文本文件，共 {lines} 行；另附 {len(assets)} 项非文本资源清单。\n",
    "## 阅读说明\n\n"
    "项目采用 Godot 4 + GDScript。启动配置见 project.godot，主场景为 scenes/main.tscn。"
    "业务分为领域、应用、基础设施和表现四层。等级上限默认 Lv.10，经验曲线由 GrowthSystem 统一管理。\n\n"
    "正文包含业务源码、场景、资源描述、Vue组件、前端构建脚本及离线HTML产物、测试、导出预设、插件源码、导入/UID元数据及已有说明文件。"
    "addons/godot_mcp 下为开发辅助插件，应与业务源码区分阅读。计划及插件说明按原文保留，不能作为功能已实现或测试通过的证明。\n\n"
    "不包含 Git 历史、Godot 缓存、本地权限与身份配置、运行日志和对话记忆。"
    "图片等资源仅列出路径、大小及 SHA-256，未将二进制内容嵌入正文；恢复可运行项目仍需原始资源。\n\n"
    "最新菜单功能验证记录（2026-11-10）：15个Godot测试脚本、605条断言通过；离线Vue浏览器测试5项通过；macOS原生链路15项通过；缺少WRY时的隔离启动测试通过。"
    "Windows预设PCK已确认收录离线HTML，但Windows/WebView2运行、多屏高DPI及物理键盘Esc尚未实测。生成文档时未重新执行测试。\n",
    "## 文件目录\n",
]
for i, (name, _) in enumerate(sources, 1):
    parts.append(f"- [{name}](#source-{i:04d})\n")
parts.append("\n## 完整文本源码\n")
langs = {".gd": "gdscript", ".py": "python", ".json": "json", ".svg": "xml", ".md": "markdown", ".csv": "csv", ".vue": "vue", ".js": "javascript", ".mjs": "javascript", ".html": "html", ".css": "css", ".plist": "xml"}
for i, (name, content) in enumerate(sources, 1):
    fence = "`" * max(4, max((len(run) for run in re.findall(r'`+', content)), default=0) + 1)
    digest = hashlib.sha256(content.encode("utf-8")).hexdigest()
    parts.append(f'\n<a id="source-{i:04d}"></a>\n\n### {name}\n\n')
    parts.append(f"行数：{len(content.splitlines())}；SHA-256：`{digest}`\n\n")
    parts.append(f"{fence}{langs.get(Path(name).suffix, 'text')}\n{content}")
    if not content.endswith("\n"):
        parts.append("\n")
    parts.append(f"{fence}\n")
parts.append("\n## 非文本资源清单\n\n| 路径 | 大小（字节） | SHA-256 |\n|---|---:|---|\n")
for name, size, digest in assets:
    parts.append(f"| `{name}` | {size} | `{digest}` |\n")
OUT.write_text("".join(parts), encoding="utf-8")
document = OUT.read_text(encoding="utf-8")
assert len(re.findall(r'^<a id="source-\d+"></a>$', document, re.MULTILINE)) == len(sources)
assert all(content in document for _, content in sources)
print(f"输出：{OUT}\n文本文件：{len(sources)}\n源码行数：{lines}\n非文本资源：{len(assets)}\n文档字节数：{OUT.stat().st_size}\n完整性检查：通过")
