## 0.3.1 — menu binding, vehicle controls and protection fixes

- Fixed **Insert**: UE4SS 3.0.1 calls the key `INS`, so 0.3.0 never registered it. Preserved `INSERT` configurations now work too.
- Held hotkeys no longer repeatedly toggle protection or consume multiple vehicle slots until released.
- Added **Vehicle boost** in the menu: Off, 60, 100, 150, 200 or 300 km/h targets. Hold Shift + W to add forward thrust; releasing Shift or braking stops it. Starts off and preserves native steering/camera.
- Default vehicle cap increased to **10**, configurable with `MaxVehicles`. Actual spawn positions are checked and blocked placements try alternatives ahead. Failed placements are removed and never counted.
- Abel's car now retains its own Blueprint input, ticking and camera. The trainer no longer imposes generic throttle/steering or a separate fixed camera on it. Traffic radio is not implemented.
- Traffic fallback camera is attached to the vehicle rather than updated by an asynchronous timer. Entry and menu close release the parking brake correctly.
- God/flight protection zeroes native damage before TakeDamage for the protected player, rather than healing standard damage afterward. It also preserves living Abel's custom Health and caps dangerous falling velocity to 3 m/s; landing protection remains until grounded. It does not revive scripted deaths or establish protection against all instant-kill scripts.
- F3 reports player Health/damage permission and vehicle radio/camera/input function names. It no longer uses parameter enumeration unavailable on this stable loader's UFunction wrapper.

Close the game and run **Update.cmd**. Press **Insert** for the menu; enable **God mode** there or with **F4**.
