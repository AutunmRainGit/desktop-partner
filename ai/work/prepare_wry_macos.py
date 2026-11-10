"""Ad-hoc sign the downloaded WRY framework without iCloud directory metadata."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
framework = root / 'addons/godot_wry/bin/universal-apple-darwin/libgodot_wry.framework'
with tempfile.TemporaryDirectory(prefix='desktop-partner-wry-') as directory:
    staged = Path(directory) / framework.name
    shutil.copytree(framework, staged, copy_function=shutil.copyfile)
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(staged)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', str(staged)], check=True)
    for source in staged.rglob('*'):
        if source.is_file():
            target = framework / source.relative_to(staged)
            target.parent.mkdir(parents=True, exist_ok=True)
            # Replace the inode rather than edit a mapped/signed Mach-O in place.
            replacement = target.with_name(target.name + '.signed-new')
            replacement.write_bytes(source.read_bytes())
            replacement.replace(target)
print('WRY macOS framework signed and copied back.')
