# MDF Reader (native GUI)

Native GUI reader built with **Zig + SDL2** (no web stack).

## Features

- Open `.mdf` by passing a path on the command line or drag-and-drop into the window
- Parses MDF container and validates CRC32 (via shared Zig core)
- If the file is a paged MDF (`DOCM`/`PAGE`/`IMG_`), renders embedded PNG page images
- Keyboard:
  - `Left/Right`: previous/next page
  - `Esc`: quit

## Build (macOS / Linux / Windows)

### Requirements

- Zig `0.13.x`
- SDL2 development libraries installed

macOS (Homebrew):

```bash
brew install sdl2
```

Ubuntu/Debian:

```bash
sudo apt-get install libsdl2-dev
```

Windows:

Install SDL2 development package and make sure your compiler/linker can find it.

### Build + run

From repo root:

```bash
cd apps/mdf-reader
zig build
./zig-out/bin/mdf-reader ../../examples/output/sample.mdf
```

## Notes on mobile

SDL2 supports iOS/Android, but packaging (Xcode/Gradle) is not included yet in this repo.
The code is written to be SDL2-compatible so those targets can be added next.

