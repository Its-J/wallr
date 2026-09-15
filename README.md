<div align="center">

# Wallr

GPU-accelerated wallpaper engine for Wayland, rendered natively with `wgpu` on `wlr-layer-shell`.

<a href="https://github.com/programmersd21/wallr">
  <img src="https://raw.githubusercontent.com/programmersd21/wallr/main/assets/demo.gif" alt="Wallr demo" width="800">
</a>

<p align="center">
  <a href="https://github.com/programmersd21/wallr/stargazers"><img src="https://img.shields.io/github/stars/programmersd21/wallr?style=for-the-badge&logo=github&logoColor=f9e2af&labelColor=11111b&color=f9e2af" alt="GitHub stars"></a>
  <a href="https://github.com/programmersd21/wallr/releases/latest"><img src="https://img.shields.io/github/v/release/programmersd21/wallr?style=for-the-badge&logo=github&logoColor=a6e3a1&labelColor=11111b&color=a6e3a1" alt="Latest release"></a>
  <a href="https://aur.archlinux.org/packages/wallr-bin"><img src="https://img.shields.io/aur/version/wallr-bin?style=for-the-badge&logo=archlinux&logoColor=cba6f7&labelColor=11111b&color=cba6f7" alt="AUR version"></a>
  <a href="https://aur.archlinux.org/packages/wallr-bin"><img src="https://img.shields.io/aur/votes/wallr-bin?style=for-the-badge&logo=archlinux&logoColor=f5c2e7&labelColor=11111b&color=f5c2e7" alt="AUR votes"></a>
  <a href="https://crates.io/crates/wallr"><img src="https://img.shields.io/crates/v/wallr?style=for-the-badge&logo=rust&logoColor=fab387&labelColor=11111b&color=fab387" alt="Crates.io version"></a>
  <a href="https://www.rust-lang.org"><img src="https://img.shields.io/badge/MSRV-1.85-94e2d5?style=for-the-badge&logo=rust&logoColor=94e2d5&labelColor=11111b&color=94e2d5" alt="Minimum supported Rust version"></a>
</p>

</div>

Wallr renders its own background surface on `wlr-layer-shell` compositors. It does not shell out to `hyprpaper`, `swaybg`, or `swww`.

## Features

- Static, GIF, and video wallpapers (MP4, WebM, MKV) with hardware-accelerated decode
- 11 transitions — fade, blur, wipe, slide, zoom, pixelate, ripple, dissolve, wave, grow, outer
- Per-monitor wallpapers and scaling modes
- Background daemon over a Unix socket, with directory watching for auto-apply
- Optional post-apply theming via Matugen, Wallust, or Pywal
- YAML animation packages with an install/search registry
- Near-zero idle overhead: static wallpapers render once and sleep; video and GIFs pace to frame boundaries

## Screenshots

<p align="center">
  <img src="https://raw.githubusercontent.com/programmersd21/wallr/main/assets/rice_1.png" alt="Terminal rice with audio visualizer and fetch widget over a Catppuccin Mocha sunset" width="49%">
  &nbsp;
  <img src="https://raw.githubusercontent.com/programmersd21/wallr/main/assets/rice_2.png" alt="System monitor and lazygit over a Catppuccin Mocha sunset" width="49%">
  <br>
  <em>Catppuccin Mocha sunset — audio visualizer and fetch widget (left), system monitor and git workflow (right)</em>
</p>

## Install

```bash
cargo install wallr
```

```bash
yay -S wallr-bin
```

```bash
nix run github:programmersd21/wallr
```

## Usage

```bash
wallr set wallpaper.jpg
wallr set wallpaper.jpg --effect grow --origin bottom_right --duration 1.2s
wallr set video.mp4 --effect wave --duration 1s
wallr watch ~/Pictures
```

`wallr set` starts the daemon automatically if it isn't already running. Full flag reference: [`docs/cli-reference.md`](docs/cli-reference.md).

## Configuration

`~/.config/wallr/config.yaml`:

```yaml
wallpaper:
  default: "~/Pictures/Wallpapers/default.png"
  mode: "fill"

animation:
  use: "smooth/crossfade"
  duration: "2000ms"

theme:
  provider: "matugen"

reload:
  - "waybar"
  - "dunst"
```

Full schema: [`docs/config-reference.md`](docs/config-reference.md).

## Requirements

| | |
|---|---|
| Compositor | Hyprland, Sway, niri (layer rule required), or KDE Plasma 6 — any `wlr-layer-shell` implementation. GNOME/Mutter is unsupported. |
| Rust | stable, for building from source |
| FFmpeg | required only when building from source, for video wallpapers. Prebuilt release binaries statically link FFmpeg. |

## Building from source

```bash
# Arch
sudo pacman -S rust wayland wayland-protocols pkg-config ffmpeg

# Fedora
sudo dnf install rust cargo wayland-devel wayland-protocols-devel pkg-config ffmpeg-devel

# Ubuntu/Debian
sudo apt install rustc cargo libwayland-dev wayland-protocols pkg-config libavcodec-dev libavformat-dev libavutil-dev libswscale-dev
```

```bash
git clone https://github.com/programmersd21/wallr.git
cd wallr
cargo install --path wallr
```

## Architecture

The `wallr` CLI talks to `wallr daemon` over a Unix socket. The daemon owns the layer-shell surface, the `wgpu` renderer, and the animation engine. Wallpaper changes render as GPU transitions from the previous image; GIFs continue playing after the transition ends, and video is decoded by FFmpeg with hardware acceleration where available.

Details: [`docs/architecture.md`](docs/architecture.md).

## Troubleshooting

**`error while loading shared libraries: libavutil.so.58`** — the installed binary was built against an older FFmpeg ABI. Reinstall the latest release (statically linked), or rebuild from source:

```bash
cargo install --path wallr --force
```

**Wallpaper intercepts input** — it shouldn't; the surface runs on `Layer::Background` with `KeyboardInteractivity::None` and an empty input region. If it happens: confirm your compositor is supported, check compositor logs for layer-shell errors, restart the daemon (`pkill wallr && wallr daemon`), and on niri add a layer-shell rule permitting Wallr on the background layer.

## Documentation

[Changelog](CHANGELOG.md) · [CLI reference](docs/cli-reference.md) · [Config reference](docs/config-reference.md) · [Animation authoring](docs/animation-authoring.md) · [Architecture](docs/architecture.md) · [Matugen integration](docs/matugen-integration.md) · [Video wallpapers](docs/video-wallpaper.md)

Last wallpaper per output is stored at `~/.cache/wallr/last_wallpaper/<OUTPUT>` — see [CLI reference](docs/cli-reference.md) and [Architecture](docs/architecture.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
