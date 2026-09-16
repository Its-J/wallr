# CLI Reference

`wallr` is controlled via subcommands and ergonomic flags.

```text
wallr set <path> [-e <effect>] [-d <duration>] [-o <origin>] [-a <angle>] [-m <output>] [-t <theme>] [--mode <mode>]
wallr daemon [--max-fps <fps>]
wallr preview <path> [-w] [--animation <package>] [effect flags]
wallr watch <directory>
wallr reload
wallr quit
wallr doctor
wallr validate <animation.yaml>
wallr new <name> [--shader]
wallr install <username/repo>
wallr search <query>
wallr cache <info|clear>
wallr config <get|set|path>
wallr monitor <list|current>
wallr ipc <pause|resume|reload|status|info|stop|seek|blank|restore>
```

---

## Wallpaper Commands

### `wallr set <path>` (alias: `wallr img`)
Sets the wallpaper for your desktop. Automatically launches the background daemon if not already running.

```bash
# Basic wallpaper set (uses config default transition or 700ms quintic crossfade)
wallr set ~/Pictures/wallpaper.png

# Transition effects with short flags
wallr set ~/Pictures/wallpaper.png -e grow -o center -d 850ms
wallr set ~/Pictures/wallpaper.png -e wipe -a 45 -d 800ms
wallr set ~/Pictures/wallpaper.png -e wave -d 900ms

# Target specific output and scaling mode
wallr set ~/Pictures/wallpaper.png -m DP-1 --mode fit

# Force dynamic theming (Matugen, Wallust, Pywal) or disable
wallr set ~/Pictures/wallpaper.png -t matugen
wallr set ~/Pictures/wallpaper.png --no-theme
```

#### Flags
| Flag | Long | Description |
|---|---|---|
| `-e` | `--effect <NAME>` | Transition: `fade`, `wipe`, `slide`, `grow`, `outer`, `wave`, `blur`, `zoom`, `pixelate`, `ripple`, `dissolve`, `any`, `random` |
| `-d` | `--duration <TIME>` | Wall-clock duration (`700ms`, `1s`, `1.2s`) |
| `-o` | `--origin <PRESET\|X,Y>` | Origin: `top_left`, `top`, `top_right`, `left`, `center`, `right`, `bottom_left`, `bottom`, `bottom_right`, or normalized `x,y` |
| `-a` | `--angle <DEG>` | Wipe/wave travel angle in degrees (`0` = right, `90` = up) |
| `-m` | `--monitor <OUTPUT>` | Target output (e.g. `DP-1`, `HDMI-A-1`) |
| `-t` | `--theme <PROVIDER>` | One-shot theme generator: `matugen`, `wallust`, `pywal`, `none` |
| | `--mode <MODE>` | Scaling mode: `fill`, `fit`, `stretch`, `center`, `tile` (default: `fill`) |
| | `--animation <PKG>` | Preset animation package name or path |
| | `--easing <CURVE>` | Easing curve: `linear`, `ease_in`, `ease_out`, `ease_in_out`, `emphatic`, `spring` |
| | `--softness <VAL>` | Edge softness / feather for wipe and dissolve |

---

## Daemon & Watcher

### `wallr daemon`
Starts the persistent Wayland layer-shell daemon.
```bash
wallr daemon
wallr daemon --max-fps 120
```

### `wallr watch <directory>`
Monitors a directory for new or modified images and rotates wallpapers automatically.
```bash
wallr watch ~/Pictures/Wallpapers
```

### `wallr reload`
Re-reads configuration from disk and live-applies settings (`max_fps`, `hw_decode`, etc.) without restarting the daemon.

### `wallr quit`
Gracefully shuts down the running daemon and removes the Unix socket.

---

## Utilities & Maintenance

### `wallr doctor`
Runs environment checks (Wayland socket, layer-shell support, theme binary availability, and loop risks).

### `wallr validate <file.yaml>`
Lints animation package structure, duration formatting, and transpiles custom shader effects.

### `wallr cache <info|clear>`
Displays decoded frame cache statistics or purges cached frames and theme palettes.

### `wallr monitor <list|current>`
Queries connected Wayland outputs and current display dimensions.

### `wallr preview <path> [-w]`
Opens a standalone debug window rendering the wallpaper and animation without changing desktop state. Add `-w` to hot-reload on file edits.

---

## Animation Package Registry

```bash
# Install package from GitHub
wallr install username/repository

# Search installed packages
wallr search liquid

# Create a new local package template
wallr new my-transition --shader
```
