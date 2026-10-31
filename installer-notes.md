# Installer behavior

Run `Install.cmd` with the game closed. Select either the game root or
`Eltunt_Budapest3\Binaries\Win64`. PowerShell invocation is also supported:

```powershell
.\install.ps1 -GameDirectory 'D:\SteamLibrary\steamapps\common\Lost Budapest Demo'
.\uninstall.ps1 -GameDirectory 'D:\SteamLibrary\steamapps\common\Lost Budapest Demo'
```

The installer validates the supplied EXE's SHA-256, every runtime file against
`payload-manifest.json`, and all destination paths before changing the game
directory. The supported executable hash is
`2e5f4d5b66da873a488287b580c2ba3dd91ed892727cfd71ecbd610d6a08f284`.
It refuses a running game, a different build, linked destination paths, and a
different existing `dwmapi.dll` or `UE4SS.dll`. A nonempty custom
`[Overrides] ModsFolderPath` is rejected before installation because this package
uses the standard local `Mods` folder. Identical existing loader files
are reused and are not owned or removed by this installer. No administrator
prompt or system-wide PowerShell policy change is needed.

Other mod entries remain in `Mods/mods.txt`; only `LostBudapestNoclip : 1` is
added or enabled. Existing UE4SS settings are retained except for the required
engine override (4.27) and `EnableHotReloadSystem = 0`. A new configuration has
the UE4SS debug consoles disabled. Original bytes of modified files are backed
up under a uniquely named `LostBudapestNoclip.backup-*` directory. The installed
hashes and original paths are recorded in `LostBudapestNoclip.install.json`.

Installation failures attempt to restore completed writes. To install a later
version, uninstall the current package first so the original backup chain stays
unambiguous. `Uninstall.cmd` restores or removes only files whose current bytes
still match this installation's recorded hashes. User edits, unknown files and
other mods are retained. When another mod directory is present, newly supplied
shared loader DLLs and a new UE4SS configuration are also retained for that mod.
When a file was edited after installation, uninstall
returns code 2 and keeps its receipt/backups for review; code 0 means completed,
and code 1 means an error. Keep the receipt and backup directory until removal.

The installer does not include or modify the game EXE or save files. Live Windows
folder-picker, Windows PowerShell 5.1 and in-game behavior need user-side testing.

Validation: 34 end-to-end fixture assertions pass under official PowerShell
7.6.9 on Linux, including fresh installation/removal, exact-byte restoration,
other-mod preservation, payload/build/collision/path rejection, edited-file
retention, partial-write rollback and interrupted-removal recovery. The fixture
uses the supplied EXE for its real SHA-256 check, with synthetic loader bytes; it
does not execute the game or loader. PowerShell syntax parsing also passes.

## Updating

Update.cmd runs update.ps1, downloads the latest release from the official repo,
verifies GitHub asset SHA256/size and bounded archive paths, then invokes
install.ps1 -Update. The installer migrates receipt ownership without replacing
original backups. Edited config.lua is preserved; other edited implementation
files stop the upgrade before writes. Uninstall after upgrading restores the
pre-first-install backup. Failed upgrade writes roll back to the prior version.
