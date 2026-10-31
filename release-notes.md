## 0.3.0 — trainer menu and revised vehicle spawning

- **Insert** opens a mouse/keyboard trainer menu: noclip, god mode, flight speed, return, vehicle model, spawn, enter/exit, recovery/repair and diagnostics.
- Live status and recent trainer messages are visible on the HUD. Up/Down selects, Left/Right adjusts, Enter activates, Backspace closes.
- Vehicle and camera spawning now use Unreal's native Summon function, avoiding UE4SS 3.0.1's nested FTransform serializer. Temporary helper/settings are restored on success and failure. This addresses the native spawn failure reported with 0.2.0 but still needs an in-game retest.
- Spawn failures include the failing stage and traceback. Original function-address-only errors are no longer the sole diagnostic.
- Existing hotkeys and Update.cmd remain available. The menu releases its input locks on close, player changes and rendering failure; missing HUD callbacks never lock input.

Fully quit the game, run **Update.cmd**, then launch and press **Insert**. New menu drawing and revised spawning are experimental until verified in-game. Repair remains physical recovery when the vehicle exposes no verified health repair.
