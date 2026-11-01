## 0.4.1 — F2 menu and vehicle fixes

- **F2 opens/closes the menu; F3 cycles cars; F9 spawns; Home writes diagnostics.** Older configs automatically use the new reserved shortcuts.
- **No trainer spawn cap.** Old `MaxVehicles` values are ignored, and the menu shows the live count.
- Hide the extra original Ábel door meshes and their collision on converted model spawns, including after entering or exiting.
- Correct reversed A/D steering on converted cars, including normal entry with the game's F key. The menu's **Steering correction** toggle restores original inputs when off.
- Preserve each selected model's positive mesh scale before physics creation, removing the unit-scale refusal affecting hatchback, liftback, luxury and van selections.
- Log the menu request and its first actual HUD draw separately to make display problems easier to identify.

Close the game and run **Update.cmd**, then spawn a new car. Existing map traffic and the original Ábel car keep their own doors and steering. Models must be loaded and have a compatible wheel rig; spawn in a clear area.
