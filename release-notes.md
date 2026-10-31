## 0.4.0 — shared Abel vehicle setup

- Estate, hatchback, liftback, luxury and van selections now use Abel's player-vehicle Blueprint with their selected body, animation, physics asset and wheel rig.
- Compatible models inherit the player controls, speedometer, radio and native camera setup. Vehicle boost remains available through the menu.
- Model parts are configured before vehicle physics is created. The original player template is restored immediately after spawning; existing map traffic and the original Abel car are unchanged.
- Missing wheel bones, unsupported scale/counts or construction that replaces the selected rig cancel the spawn instead of creating a mismatched vehicle.
- Player setup defaults on, including with older configurations. Set `PlayerVehicleSetup = false` for the previous traffic-vehicle fallback, which lacks the native speedometer/radio.

Close the game, run **Update.cmd**, then spawn a new car from the **Insert** menu. **F5** enters/exits. This changes new trainer spawns; existing traffic vehicles keep their original AI logic.
