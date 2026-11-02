## 0.4.4 — menu viewport, truck entry and steering fixes

- Fix the viewport-size read that stopped F2 before the menu could be submitted. Keep **arrows / Enter** navigation, visible **F3** selection and **F9** spawning.
- Let **F5** select tracked trainer cars up to 25 metres away, including trucks placed beyond the old 12-metre limit.
- Correct alternate-model A/D through the native runtime key mappings, then restore normal mappings on exit, pause, menu or disable. No input configuration is saved.
- Reject spawn positions above or intersecting another vehicle, using body footprints before and after engine adjustment.
- Combine duplicate pending actions and limit F9 attempts to one every 0.75 seconds, while keeping unlimited total spawning.
- Add a door-component lookup fallback and preserve interaction queries on hidden panels.

Fully quit the game and run **Update.cmd**, then restart and load your usual save. **F2** opens the menu; **F5** enters/exits a nearby trainer car.
