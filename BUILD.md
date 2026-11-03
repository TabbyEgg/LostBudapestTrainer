# Source and validation

The trainer source is the fifteen Lua files under
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

Current results: **525 Lua assertions and 61 installer assertions pass**, recorded
in `tests/results.json` and `validation/installer-check-results.json`.
The actual runtime payload was also installed and removed in an isolated
filesystem fixture, leaving the original game EXE unchanged. The loader proxy
exports every DWM function imported by the supplied game EXE.

The Lua tests simulate Unreal and UE4SS boundaries. Installer checks ran in
PowerShell on Linux. No Windows game, native loader injection, Windows folder
picker or Windows PowerShell 5.1 session was executed. The initial build needs
an in-game check; the reported assertion counts do not establish that it works
in the actual game.

Version 0.4.5 uses a temporary native vehicle template profile during synchronous
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

0.4.4 fixes a concrete pinned-loader ABI mismatch: LuaUObject.cpp179-200 references
scalar out tables without consuming each argument. GetViewportSize writes both
SizeX and SizeY into the first table. Passing one table twice matches that
behavior and a conforming implementation; the regression boundary now models
both writes into the first table instead of assuming separate outputs.

The new steering.lua changes paired A/D scales in InputSettings defaults only
while ForceRebuildKeymaps copies them into runtime input, and restores the exact
defaults immediately. It calls no SaveConfig, SaveKeyMappings or InvertAxis.
Exit/menu/pause/disable/restart rebuild normal runtime mappings. Pending cleanup
retains scheduling priority. ForceRebuildKeymaps refreshes all local PlayerInput
objects, so unsaved runtime-specific input remaps may be replaced by project
configuration; this demo workflow has one local player.

The supplied 0.4.3 log shows the viewport guard failing, failed F5 target lookup,
rapid repeated successful spawns and failed door component-array lookup. The
truck entry selector now uses tracked references within25m. Footprint tests
reject roof stacks even when native TeleportTo reports success; native bounds
use struct output tables, with a conservative6mx3m fallback. Hotkey tests cover
pending coalescing and cooldown reset. No Windows game is executed here.

0.4.5 addresses another concrete v3.0.1 stack-consumption defect. In
LuaUObject.cpp381-408, ObjectProperty.Set consumes userdata but leaves nil on
the stack. The next FloatProperty.Set reads nil via get_float (865-866), which
LuaMadeSimple.cpp569-574 converts to0 and consumes. The previous AddDebugText
call passed nil InFont before FontScale; it therefore submitted invisible
zero-scale text even though ProcessEvent returned successfully. The supplied
0.4.4 log confirms successful submissions without a Lua error; it does not
itself contain an observed native FontScale value.

The adapter now selects a valid non-CDO UFont, preserving the following scalar
arguments. No font searches or loads occur during module startup. Cache reuse,
invalid-font reacquisition, missing-font cleanup and the exact defective tail
marshaling are modeled. Optional native DebugTextList inspection records the
actual scale and rejects a readable zero scale; metadata-read failures are
nonfatal. These checks do not observe pixels in the Windows game.

The user's supplied 0.4.5 menu screenshot confirms that the native HUD text is
visible in their game, including the feature rows and live speed/model values.

0.4.6 copies observed material vector overrides into a detached Lua snapshot,
then creates private dynamic materials on each converted car. It accepts only
global parameters (`EMaterialParameterAssociation::GlobalParameter = 2`) and
randomizes recognized body-paint values with one coherent period colour per
car. Glass, chrome, tyre, interior, roof and opacity values are preserved. A
random matching live traffic instance supplies existing schemes; source traffic
materials and immutable parents are never written. Missing metadata retains the
available source appearance, and a cosmetic failure does not discard a valid car.
Only vector overrides are cloned from source dynamic materials; scalar/texture
overrides continue to use the immutable parent's values.

Separate original wheel mesh components are hidden only when owned by the
converted native car. The selected root mesh, its wheel bones and physics-wheel
data are excluded, as are steering-wheel meshes. The same queued ownership and
identity checks maintain extra-door and wheel visibility without engine-wide
hooks. The hatchback driver adjustment hides a validated humanoid head bone on a
secondary owned mesh, retaining torso, hands and animation. No verified model-specific
seat anchors are available, so it avoids guessed seat transforms.

F5 restores the previous walking movement and collision state at the current
flight location before vehicle capture. Entry stops if that restoration fails,
including after automatic retry exhaustion, and F5 can retry the retained
snapshot. Native F interaction geometry remains model dependent. Diagnostic
reflection output now stays in `UE4SS.log`; the HUD receives a single completion
or failure summary, and failures restore the notice callback.

0.4.7 extends owned cosmetic matching with the exact original native body asset
and original wheel-attachment socket names captured before template changes.
Generic secondary components can therefore qualify without wheel-like names,
while the selected root mesh and its physics wheel rig remain excluded. The
fallback scan includes skinned and poseable meshes. Wheel hiding no longer
propagates to child components, and maintenance rejects changed assets or
attachments. The user confirms the 0.4.6 hatchback head adjustment works; their
remaining wheel-overlap screenshots do not identify which component renders the
visible geometry. These additional identity paths are checked without claiming
that the actual remaining geometry has been identified in the Windows game.

A queued normal-F fallback considers only nearby tracked converted cars. A
0.25-second game-time grace gives native input its normal frame first. Native
entry takes priority if it changes the pawn or locks the walking character;
the action remembers entry versus exit so a normal exit cannot turn into
re-entry. Noclip state must restore successfully before vehicle capture, which
also rejects unowned MOVE_None state and changed target/character identities.
The grace uses game time and is cancelled by menu/restart or a backwards clock.
The fallback uses the existing trainer possession path rather than guessing native
interaction-box transforms or Blueprint entry-function parameters.

The catalog discovers additional already-loaded concrete vehicle Blueprints,
verifying vehicle ancestry and an animated body/wheel rig before adding them.
Discovery performs no asset loads or module-startup world access, and merging
preserves existing aliases and the selected model. Steering correction now runs
automatically for converted cars, with no menu/config toggle; an older retained
configuration's toggle value is ignored. Runtime mapping restoration still
applies on exit, pause and menu activity.

The supplied 0.4.5 log records additional Coupe, Sedan and SUV blueprints. It
also maps BP_Coupe to `/Game/Autok/Fiat/Fiat_rigged.Fiat_rigged`; the selector
labels this model `Coupe (small Fiat)` to distinguish it from Hatchback. The
new user-provided cars.zip labels all seven original selections for reference;
the pictures do not expose runtime component identities or native entry state.
