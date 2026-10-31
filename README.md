# Lost Budapest Noclip 0.1.1

[**Download the ready-to-install trainer ZIP**](https://github.com/TabbyEgg/LostBudapestTrainer/raw/refs/heads/main/downloads/LostBudapest-Noclip-0.1.1.zip)

A removable noclip/free-flight trainer for the Windows Lost Budapest demo.
Built for the supplied `EltuntBP-Win64-Shipping.exe`: Unreal Engine 4.27.2,
SHA256 `2e5f4d5b66da873a488287b580c2ba3dd91ed892727cfd71ecbd610d6a08f284`.

## Install

1. Fully close Lost Budapest.
2. Extract the trainer ZIP to its own folder. Run **Install.cmd** and select the
   game folder containing `Lost_Budapest_Demo.exe`. The installer also accepts
   the game's `Eltunt_Budapest3\Binaries\Win64` folder.
3. Launch the game normally. Enter a level on foot and press **F6**.

The installer checks the game build and package hashes, installs the bundled
official UE4SS 3.0.1 loader, and enables only this trainer. It preserves existing
mod entries and backs up configuration changes. If a different loader already
occupies the required DLL paths, it stops before changing files.

## Controls

| Key | Action |
| --- | --- |
| F6 | Toggle noclip at the current position |
| W / A / S / D | Fly relative to your view; looking up/down changes forward flight |
| E or Space | Move vertically up |
| Q or left Ctrl | Move vertically down |
| Shift | Hold for 3x speed |
| F7 / F8 | Lower / raise speed |
| F10 | Return to where you enabled noclip, then turn it off |

Five speed levels: 2, 6, 12, 24 and 48 metres/second. The initial speed is 6 m/s.
Use F10 to return before ending flight inside geometry. F6 turns collision back
on wherever you are. Pausing stops flight; possession/map changes turn noclip
off. It starts off every time the game launches.

Speed levels and function keys can be edited in
`Mods\LostBudapestNoclip\Scripts\config.lua` after installation. Fully restart the
game after editing. Live script reload is disabled because UE4SS 3.0.1 has no Lua
unload callback to restore modified player state.

## Uninstall

Close the game and run **Uninstall.cmd**, selecting the same game folder.
The receipt records which files this installer added or backed up. Files changed
since installation are preserved instead of being overwritten during removal.

## Status and testing

Messages beginning `[Lost Budapest Noclip 0.1.1]` appear in
`Eltunt_Budapest3\Binaries\Win64\UE4SS.log`.

This is a first experimental build. The submitted executable was statically
inspected and Lua behavior is checked with simulated Unreal objects. The game
has not been run here; loader startup, actual flight and collision need an
in-game check. If F6 does nothing, send `UE4SS.log` from that folder. If the game
does not start, run the uninstaller with the game closed and send the same log.

The trainer changes the current player's collision and movement state through
reflected Unreal functions. It uses no fixed game-memory addresses and does not
modify the game executable or save files. It restores the old movement mode and
collision state when disabled, unless the game has already chosen a different
movement mode. The original game executable is not included.

Source, checks and dependency provenance are included. The UE4SS loader is
redistributed under its MIT license; see `licenses/` and `THIRD-PARTY.md`.

For a Git source checkout, run `python tools/fetch_loader.py` first to restore
the pinned official loader DLLs, then use Install.cmd. The downloadable ZIP
already contains those DLLs and requires no Python installation to use.

## Vehicle diagnostics

Stand beside an enterable vehicle and press **F11** once. Send
`Eltunt_Budapest3\Binaries\Win64\UE4SS.log`. The diagnostic reads loaded
vehicle/pawn class names and available health/controller fields; it does not
repair or spawn anything yet. If upgrading, close the game and uninstall the
previous trainer before installing this version.
