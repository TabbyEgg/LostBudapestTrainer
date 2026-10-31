# Lost Budapest Trainer 0.3.1

[**Download the latest ZIP from Releases**](https://github.com/TabbyEgg/LostBudapestTrainer/releases/latest)

Noclip, god mode, vehicle spawning and experimental trainer driving for the
Windows demo. Targets the supplied Unreal 4.27.2 build of
`EltuntBP-Win64-Shipping.exe`, SHA256
`2e5f4d5b66da873a488287b580c2ba3dd91ed892727cfd71ecbd610d6a08f284`.

## Install and update

Close the game, extract the ZIP into its own folder, and run **Install.cmd**.
Select the game folder containing `Lost_Budapest_Demo.exe`, or its
`Eltunt_Budapest3\Binaries\Win64` folder, then launch normally.

**Already installed? Run Update.cmd instead.** It downloads the latest official
release, checks GitHub's asset SHA256, and upgrades the selected installation
without a manual uninstall. Original uninstall backups and edited `config.lua`
are retained. This new ZIP supplies Update.cmd for the first time; keep it for
future one-command updates. The game must be closed.

Updates stop before overwriting edited implementation files or conflicting
loaders. If your configuration was edited, its speeds and key choices stay as
written; new `VehicleKeys` default to the keys below when absent. For an offline
package upgrade, use `install.ps1 -Update -GameDirectory 'your game folder'`.

**Uninstall.cmd** removes/restores files recorded in the receipt. Edited files
are retained for review. Keep the receipt and backup folder in the game folder.

## Menu

Press **Insert** in a loaded game to open or close the trainer menu. Click a row,
or use **Up/Down** to select, **Left/Right** for speed/model, **Enter** to activate,
and **Backspace** to close. Speed and model selection stay open; spawning, entry,
repair and noclip actions close the menu before restoring gameplay controls and
executing. Flight, god mode/landing protection, speed and driving status are live.
Recent trainer messages, including spawn errors, appear on the HUD.

The menu uses the game's Blueprint HUD canvas, including a fallback for compiled
HUD event graphs. It never replaces your HUD or changes game assets. If the HUD
is unavailable it closes automatically and leaves hotkeys active. Menu drawing
and the revised vehicle spawn path still need in-game verification on this build.

The default binding is `MenuKey = "INS"` in `config.lua` (the stable loader's name for Insert). Older `INSERT` configurations are accepted automatically.
Repeated key-down callbacks are ignored until you release the key.

## Controls

| Key | Action |
| --- | --- |
| Insert | Open/close trainer menu |
| F1 | Recover/repair occupied or nearby supported vehicle |
| F2 | Cycle selected spawn model; selected name appears in UE4SS.log |
| F3 | Read vehicle diagnostics into UE4SS.log |
| F4 | Toggle god mode |
| F5 | Enter/exit experimental trainer-driving mode |
| F6 | Toggle noclip |
| F7 / F8 | Lower / raise flight speed |
| F9 | Spawn selected vehicle in front of you |
| F10 | Return to the noclip entry point and disable flight |

Flight: WASD relative to your view, E/Space up, Q/Ctrl down, Shift boosts 3x.
Speeds: 2, 6, 12, 24, 48, 72, 96, 144, 240 and 480 m/s. Default is 6 m/s.
God mode follows the controlled pawn, including trainer vehicle possession,
and uses Unreal's standard damage permission. Flight automatically keeps
that protection until grounded for 0.75 game seconds after disabling noclip.
Native ApplyDamage and ApplyPointDamage calls are intercepted before health
processing for the protected player only. For Abel, protection also preserves a living player's captured positive `Health`
value and limits falling velocity to 3 m/s. It does not resurrect a pawn already
killed by a scripted event or prove protection against every custom instant kill.
F4 toggles manual protection; flight applies the guard automatically.

Spawn selection: **Abel's car** (default), estate, hatchback, liftback, luxury,
van 1 and van 2. These are actual classes recorded in the provided game log.
Only already-loaded blueprints are used. The default cap is **10** live trainer
spawns, configurable with `MaxVehicles` (1–50); older configs use 10 automatically.
The menu shows the current count. A spawn only counts after its actual position
is checked. Blocked placements try other positions ahead; all blocked attempts
remove the failed car rather than leaving it near the player. Spawn in a clear area; the game may reject an obstructed position. Version 0.3.0
uses Unreal's native Summon function to avoid the stable loader's nested
FTransform serialization problem. The temporary spawn helper, class spawn
settings and player collision state are restored immediately after each call;
the engine builds the spawn transform itself. Failed spawns include the stage
and traceback in the log.

Try the game's normal enter-vehicle interaction for Abel's car. Traffic cars
may lack normal player-entry logic. **F5 provides separate trainer driving**:
stand on foot within 12 metres of Abel's car or a trainer-spawned car and press
F5. **Abel's car keeps its own Blueprint controls, ticking and camera**; the
trainer no longer overrides its throttle, steering or radio-related Blueprint
logic. Radio operation on newly spawned cars still needs in-game confirmation.

Traffic cars use fallback controls: W forward, S reverse, A/D steering, Space
brake. Their camera is attached to the car and follows each engine frame, rather
than being teleported by the input timer. Traffic cars have no verified game
radio integration. Press F5 again to restore your character, collision and
visibility. Exit placement is swept; an obstruction can stop the character
before reaching the intended spot beside the car. Turn noclip off before entry.

F1 prioritizes your occupied car, then the nearest player car/trainer spawn
within 12 metres. It rights the vehicle and clears motion. It invokes a
recognized repair function only if reflection verifies it takes no inputs,
or restores recognized numeric health/max-health pairs. If the blueprint
exposes neither, the log explicitly says **damage was not changed**; this is
physical recovery, not an invented full damage repair. Existing unrelated
traffic vehicles are not modified.

Speeds and bindings can be edited in
`Mods\LostBudapestNoclip\Scripts\config.lua`; restart the game after editing.

## Status and limits

Trainer messages are in `Eltunt_Budapest3\Binaries\Win64\UE4SS.log`.
F3 now includes nearby vehicle repair/entry function names and relevant property
names. Send that log if repair or entry is unsupported.

Flight and speed controls were confirmed working by the user. The user confirmed
vehicle spawning in 0.3.0. Version 0.3.1 addresses the missing Insert binding,
blocked placement, native car control/camera and custom health/fall guards.
These changes still require in-game verification;
automated Lua tests use simulated game objects. Installer/update fixtures run
PowerShell on Linux; Windows folder selection remains untested here.

All engine access is through reflected functions on the game thread. Game EXE
and save files are not modified. Use a full game restart after changing scripts;
live Lua reload is disabled so modified pawn state is not orphaned.

For a source checkout, run `python tools/fetch_loader.py` to restore the pinned
UE4SS DLLs before installation. The release ZIP already contains them and needs
no Python. See `BUILD.md`, `tests/` and `validation/` for source and evidence.
Official UE4SS 3.0.1 is bundled under its MIT license; see `licenses/`.
