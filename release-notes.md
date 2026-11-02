## 0.4.5 — invisible menu font fix

- Supply a real font object to the native HUD text call. The bundled SDK leaves a nil font argument unconsumed, causing the following font scale to become zero.
- Reuse an available engine font, with standard font-asset fallbacks.
- Log the requested and native text scale where the HUD queue can be inspected, and reject a verified zero-scale submission before locking controls.

Fully quit the game and run **Update.cmd**, then load the level and press **F2** once. **Arrows** select/adjust and **Enter** activates. Other trainer features retain their v0.4.4 behavior.
