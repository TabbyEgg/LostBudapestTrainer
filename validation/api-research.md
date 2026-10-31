# Lost Budapest noclip API research

Target binary: `EltuntBP-Win64-Shipping.exe`, 86,158,848 bytes, SHA256
`2e5f4d5b66da873a488287b580c2ba3dd91ed892727cfd71ecbd610d6a08f284`.
This is static research; no game runtime or UE4SS injection was executed.

## Pinned loader

Official latest stable release observed: UE4SS v3.0.1, published 2024-02-14.
Tag commit: `d935b5b23bac03b65c14ae38382b02007204cc2e`.
Release: https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1

Use the stable docs/source pinned to that tag. Current `main` has additional
APIs, including a Lua unload callback, which are absent from v3.0.1.

## Verified Lua and engine interface

- `RegisterKeyBind(Key.F6, callback)` or `RegisterKeyBind(Key.F6, {ModifierKey.CONTROL}, callback)`.
  Registration callbacks only run with the game or debug console focused. Mutating Unreal
  objects from a binding should be dispatched through `ExecuteInGameThread(callback)`.
  https://github.com/UE4SS-RE/RE-UE4SS/blob/v3.0.1/docs/lua-api/global-functions/registerkeybind.md
- `LoopAsync(milliseconds, callback)` loops until callback returns true. It is not a
  game-frame tick. Queue at most one pending `ExecuteInGameThread` callback at a time.
  https://github.com/UE4SS-RE/RE-UE4SS/blob/v3.0.1/docs/lua-api/global-functions/loopasync.md
  https://github.com/UE4SS-RE/RE-UE4SS/blob/v3.0.1/docs/lua-api/global-functions/executeingamethread.md
- Reflected struct arguments accept Lua field tables (`{X=...,Y=...,Z=...}`).
  https://github.com/UE4SS-RE/RE-UE4SS/blob/v3.0.1/docs/guides/creating-a-lua-mod.md
- `FName(name, EFindName.FNAME_Find)` returns existing FName or None. Omitted mode
  defaults to adding a name. Validate keyboard names aren't None before using.
  https://github.com/UE4SS-RE/RE-UE4SS/blob/v3.0.1/docs/lua-api/global-functions/fname.md
- Unreal FKey's reflected field is `KeyName`. Official console-mod example sets
  `ConsoleKeys[1].KeyName = FName("F10", EFindName.FNAME_Find)`.
  Therefore `controller:IsInputKeyDown({KeyName=FName("W",EFindName.FNAME_Find)})`
  is the reflected native-call form. There is no direct official UE4SS example of
  IsInputKeyDown; the FKey/table form follows two independently documented APIs.
  https://github.com/UE4SS-RE/RE-UE4SS/blob/v3.0.1/assets/Mods/ConsoleEnablerMod/Scripts/main.lua
- `controller:GetControlRotation()` returns FRotator, with numeric `Pitch`, `Yaw`, `Roll`.
  https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/AController/GetControlRotation
- `pawn:K2_GetActorLocation()` returns FVector with numeric X/Y/Z. Copy scalar fields
  rather than retaining a remotely backed struct across ticks.
- `pawn:K2_SetActorLocation(locationTable, false, hitResultTable, true)` has FOUR
  explicit Unreal parameters; pass `{}` for FHitResult output, even without sweep.
  Official UE4SS sample confirms the analogous five-argument location-and-rotation call.
  https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/GameFramework/AActor/K2_SetActorLocation?application_version=5.5
  https://github.com/UE4SS-RE/RE-UE4SS/blob/v3.0.1/assets/Mods/SplitScreenMod/Scripts/main.lua
- `pawn:GetActorEnableCollision()` and `pawn:SetActorEnableCollision(bool)` operate
  on the whole actor. Snapshot the actual prior boolean and restore exactly.
- `movement:SetMovementMode(modeInteger, customInteger)` needs BOTH parameters:
  mode=0 is MOVE_None, mode=6 is MOVE_Custom; custom mode is uint8.
  Snapshot `MovementMode` and `CustomMovementMode` separately.
  https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/GameFramework/UCharacterMovementComponent/SetMovementMode?application_version=5.5
- `movement:StopMovementImmediately()` clears existing movement velocity.
- `StaticFindObject("/Script/Engine.Default__GameplayStatics"):GetTimeSeconds(pawn)`
  reads world time (dilated, stops on pause). For an asynchronous update loop,
  subtract successive world-time readings, clamp a large difference (e.g. 0.05 sec),
  and ignore zero/negative deltas. Using one-frame GetWorldDeltaSeconds each async
  callback makes speed depend on the callback/frame-rate ratio.
  https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/UGameplayStatics
- Use the official sample-supported `RegisterHook("/Script/Engine.PlayerController:ClientRestart", callback)` to restore old player state on a restart, with polling for pawn identity changes as a fallback. Do not override the native return.
  The optional `RegisterLoadMapPreHook` is deliberately not used: pinned v3.0.1
  `LuaMod.cpp` pushes five callback arguments but invokes `call_function(4, 1)`.
  https://github.com/UE4SS-RE/RE-UE4SS/blob/v3.0.1/assets/Mods/CheatManagerEnablerMod/Scripts/main.lua
  https://github.com/UE4SS-RE/RE-UE4SS/blob/v3.0.1/UE4SS/src/Mod/LuaMod.cpp

## Module layout and lifetime

`Mods/<mod>/Scripts/main.lua` is the entry point. A local
`Scripts/config.lua` can be loaded with `require("config")`; v3.0.1 LuaMod.cpp's
setup_lua_require_paths explicitly adds `<mods>/<name>/Scripts/?.lua`, shared/?.lua,
and shared/?/?.lua. Source lines 814–821:
https://github.com/UE4SS-RE/RE-UE4SS/blob/v3.0.1/UE4SS/src/Mod/LuaMod.cpp

No Lua unload callback is exposed by stable 3.0.1 LuaModRef.cpp. Configure
`[General] EnableHotReloadSystem = 0`; restore noclip before any manual script restart.
Do not rely on current-main OnUnload APIs or cache transient actors in shared ModRef
variables: the official Mod documentation warns they may outlive their actors.

For controller resolution, UEHelpers' stable helper caches the first controller
whose pawn is player-controlled; it does not check IsLocalController. Prefer a local
valid controller and reject unexpected/multiple ambiguous local players. Retain
the exact pawn/movement objects that this activation modified. If possession changes,
restore those old objects if still valid and turn the trainer off; don't apply old
snapshot values to a new pawn or automatically transfer noclip.

## Suggested movement implementation

For a character pawn with valid CharacterMovement, snapshot collision/movement mode,
disable actor collision and set MOVE_None. Drive a manually normalized vector from
WASD in control-rotation pitch/yaw, with QE as world-Z ascent/descent. Translation
uses virtual speed * world-time delta, no sweep, teleport=true. The camera remains
game-controlled, and no raw memory offsets, engine-code patches or input-axis
bindings need to be altered. Restore the exact old mode/custom-mode/collision on
toggle-off; a separate panic key can return to the recorded enable position first.

These reflected registration names are present in the submitted binary's ANSI
strings: GetTimeSeconds, GetControlRotation, K2_GetActorLocation,
K2_SetActorLocation, SetActorEnableCollision, GetActorEnableCollision,
IsInputKeyDown, IsLocalController, SetMovementMode, StopMovementImmediately,
MovementMode, CustomMovementMode, CharacterMovement, IsGamePaused and PrintString.
String presence supports API availability, but does not establish successful runtime
reflection, loader compatibility or actual noclip behavior.
