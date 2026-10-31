#!/usr/bin/env python3
"""Apply the reviewed, body-only release edits; refuse concurrent text changes."""
from pathlib import Path
import hashlib
import json
import subprocess

REPOSITORY = 'TabbyEgg/LostBudapestTrainer'

def api(path, data=None):
    args = ['gh', 'api', path]
    if data is not None:
        args += ['--method', 'PATCH', '--input', '-']
    result = subprocess.run(args, input=json.dumps(data) if data is not None else None,
                            text=True, capture_output=True, check=True)
    return json.loads(result.stdout)

for edit in json.loads((Path(__file__).resolve().parents[1] / '.github/release-note-edits.json').read_text()):
    path = f'repos/{REPOSITORY}/releases/{edit["id"]}'
    release = api(path)
    assert release['tag_name'] == edit['tag']
    body = release.get('body') or ''
    if body == edit['new_body']:
        print(f'{edit["tag"]}: already updated')
        continue
    assert hashlib.sha256(body.encode()).hexdigest() == edit['old_body_sha256'], f'Release text changed concurrently: {edit["tag"]}'
    updated = api(path, {'body': edit['new_body']})
    assert updated['body'] == edit['new_body']
    print(f'{edit["tag"]}: description updated')
