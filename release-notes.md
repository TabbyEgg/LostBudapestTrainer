## 0.1.2

- F4 toggles god mode through Unreal's player damage permission.
- Noclip automatically protects against standard damage while flying and keeps a landing guard until grounded for 0.75 game seconds after flight ends.
- Vehicle diagnostics moved from F11 to F3 because F11 conflicts with the game's window toggle.
- Vehicle spawning and repair are not implemented yet. Stand beside an enterable car, press F3, and provide the vehicle diagnostic block from UE4SS.log to identify its actual blueprint and entry system.

Close the game and uninstall the older trainer before installing this version. Download the ZIP asset, extract it and run Install.cmd.

117 Lua checks pass. God mode still needs in-game verification; custom Blueprint health changes may bypass Unreal's standard damage permission.
