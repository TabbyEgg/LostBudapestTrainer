# Lua behavior checks

Install `requirements.txt` into a Python virtual environment, then run
`python tests/run.py` from the project directory. Lupa executes the Lua 5.4
production modules; no replacement copy of trainer logic is used.

The checks run the controller against fault-injecting game-boundary doubles,
then run the shipped `main.lua` and `adapter.lua` together with typed Unreal and
UE4SS doubles. They verify camera-relative normalized movement, pause handling,
timing limits, speed changes, original-state restoration, partial failures,
ownership and possession changes, emergency-return ordering, bounded cleanup
retries and missing engine inputs. Integration cases reject Unreal access outside
the queued game-thread callback, validate FKey/FName/transform argument shapes,
and ensure async updates coalesce and do not reactivate after a player restart.
Emergency-return cases distinguish a genuinely refused teleport from Unreal's
false/no-movement result when already at the entry point. A failed return retains
noclip until a successful retry; destroyed-component cleanup checks the old pawn
identity before touching collision on any still-valid object.

This establishes Lua behavior under those modeled contracts. It does not load
UE4SS DLLs, run the Windows executable or establish real in-game compatibility.
`results.json` records the tested production-source hashes and explicit runtime
limits; `results.txt` records individual case outcomes.

Installer fixtures run the actual PowerShell scripts against isolated directories
with synthetic loader payloads and a hardlink to the approved EXE (never executed):

```text
python tests/installer-checks.py --powershell /path/to/pwsh --game-exe /path/to/EltuntBP-Win64-Shipping.exe
```

The temporary root must be on the EXE's filesystem to allow hardlinks. Use
`--temp-root` for another writable directory on that filesystem. Existing
validation evidence was produced under PowerShell 7 on Linux; Windows folder
selection and Windows PowerShell 5.1 still require a platform check.

Menu cases cover missing HUD events, rendering errors, balanced input-lock
restoration, mouse/keyboard edges, live status and read-only error notifications.
Native spawn fixtures reject unknown classes, identify only a newly created
actor, and verify helper/class defaults/collision restoration on every modeled
failure. The replacement spawn path passes only flat vectors/rotators into
Unreal, never nested FTransform tables. These are simulated boundary tests, not
a live UE4SS/game validation.

0.3.1 regressions use the stable loader's real `INS` key spelling and test the
preserved `INSERT` alias, held-key deduplication, obstructed spawn positions,
Abel native input/camera without manual control writes, attached traffic camera,
menu braking cleanup, custom Health preservation and vertical fall limits.

Native damage hook cases verify player-only pre-damage suppression for lethal
ApplyDamage and ApplyPointDamage while other actors and unprotected damage
remain unchanged. These checks do not execute the game's Blueprint death logic.

Boost cases cover its off default, bounded selection, normal-car support,
Shift/W/brake gating, forward-only acceleration, target cutoff and failure
cleanup without changing native steering or camera.

Shared player-vehicle cases verify source mesh/animation/physics/wheel matching,
pre-construction application, exact default restoration, spawned-instance
independence, invalid rig refusal, animation/runtime wheel mismatch cleanup,
source-instance fallback and explicit legacy routing. No array is resized and
no source traffic actor/default is modified. Native template copy timing remains
a modeled Unreal boundary; the fixture does not execute the Windows game.

0.4.1 cases exercise reserved F2/F3/Home migration from preserved configs, the
actual main-to-HUD adapter path and balanced menu locks, 100 spawns with a legacy
limit of one, converted-car-only keyboard steering in queued updates,
positive source scale installed before construction without late resizing, and
extra-door visibility/hidden/collision maintenance scoped to converted components.

0.4.2 cold-start cases permit only the original two damage hooks and player
restart hook, and reject attempts to add engine-wide component/steering setter
hooks. Before a converted car exists the async scheduler does not touch Unreal
or enqueue maintenance. Owned door maintenance avoids redundant writes and
forgets reparented/destroyed components. Steering checks cover normal F entry,
keyboard release without continued analog-input overrides, original/NPC vehicle
exclusion, pause/menu gating and isolated component failures.

Installer recovery cases verify that re-enabling a disabled trainer entry must
restore the previously owned mod-list bytes exactly. They also verify the
original backup chain and reject unrelated mod-list edits without writes.

0.4.3 exercises keyboard menu submission through the native HUD queue without
Blueprint draw callbacks or a live Canvas, named scalar and flat-struct output
parameters, exact AddDebugText flags, keyed cleanup, no startup polling, input
edges and balanced locks on failed submission. Spawn checks exercise destination
teleport adjustment, player separation, rejection cleanup and staged opaque
errors. Cosmetic door API failure cannot invalidate a matched native vehicle.
