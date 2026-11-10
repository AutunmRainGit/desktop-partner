"""Verify a project copy without WRY; keep real project and pet saves untouched."""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
godot = '/Applications/Godot.app/Contents/MacOS/Godot'
logs = root / 'ai/work/menu-regression'
logs.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='desktop-partner-fallback-') as directory:
    target = Path(directory)
    for name in ['scripts', 'scenes', 'resources', 'tests']:
        shutil.copytree(root / name, target / name)
    shutil.copyfile(root / 'icon.svg', target / 'icon.svg')
    project = (root / 'project.godot').read_text()
    # Isolate development-only MCP autoload/editor plugin in the temporary fixture.
    for section in ['autoload', 'editor_plugins']:
        project = re.sub(r'\[' + section + r'\]\n.*?(?=\n\[|\Z)', '', project, flags=re.S)
    (target / 'project.godot').write_text(project)
    (target / 'tests/fallback_probe.gd').write_text('''extends SceneTree
const ActionsTest = preload("res://tests/test_main_actions.gd")
func _init():
    run.call_deferred()
func run():
    assert(not ClassDB.class_exists("WebView"))
    assert(not FileAccess.file_exists("res://addons/godot_wry/WRY.gdextension"))
    var main = load("res://scenes/main.tscn").instantiate()
    main.set_script(ActionsTest.TestMain)
    root.add_child(main)
    main.set_process(false)
    main._game.get_state().satiety = 40
    main._on_context_menu_requested(Vector2i.ZERO)
    var event = InputEventKey.new()
    event.pressed = true
    event.keycode = KEY_F
    main._unhandled_key_input(event)
    assert(main._game.get_state().satiety == 70)
    main.queue_free()
    await process_frame
    print("FALLBACK PASS: no WRY, main scene initialized, menu failure isolated, F still feeds")
    quit()
''')
    for name, args in [('fallback-import', ['--editor', '--import', '--quit']),
                       ('fallback-probe', ['--script', 'res://tests/fallback_probe.gd'])]:
        result = subprocess.run([godot, '--headless', '--path', str(target), '--log-file', str(logs / (name + '-engine.log')), *args], capture_output=True, text=True, timeout=90)
        output = result.stdout + result.stderr
        (logs / (name + '.log')).write_text(output)
        print(name, result.returncode)
        if result.returncode or 'SCRIPT ERROR' in output:
            raise RuntimeError(output[-4000:])
        if name == 'fallback-probe':
            assert 'FALLBACK PASS' in output
            print(output)
