"""Build a universal optional glass adapter with Apple's Command Line Tools."""
from pathlib import Path
import subprocess
import tempfile

source = Path(__file__).resolve().parent
target = source.parents[1] / 'addons/desktop_glass/bin/libdesktop_glass.macos.dylib'
target.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='desktop-glass-') as directory:
    library = Path(directory) / target.name
    subprocess.run(['clang++', '-std=c++17', '-O2', '-dynamiclib', '-fobjc-arc', '-x', 'objective-c++',
                    '-arch', 'arm64', '-arch', 'x86_64', '-mmacosx-version-min=11.0',
                    '-framework', 'Cocoa', '-framework', 'QuartzCore',
                    str(source / 'desktop_glass.cpp'), '-o', str(library)], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(library)], check=True)
    replacement = target.with_suffix('.new')
    replacement.write_bytes(library.read_bytes())
    replacement.replace(target)
print(target)
