#!/usr/bin/env python3
"""Restore the two pinned official UE4SS DLLs for a source checkout."""
from pathlib import Path
import hashlib
import io
import os
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
URL = 'https://github.com/UE4SS-RE/RE-UE4SS/releases/download/v3.0.1/UE4SS_v3.0.1.zip'
ARCHIVE_SHA256 = '4b47d4bceddd2f561a4e395bfa00924ccfc945af576a2d0c613e6537846c57ec'
EXPECTED = {
    'UE4SS.dll': '8ac18fbffc1ef96b0662d4a2d537b3f224c26d65caaba7989a9404c566102b26',
    'dwmapi.dll': 'ce596412befa68c30b7f88f65beb77d9bdad55e9b96a276a5a9cf690c63f24bb',
}

def digest(data):
    return hashlib.sha256(data).hexdigest()

if all((ROOT/'Runtime'/name).is_file() and digest((ROOT/'Runtime'/name).read_bytes()) == sha
       for name, sha in EXPECTED.items()):
    print('Both official UE4SS 3.0.1 dependencies already match.')
else:
    with urllib.request.urlopen(URL, timeout=60) as response:
        data = response.read(5523403)
    assert len(data) == 5523402 and digest(data) == ARCHIVE_SHA256, 'Official release archive identity mismatch'
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        payload = {name: archive.read(name) for name in EXPECTED}
    for name, sha in EXPECTED.items():
        assert digest(payload[name]) == sha, 'Dependency identity mismatch: ' + name
    folder = ROOT/'Runtime'
    folder.mkdir(parents=True, exist_ok=True)
    for name, value in payload.items():
        destination = folder/name
        temporary = folder/(name+'.download-tmp')
        try:
            temporary.write_bytes(value)
            os.replace(temporary, destination)
        finally:
            if temporary.exists():
                temporary.unlink()
    print('Restored both verified official UE4SS 3.0.1 DLLs; no game files were accessed.')
