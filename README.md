# Lost Budapest Trainer 0.4.6

[**Download the latest ZIP from Releases**](https://github.com/TabbyEgg/LostBudapestTrainer/releases/latest)

Noclip, god mode, vehicle spawning and trainer driving for the
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
are retained. Keep Update.cmd for future one-command updates. The game must be closed.

Updates stop before overwriting edited implementation files or conflicting
loaders. Edited speeds and optional custom bindings are retained. **F2 is reserved for
the menu and F3 for model selection**, including with older configs. A conflicting
old diagnostics binding moves to Home. For an offline
package upgrade, use `install.ps1 -Update -GameDirectory 'your game folder'`.

**Uninstall.cmd** removes/restores files recorded in the receipt. Edited files
are retained for review. Keep the receipt and backup folder in the game folder.

## Recovery from the 0.4.1 loading crash

Close the game and run **Update.cmd**. Version 0.4.2 removes the engine-wide
steering, visibility and collision setter hooks added in 0.4.1. Converted-car
adjustments now run only through the trainer's queued game-thread update, after
a converted car exists. The updater also re-enables the trainer if you disabled
its entry in `Mods\mods.txt`.

To temporarily disable the trainer, set `LostBudapestNoclip : 0` in that file.

## Menu

Press **F2** in a loaded level to open or close the keyboard menu.
Use **Up/Down** to select, **Left/Right** to adjust a speed or model, **Enter**
to activate and **Backspace** to close. The selected row starts with `>`.
The menu supplies a real game font so the bundled SDK preserves its text scale.
The menu displays all trainer features and their live values as text over the
game. It does not use mouse clicks.

F2 works with older Insert configurations too. Speed/model selection and toggles
stay open. Spawning, entry, repair and noclip close the menu and release its
movement/look locks before executing. Recent action messages also appear briefly
on screen, so **F3** car selection is visible without opening the menu.

### Vehicle boost

The menu's **Vehicle boost** row selects Off, 60, 100, 150, 200 or 300 km/h.
Hold **Shift + W** while driving to add forward acceleration toward that target.
Release Shift or brake to stop the extra thrust. Boost starts off and works with
trainer driving or a normally entered supported car. It preserves native
steering/camera and applies no vertical force; it is a boost target rather than
a hard speed limiter.

## Controls

| Key | Action |
| --- | --- |
| F2 | Open/close trainer menu |
| F1 | Recover/repair occupied or nearby supported vehicle |
| F3 | Cycle selected spawn model; selected name appears in UE4SS.log |
| Home | Read vehicle diagnostics into UE4SS.log |
| F4 | Toggle god mode |
| F5 | Enter/exit trainer-driving mode |
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
van 1 and van 2. Models must already be loaded in the current level.
Only already-loaded blueprints are used. **There is no trainer spawn cap**; old
`MaxVehicles` settings are ignored. The menu shows the live spawned count. Repeated queued spawn requests are
combined, with 0.75 seconds between F9 attempts.
Spawning many vehicles still consumes game memory and physics resources. A spawn only counts after its actual position
is checked. Blocked placements try up to 40 positions around you, out to 20 metres. The
engine checks each destination and may adjust it to fit, rather than sweeping a
path through curbs or parked cars. Vehicle footprints are checked before and
after adjustment, so a car cannot be accepted on another car's roof. All rejected attempts
remove the failed car rather than leaving it near the player. Spawn in a clear
area. Failed spawns report the model and reason in the menu message and log.

### Shared player vehicle setup

**Player vehicle setup is on by default.** Estate, hatchback, liftback, luxury
and van selections use Abel's player-vehicle Blueprint with the selected model's
body, animation, physics asset and wheel rig. This gives compatible models the
same player controls, speedometer, radio and camera setup as Abel's car.

Converted models hide the separate original Ábel door and wheel meshes. Doors
retain query collision for interaction; hidden cosmetic wheels have no collision.
The selected model's own wheel rig and the interior steering wheel are retained.
The hatchback also hides the recognized driver's head bone to prevent it protruding
through the roof, while keeping the body and hands. This is a cosmetic adjustment;
it does not move the seat. Unrecognized driver skeletons are left unchanged.

Spawned replacement models use varied loaded traffic paint schemes and random
period-style body colors where a supported paint parameter is available. Each
spawn gets its own dynamic paint material, so repainting a new car cannot repaint
existing traffic or earlier spawns. Unrecognized paint parameters retain their
source colors. Body paint changes leave captured glass, trim and roof colors unchanged.

Component lookup can fall back
to the SDK object list if the component-array call is unavailable. Doors that are part
of the selected body stay with that body. **Keyboard steering fix** defaults on for
these converted cars, including normal game entry with F. It updates the native A/D axis mappings used by the car, while leaving gamepad
entries unchanged. Normal runtime mappings are restored when you exit, pause,
open the trainer menu or disable the fix; no input settings are saved to disk. Toggle it in the menu,
or set `InvertVehicleSteering = false` in `config.lua` to retain original inputs.

This applies to new trainer spawns. Existing map traffic and the original Abel
car are left alone. Stand on foot within **25 metres** and press **F5** to enter or
exit a spawned car. F5 switches noclip off at your current location before entry.
Use F5 if the game's F interaction prompt is unavailable on a replacement body.

A model must have a loaded animated body, matching wheel count, valid wheel
bones and finite positive mesh scale. Authored scale is applied before vehicle
physics is created; zero or mirrored scale is refused. An incompatible rig, or one replaced during game
construction, cancels the spawn with a log message. A cosmetic hiding or paint failure does not reject an otherwise valid matched
vehicle; it is reported separately. The trainer never silently substitutes the
AI driving setup when player setup is selected.

Set `PlayerVehicleSetup = false` in `config.lua` to restore legacy traffic
spawning. Legacy traffic driving uses W/S, A/D and Space with an attached camera;
it has no player radio or native speedometer. F5 returns to the original
character. Exit placement is swept, so an obstruction can stop the character
before reaching the intended spot beside the car.

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
Home includes nearby vehicle repair/entry function names and relevant property
names. Detailed diagnostics stay in the log; the HUD shows a short completion
message. Send that log if repair or entry is unsupported.

All engine access is through reflected functions on the game thread. Game EXE
and save files are not modified. Use a full game restart after changing scripts;
live Lua reload is disabled so modified pawn state is not orphaned.

For a source checkout, run `python tools/fetch_loader.py` to restore the pinned
UE4SS DLLs before installation. The release ZIP already contains them and needs
no Python. See `BUILD.md`, `tests/` and `validation/` for source and evidence.
Official UE4SS 3.0.1 is bundled under its MIT license; see `licenses/`.
