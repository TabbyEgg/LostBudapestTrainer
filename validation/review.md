# Independent trainer review

Reviewed the trainer Lua source against UE4SS **v3.0.1** (commit
`d935b5b23bac03b65c14ae38382b02007204cc2e`) and the supplied Unreal 4.27.2
shipping binary's static inspection. No Windows game runtime was executed.

## Findings addressed before packaging

1. **Do not register the stable loader's LoadMapPre callback.** In pinned
   `UE4SS/src/Mod/LuaMod.cpp`, the native callback constructs five Lua arguments
   (Engine, World, FURL, PendingGame, Error) at lines 3607–3613 but calls
   `lua.call_function(4, 1)` at line 3614. The same source's callback registration
   stores the main state in the callback record, so the string is not being
   pushed to a distinct Lua stack. `deps/first/LuaMadeSimple/src/LuaMadeSimple.cpp`
   lines 724–728 pass that count directly to `lua_pcall`. This is an upstream
   argument-count mismatch, not a trainer runtime result. The trainer now uses
   the official sample-supported `/Script/Engine.PlayerController:ClientRestart`
   hook plus its existing current-pawn comparison. It leaves normal restart
   behavior unchanged and does not use LoadMapPre.

2. **Check the old pawn identity before partial restoration.** The movement-
   component-invalid branch previously restored collision before checking the
   pawn's recorded identity. The adapter now captures a separate pawn identity
   and verifies it before either restoration branch. The composite pawn and
   movement identity still guards full restoration.

3. **Do not enable collision when an emergency return fails.** The controller
   now retains active noclip and its original snapshot if F10's return fails
   while the same pawn is controlled. This lets the player retry or fly to an
   open position. A refused move to a position already reached is accepted only
   within 0.01 Unreal units on all three axes.

## API and state checks

- `GetActorEnableCollision`, `SetActorEnableCollision`, `K2_GetActorLocation`,
  `K2_SetActorLocation`, movement mode, time, control rotation and input method
  registration strings are present in the uploaded binary. This supports the
  reflection-based design but does not prove live behavior.
- Stable `LuaUObject.cpp` marshals byte and enum properties as Lua integers and
  bool properties as Lua booleans. The movement-mode and collision assertions
  therefore agree with the loader's actual marshaling.
- The same file's struct pusher converts named Lua tables to Unreal structs,
  leaves omitted input fields at defaults, and handles output structs. The
  `FKey` table's `KeyName` and `K2_SetActorLocation(target,false,{},true)` forms
  follow the stable interface. The empty hit-result output is still supplied.
- `GetAddress` returns the underlying object address. `UObjectBase` overrides
  the generic non-null-only `IsValid`: `LuaUObject.hpp` lines 610–620 check a
  non-null object, `!IsUnreachable()` and membership in the loader's object hash
  set. `LuaUObject.cpp` lines 44–65 implement that set and its UObject-delete
  listener. The adapter uses this supported typed-object validity API and
  additional saved identities; it does not perform raw memory dereferences.
- Async/keybind callbacks do not read or mutate Unreal objects. Runtime access
  occurs in queued game-thread callbacks or the player restart hook. A pending
  flag limits the queue to one callback. Callback errors clear the flag and
  attempt state restoration. The stable ProcessEvent queue has its own
  recursive mutex and reentrant-action guard.
- The implementation snapshots collision, movement mode, custom mode and entry
  position before changes. It restores the original pawn rather than transferring
  old state to a replacement pawn. A later game-selected movement mode is left
  intact. Pause/clock resets, bounded delta, normalized input and clamped speeds
  avoid movement bursts after a pause or slow callback.
- Stable v3.0.1 has no supported Lua unload callback. The payload disables hot
  reload and documents closing the game before changing/removing the trainer.

No further blocking source-level issue was found after the changes above.
Actual loader startup, reflected calls and flight require in-game verification.

## Primary sources

- [UE4SS v3.0.1 LuaMod.cpp](https://github.com/UE4SS-RE/RE-UE4SS/blob/v3.0.1/UE4SS/src/Mod/LuaMod.cpp)
- [Lua call wrapper](https://github.com/UE4SS-RE/RE-UE4SS/blob/v3.0.1/deps/first/LuaMadeSimple/src/LuaMadeSimple.cpp)
- [UObject property marshaling and delete listener](https://github.com/UE4SS-RE/RE-UE4SS/blob/v3.0.1/UE4SS/src/LuaType/LuaUObject.cpp)
- [Typed UObject validity](https://github.com/UE4SS-RE/RE-UE4SS/blob/v3.0.1/UE4SS/include/LuaType/LuaUObject.hpp)
- [Official player-restart example](https://github.com/UE4SS-RE/RE-UE4SS/blob/v3.0.1/assets/Mods/CheatManagerEnablerMod/Scripts/main.lua)
- [Stable FName API](https://github.com/UE4SS-RE/RE-UE4SS/blob/v3.0.1/docs/lua-api/global-functions/fname.md)
- [Official FKey example](https://github.com/UE4SS-RE/RE-UE4SS/blob/v3.0.1/assets/Mods/ConsoleEnablerMod/Scripts/main.lua)
