#!/usr/bin/env python3
"""Exercise shipped Lua against deterministic UE4SS/game-boundary doubles.

This never launches the Windows game or loads native DLLs. Requires lupa.
"""
import hashlib
import json
from pathlib import Path
import sys

from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
HERE = Path(__file__).resolve().parent
SCRIPTS = ROOT / 'Runtime/Mods/LostBudapestNoclip/Scripts'
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().TRAINER_SCRIPTS = str(SCRIPTS)
lua.globals().TRAINER_ROOT = str(ROOT)
captured = []
lua.globals().TEST_PRINT = lambda text: captured.append(str(text))
try:
    lua.execute((HERE / 'regressions.lua').read_text())
except Exception as error:
    captured.append('HARNESS ERROR: ' + str(error))
    (HERE / 'results.txt').write_text('\n'.join(captured) + '\n')
    print('\n'.join(captured))
    raise
summary = {
    'assertions': int(lua.globals().TEST_ASSERTIONS),
    'failures': int(lua.globals().TEST_FAILURES),
    'lua_implementation': lua.lua_implementation,
    'production_source_sha256': {
        p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(SCRIPTS.glob('*.lua'))
    },
    'harness_sha256': {
        p.name: hashlib.sha256(p.read_bytes()).hexdigest()
        for p in [HERE/'run.py', *sorted(HERE.glob('*.lua'))]
    },
    'game_runtime_tested': False,
    'ue4ss_native_loader_executed': False,
}
(HERE / 'results.txt').write_text('\n'.join(captured) + '\n')
(HERE / 'results.json').write_text(json.dumps(summary, indent=2) + '\n')
print('\n'.join(captured))
sys.exit(1 if summary['failures'] else 0)
