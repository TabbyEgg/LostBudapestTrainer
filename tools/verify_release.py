#!/usr/bin/env python3
"""Verify the tracked ready-to-install ZIP against repository sources."""
from pathlib import Path, PurePosixPath
import ast
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
metadata = json.loads((ROOT/'downloads/release.json').read_text())
archive_path = ROOT/'downloads'/metadata['filename']
assert archive_path.parent == ROOT/'downloads'
source_version = next(n.value.value for n in ast.parse((ROOT/'tools/package.py').read_text()).body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='VERSION' for t in n.targets))
current = metadata['version'] == source_version
data = archive_path.read_bytes()
assert len(data) == metadata['size']
assert hashlib.sha256(data).hexdigest() == metadata['sha256']
with zipfile.ZipFile(archive_path) as archive:
    assert archive.testzip() is None
    assert len(archive.namelist()) == len(set(archive.namelist()))
    for name in archive.namelist():
        relative = PurePosixPath(name)
        assert not relative.is_absolute() and '..' not in relative.parts
        assert not name.lower().endswith('.exe')
        if current:
            assert archive.read(name) == (ROOT/name).read_bytes(), 'Release/source mismatch: '+name
    payload = json.loads(archive.read('payload-manifest.json'))
    for entry in payload['files']:
        content = archive.read('Runtime/'+entry['path'])
        assert len(content) == entry['size']
        assert hashlib.sha256(content).hexdigest() == entry['sha256']
print('Release ZIP and payload hashes verified; no game EXE included. ' + ('Packaged source matches.' if current else 'Archived release; current source version differs.'))
