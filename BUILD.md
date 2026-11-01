# Source and validation

The trainer source is the eleven Lua files under
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

Current results: **318 Lua assertions and 61 installer assertions pass**.
The actual runtime payload was also installed and removed in an isolated
filesystem fixture, leaving the original game EXE unchanged. The loader proxy
exports every DWM function imported by the supplied game EXE.

The Lua tests simulate Unreal and UE4SS boundaries. Installer checks ran in
PowerShell on Linux. No Windows game, native loader injection, Windows folder
picker or Windows PowerShell 5.1 session was executed. The initial build needs
an in-game check; the reported assertion counts do not establish that it works
in the actual game.

Version 0.4.3 uses a temporary native vehicle template profile during synchronous
actor construction. Model mesh/animation/physics and wheel data are installed
before physics initialization, then the exact original template is restored.
Cases exercise one-based UE4SS arrays without resizing, incompatible rigs,
construction overrides, partial writes, animation/physics mismatch, source
instance fallback, immutable paint parents and native/legacy spawn routing.
The user's 0.4.0 screenshot shows a converted estate with the native speedometer
and radio HUD. Their log records successful estate construction, plus unit-scale
refusals for the other five model selections. The same screenshot/report shows
an extra open door panel and reversed A/D steering. Current boundary cases
cover positive per-axis scale copying without late physics resizing, converted-only
queued keyboard steering correction, door-component maintenance, legacy key migration, F2 HUD
rendering/lock restoration and 100 placements without a spawn limit. The new code
has not been executed in the Windows game here.

0.4.2 removes the four native engine-wide setter hooks added in 0.4.1. The user's
paired logs show the trainer enabled with all four hooks and a reported fatal
level-load error, and disabled with a successful user-confirmed level load. The
enabled log contains no native crash stack or Lua error, so it does not identify
the exact failing native call. This is a rollback of the new startup interception
plus a replacement limited to trainer-owned converted cars, not a reproduced
Windows crash here. Startup checks reject any attempt to register those setter
hooks and verify no world access or maintenance queue before a converted car
exists. Maintenance checks cover ownership changes, destroyed components,
keyboard release, analog input, pause/menu gating and isolated error handling.

The installer recovery exception accepts a changed mods.txt only when merging
the trainer entry back on reproduces its exact prior recorded SHA256. Cases
verify disabled-entry recovery and original uninstall backups, while unrelated
mod-list edits still reject the update without changing files or the receipt.

0.4.3 replaces the script-observed Canvas renderer with AHUD's native text queue.
HUD.cpp PostRender calls DrawDebugTextList independently of ReceiveDrawHUD and
bShowHUD. HUD.h declares AddDebugText/RemoveDebugText as native client RPCs with
no DevelopmentOnly metadata. Their names, PC GetHUD/GetViewportSize/deprojection
and K2_TeleportTo are present in the supplied shipping binary. Queued updates
submit finite-duration text keyed to the local HUD actor, use flat FVector/FColor
arguments and remove only that keyed entry. No global renderer hooks are added.
The user log proves F2 requests and F3 selection but contains no old Canvas draw
success; it also reports opaque Van 1 errors and strict placement rejection.
This change has modeled native-boundary validation here, not a Windows engine
run. Placement fixtures cover collision-adjusted TeleportTo destinations,
player separation, refused destinations, staged failures and exact cleanup.
