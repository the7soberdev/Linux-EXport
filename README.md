# Fisch Hub 2.1

Modular Luau hub for Fisch. Auto-fish, structural minigame solver, economy
automation, quest turn-ins, teleports, ESP, movement, staff-aware pausing.

Two delivery paths, same bundle:

- **Windows 10** - open `windows/` and run `Install.bat`. That folder is
  self-contained: installer, loader, bundle, source. See `windows/README.md`.
- **Linux** - `./fisch-hub.sh` installs, syncs, watches and launches. See
  "Autoload on Sober" below for what that runtime can and cannot do.

```
src/          15 modules, one responsibility each
dist/         bundled single-file build (93 KB, ~3350 lines)
windows/      ready-to-run Windows package (installer, loader, bundle, source)
autoload/     executor autoexec stub
build.py      bundler
fisch-hub.sh  Linux installer + watcher + launcher
tests/        headless stub harness
```

## Build and test

```sh
python3 build.py                       # src/*.lua -> dist/FischHub.lua
luau-compile --binary dist/FischHub.lua   # syntax gate
cat tests/stub.lua dist/FischHub.lua tests/driver.lua > /tmp/t.lua && luau /tmp/t.lua
```

The stub harness defines the slice of the Roblox API the hub touches —
`Instance`, `Enum`, `UDim2`, `task`, services, `Drawing` — so every module can
be loaded and stepped outside the engine. It has caught ordering and nil-index
bugs that would otherwise only appear in-game.

## Architecture

One `RunService.Heartbeat` connection drives every periodic task through a
scheduler with per-task accumulators. No module runs its own `while true do
task.wait()` loop, so a slow economy pass cannot delay the 50 ms fishing tick.

| Module | Responsibility |
|---|---|
| `env` | services, executor capability detection, logging |
| `util` | pattern matching, serialization, the heartbeat scheduler |
| `config` | defaults, persistence, named profiles |
| `scanner` | remotes, prompts, landmarks, best-rod ranking; 3 s refresh |
| `motion` | speed, jump, fly, noclip, oxygen, tween teleports |
| `minigame` | structural reel solver + fallbacks |
| `fishing` | cast/wait/reel state machine with adaptive patience |
| `economy` | sell, appraise, restock passes |
| `quests` | prompt-driven quest turn-in |
| `esp` | Drawing overlay, 1 Hz candidate rebuild |
| `anti` | anti-AFK, staff detection, rejoin, visual cleanup |
| `stealth` | variance, presence masking, pacing, teleport guard, panic |
| `learn` | `__namecall` recorder that captures the game's real remotes |
| `ui` | tabbed panel, sliders, notifications, status bar |
| `main` | boot, keybinds, lifecycle, public API |

## Features

**Fishing** — auto cast/reel, instant reel, best-rod auto-equip from a tier
list, adaptive cast patience derived from observed bite times.

**Minigame solver** — no hardcoded GUI paths. The widest visible object in the
active fishing Gui is the track; the children are sampled every frame and
sorted into movers and statics. The shape is classified into one of four
geometries — `linear` (static zone, sliding marker), `reverse` (static marker,
sliding zone), `fill` (growing bar), `radial` (orbiting marker) — and solved
per geometry. Marker velocity is estimated from consecutive samples and the
press is aimed at the predicted position after input latency, not the current
one. Unclassifiable shapes fall back to a duty-cycled hold.

**Economy** — three interaction mechanisms attempted in order: ProximityPrompt,
ClickDetector, then RemoteEvent. Vendor travel and return-to-origin around
every pass.

**Quests** — six prompt fires per turn-in covers talk → accept → hand in →
claim.

**Movement** — walk speed, jump power, camera-relative fly, noclip, infinite
oxygen across all three plausible storage locations (leaderstats, attributes,
character values). Teleports accept any landmark substring and tween instead
of snapping.

**ESP** — players, fish/items, NPCs, chests; boxes and distance labels; range
slider.

**Safety** — anti-AFK, staff detection by name marker or group rank, which
pauses the fisher instead of stopping it, and rejoin via the job id.

## Stealth

The stealth module attacks the two things that actually get accounts actioned:
statistics and reports.

- **Variance** — every interval is drawn from a triangular distribution, never
  a constant. Cast patience, reel lead, and press duration all wobble.
- **Per-session fingerprint** — four constants are drawn at boot
  (`castScale`, `reelLeadScale`, `slipBias`, `paceScale`), so two sessions of
  the same settings never produce the same timing profile.
- **Presence masking** — if another player is within range *and* has line of
  sight (raycast, both characters filtered), the fisher stops. A reel already
  in progress finishes; nothing new starts. It resumes when the view is clear.
- **Pacing** — rolling one-minute catch cap, plus work/break cycles with
  randomized session and break lengths.
- **Deliberate imperfection** — a configurable chance per catch that the hub
  simply does not press for long enough to lose it. A 100% success rate is a
  fingerprint; a plausible one is not.
- **Input noise** — the solver skips a random frame every so often and varies
  hold duration, so input frequency is not frame-perfect.
- **Teleport guard** — refuses to blink if anyone is near the destination.
- **Panic** — one key (`Delete`) sets every automation off, drops ESP, stops
  flight, and hides the UI. No confirmation, no menu.

Presets: *normal* and *paranoid* (250-stud proximity, 9 catches/min, 12%
imperfection, 40 min sessions with 11 min breaks).

## Getting to certainty: the Learn tab

Name patterns are guesses. The Learn tab replaces them with observation.

1. **Start capture.** A `__namecall` hook begins recording every
   `FireServer`/`InvokeServer` with its arguments.
2. **Tag, then act.** Press `Tag next as REEL`, then reel one fish by hand.
   Press `Tag next as CAST`, cast once. The recorded calls inherit those tags.
3. **Stop and apply.** The recorder ranks remotes by call rate — many calls per
   second is a reel remote, one call per action is a cast or sell remote — and
   writes the winners into the scanner as overrides. Overrides survive
   rescans and config reloads.

After that pass, the hub is not matching substrings any more. It is firing the
exact remote the game uses, with the exact signatures observed. `learn.report()`
prints the ranking so you can confirm before applying.

`__namecall` hooking is isolated to this module, pcall-guarded end to end, and
`Unhook` restores the original function. Executors that do not expose
`getrawmetatable` get a clean "learning disabled" message and the rest of the
hub runs unchanged.

## Console API

```lua
local hub = getgenv().FischHub
hub.probe()                       -- dump remotes, prompts, scheduler to console
hub.config.set("reelMode", "Remote")
hub.economy.sell()
hub.quests.claim()
hub.motion.tweenTo(landmark)
hub.anti.watch("someModName", "1234567")   -- name + optional group id
hub.stealth.engagePanic()                  -- everything off, UI hidden
hub.stealth.blocked()                      -- current gate state + reason
hub.ui.toggle()
```

## Autoload on Sober

### What Sober actually runs

Sober does not run the Windows client. It runs Roblox's **Android** build: a
`base.apk` plus `split_config.x86_64.apk`, unpacked under

```
~/.var/app/org.vinegarhq.Sober/data/sober/packages/x86_64/com.roblox.client/
```

Both files belong to you (uid 1000), and the engine itself is
`lib/x86_64/libroblox.so` inside the split — a normal shared object loaded into
a normal Linux process. That is why script hacks on Sober exist at all, and how
they arrive:

- **patched package** — a modified `base.apk` / split carrying an executor, dropped
  into the directory above;
- **injector** — a process that attaches to `libroblox.so` and hooks the Lua VM.

Neither is an autoexec folder. The Windows-style convention this launcher
syncs to (an `autoexec` directory an executor reads at startup) is a property of
Windows executors, and Sober has no equivalent. So on a stock Sober install the
hub is staged but nothing can start it. Run `./fisch-hub.sh` and it will say so
instead of pretending to watch an empty folder.

### Swapping a package without losing the original

`tools/sober-apk.sh` handles the patched-package route and nothing else — it
never downloads anything, and it always keeps a byte-exact backup first:

```sh
tools/sober-apk.sh status                  # sizes, hashes, whether Sober is running
tools/sober-apk.sh backup                  # snapshot to ~/.local/share/fisch-hub/apk-backup/
tools/sober-apk.sh install client.apk      # base or x86_64 split
tools/sober-apk.sh install client.apkm     # bundle of splits, extracted for you
tools/sober-apk.sh restore                 # put the snapshot back
```

It refuses arm64 packages (Sober needs x86_64), refuses to write while Sober
holds the files open, and writes through a temporary then renames, so a failed
copy cannot leave a half-written APK.

Once an executor is running inside the game, the hub is unchanged: paste
`~/.config/fisch-hub/loader.lua`, or its contents, into the executor's script
box. The loader finds the bundle next to itself or fetches it, then runs it.

### The launcher

The installer handles everything downstream of the injection point:

```sh
./fisch-hub.sh            # install, sync, watch, launch
./fisch-hub.sh --status   # what exists, what is detected, what is missing
./fisch-hub.sh --verify   # hash every installed copy against the source
./fisch-hub.sh --watch    # foreground watcher, if Sober is started another way
```

One script does all of it. On every run it copies the bundle to
`~/.config/fisch-hub/`, installs itself to `~/.local/bin/fisch-hub`, writes the
menu entry, syncs every autoexec directory it finds (native, Flatpak, Wine),
verifies each copy by SHA-256, then starts Sober.

**The watcher is why delivery is reliable.** Executor folders are often created
on first run, *after* the launcher starts. A background loop polls once a
second for the whole session and adopts any directory that appears, copying the
hub in before the first injection. A folder made at minute 12 of a session
still gets the hub within a second.

`install.sh` is a thin wrapper around `--install`, kept for muscle memory.

## Tuning surface

`src/config.lua` holds every default and every name pattern. Patterns are
lowercase substrings — a Fisch update that renames a remote usually needs one
word added there, not a code change.

`ROD_ORDER` in `src/scanner.lua` is the rod tier list. Add rods as they ship;
unknown rods rank 0 and still get equipped when nothing better exists.
