# Source and validation

The trainer source is the ten Lua files under
`Runtime/Mods/LostBudapestNoclip/Scripts/`. There is no compiled trainer logic.
The only DLLs are unmodified files from official UE4SS 3.0.1, listed with hashes
in `payload-manifest.json` and attributed in `THIRD-PARTY.md`.

Source checkouts do not track the official loader DLLs. Restore their exact
verified release bytes with `python tools/fetch_loader.py` before validation or
installation. The ready-to-install ZIP already contains both DLLs.

Lua checks use Python and Lupa's Lua 5.4 runtime:

```text
python -m venv .venv
.venv/bin/pip install -r tests/requirements.txt
.venv/bin/python tests/run.py
```

On Windows, use `.venv\Scripts\python.exe` and `pip.exe` instead. Installer
filesystem fixtures require PowerShell 7 plus a local copy of the approved game
EXE; the game is never executed by the checks. See `tests/README.md`.

Run `python tools/package.py` to verify the recorded source identities and
dependency bytes, regenerate the payload manifest and create the release ZIP.
The game EXE and research toolchains are excluded from releases.

Current results: **245 Lua assertions and 55 installer assertions pass**.
The actual runtime payload was also installed and removed in an isolated
filesystem fixture, leaving the original game EXE unchanged. The loader proxy
exports every DWM function imported by the supplied game EXE.

The Lua tests simulate Unreal and UE4SS boundaries. Installer checks ran in
PowerShell on Linux. No Windows game, native loader injection, Windows folder
picker or Windows PowerShell 5.1 session was executed. The initial build needs
an in-game check; the reported assertion counts do not establish that it works
in the actual game.
