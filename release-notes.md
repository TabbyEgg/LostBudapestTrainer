## 0.4.2 — level-loading crash recovery

- Remove the four engine-wide steering, visibility and collision setter hooks introduced in 0.4.1 after reports of a fatal error while loading the level.
- Maintain extra-door hiding only for converted trainer cars through the existing queued game-thread update.
- Apply the **Keyboard steering fix** only to the locally controlled converted car while A/D is held. No converted-car maintenance starts before one is spawned.
- Keep **F2 menu**, **F3 model selection**, **F9 spawning**, unlimited trainer spawns and positive model-scale support.

Fully close the game and run **Update.cmd**. The update re-enables the trainer if you temporarily disabled it in `Mods\mods.txt`. Spawn a new car after entering the level.
