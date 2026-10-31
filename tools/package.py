#!/usr/bin/env python3
"""Check recorded validation identities and build the distributable trainer ZIP."""
from pathlib import Path
import hashlib
import json
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.2.0'
DLLS = {
    'UE4SS.dll': '8ac18fbffc1ef96b0662d4a2d537b3f224c26d65caaba7989a9404c566102b26',
    'dwmapi.dll': 'ce596412befa68c30b7f88f65beb77d9bdad55e9b96a276a5a9cf690c63f24bb',
}

def sha(data):
    return hashlib.sha256(data).hexdigest()

for name, expected in DLLS.items():
    data = (ROOT / 'Runtime' / name).read_bytes()
    assert sha(data) == expected, f'Official loader identity changed: {name}'
    offset = struct.unpack_from('<I', data, 0x3c)[0]
    assert data[offset:offset+4] == b'PE\0\0'
    assert struct.unpack_from('<H', data, offset+4)[0] == 0x8664

lua = json.loads((ROOT / 'tests/results.json').read_text())
assert lua['failures'] == 0 and lua['assertions'] == 178
assert lua['game_runtime_tested'] is False
for relative, expected in lua['production_source_sha256'].items():
    assert sha((ROOT / relative).read_bytes()) == expected, f'Untested Lua change: {relative}'
for relative, expected in lua['harness_sha256'].items():
    assert sha((ROOT / 'tests' / relative).read_bytes()) == expected

installer = json.loads((ROOT / 'validation/installer-check-results.json').read_text())
assert installer['failures'] == 0 and installer['assertions'] == 55
for relative, expected in installer['source_sha256'].items():
    assert sha((ROOT / relative).read_bytes()) == expected, f'Untested installer change: {relative}'

smoke = json.loads((ROOT / 'validation/actual-payload-install-check.json').read_text())
assert smoke['install']['exit'] == smoke['update']['exit'] == smoke['uninstall']['exit'] == 0
assert smoke['game_bytes_unchanged'] and smoke['removal_left_only_original_game_exe']
assert smoke['windows_game_executed'] is False

records = [dict(path=p.relative_to(ROOT / 'Runtime').as_posix(), size=p.stat().st_size,
                sha256=sha(p.read_bytes()))
           for p in sorted((ROOT / 'Runtime').rglob('*')) if p.is_file()]
assert len(records) == 10
(ROOT / 'payload-manifest.json').write_text(json.dumps(dict(format=1, files=records), indent=2) + '\n')
files = [ROOT/name for name in ('README.md', 'BUILD.md', 'THIRD-PARTY.md', 'LICENSE.txt',
         'Install.cmd', 'Uninstall.cmd', 'Update.cmd', 'update.ps1', 'install.ps1', 'uninstall.ps1', 'installer-notes.md',
         'payload-manifest.json')]
allowed = {'.lua', '.dll', '.cmd', '.ps1', '.ini', '.md', '.txt', '.json', '.py'}
for folder in ('Runtime', 'tests', 'tools', 'licenses', 'validation'):
    files.extend(p for p in sorted((ROOT/folder).rglob('*')) if p.is_file()
                 and '__pycache__' not in p.parts and p.suffix.lower() in allowed)
assert len(files) == len(set(files))
assert not any(p.suffix.lower() == '.exe' for p in files)
assert {p.relative_to(ROOT).as_posix() for p in files if p.suffix.lower() == '.dll'} == {
    'Runtime/UE4SS.dll', 'Runtime/dwmapi.dll'}
output = ROOT.parent / f'LostBudapest-Noclip-{VERSION}.zip'
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for p in files:
        info = zipfile.ZipInfo(p.relative_to(ROOT).as_posix(), (2026, 10, 31, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o100644 << 16
        archive.writestr(info, p.read_bytes(), compresslevel=9)
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
    for p in files:
        assert archive.read(p.relative_to(ROOT).as_posix()) == p.read_bytes()
    for record in records:
        assert sha(archive.read('Runtime/' + record['path'])) == record['sha256']
report = dict(version=VERSION, path=str(output), size=output.stat().st_size,
              sha256=sha(output.read_bytes()), entries=len(files), lua_assertions=178,
              installer_assertions=55, actual_payload_install_uninstall_verified=True,
              archive_crc_and_entry_bytes_verified=True, game_runtime_tested=False)
output.with_suffix('.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
