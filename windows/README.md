# Fisch Hub - Windows package

Everything needed to put the hub on a Windows 10 machine. No admin rights, no
downloads, no background service.

## What it does

Two files, copied into every executor autoexec folder it can find:

```
<executor>\autoexec\FischHub.lua        the loader, runs on every injection
<executor>\autoexec\fischhub\hub.lua    the hub bundle, 93 KB
```

Plus a copy of both in `%LOCALAPPDATA%\FischHub` so nothing depends on the
package folder staying put.

When you inject into Roblox, the loader runs, finds the bundle, and starts it.
`RightControl` opens the panel, `Delete` is the panic key.

## What it does not do

It does not install an executor, download anything, or touch Roblox itself.
It only writes into folders an executor already created and watches.

## Quick start

1. Copy this folder anywhere on the Windows machine (Desktop is fine).
2. Run `Install.bat` (or right-click `fisch-hub.ps1` -> Run with PowerShell).
3. Start your executor, inject into Roblox.

If step 2 says no executor folder was found, start the executor once, close
it, and run `fisch-hub.ps1 -Sync` again. Executors create their autoexec folder
on first launch, which is why the installer can find nothing before that.

If your executor keeps its autoexec somewhere unusual:

```powershell
.\fisch-hub.ps1 -Sync -SearchPath "C:\path\to\the\folder"
```

## Commands

| Command | What it does |
| --- | --- |
| `.\fisch-hub.ps1` | install, sync, print a summary |
| `.\fisch-hub.ps1 -Status` | bundle hash, install dir, folders found |
| `.\fisch-hub.ps1 -Verify` | SHA-256 of every installed file vs the source |
| `.\fisch-hub.ps1 -Sync` | copy again into every folder found now |
| `.\fisch-hub.ps1 -Watch` | stay open and adopt executor folders as they appear |
| `.\fisch-hub.ps1 -Uninstall` | remove only the files this script wrote |
| `.\fisch-hub.ps1 -Launch` | start the newest `RobloxPlayerBeta.exe` it finds |
| `.\fisch-hub.ps1 -SearchPath "D:\x"` | extra roots to scan, repeatable |

Flags combine: `.\fisch-hub.ps1 -Sync -Launch`.

## How folders are found

Every run scans these roots three levels deep for a folder named `autoexec`,
`autoload`, `auto_exec` or `autoexecs`:

```
%LOCALAPPDATA%
%APPDATA%
%USERPROFILE%\Documents
%USERPROFILE%\Desktop
%USERPROFILE%\Downloads
```

It skips `node_modules`, `.git`, caches, `%APPDATA%` subtrees and Windows store
folders, so the scan stays fast. Nothing is installed unless a matching folder
already exists - it never creates an autoexec folder for an executor that is
not there.

## Safety

Every write is recorded in `%LOCALAPPDATA%\FischHub\manifest.json` with its
SHA-256. Consequences:

- `-Verify` tells you if any installed file changed or disappeared.
- `-Uninstall` deletes only files whose hash still matches what the installer
  wrote. Anything you edited is kept and reported.
- Files are only rewritten when the hash differs, so `-Watch` does not churn
  the disk or race a running executor.

## Rebuilding the bundle

The full source is in this folder. With Python 3 installed:

```
python build.py
```

That rewrites `dist\FischHub.lua`. Copy it over `FischHub.lua` in this folder,
then run `-Sync` to push the new build into the executor folders.

## Troubleshooting

**"running scripts is disabled on this system"**
`Install.bat` already passes `-ExecutionPolicy Bypass`. If you launch the ps1
by hand, use:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\fisch-hub.ps1
```

**No executor folders found**
Start the executor once so it creates its folder, then `-Sync`. Or find the
folder yourself and pass `-SearchPath`. `-Watch` is for exactly this: start it
before the executor, and it adopts the folder the moment it appears.

**Hub loads but does nothing**
The loader prints `[FischHub] autoloaded from <path>` in the executor console
when it works. If you see `loader found no hub source`, run `-Verify`: the
autoexec copy is missing or was edited.

**Panel does not open**
The GUI binds to `RightControl`. Some executors swallow that key; change it in
`src/config.lua` (`toggleKey`) and rebuild.
