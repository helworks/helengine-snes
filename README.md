# Helengine Super Nintendo Host

Super Nintendo platform host for Helengine. Current milestone: a diagnostic
ROM that boots to a centred red square on a black background, built with a
pinned llvm-mos-65816 C++ toolchain inside Docker.

Design: `docs/superpowers/specs/2026-09-17-snes-red-square-boot-design.md`.
Background reading: `docs/SuperNintendoDevelopment.md`, `docs/super-nintendo-cpp.md`.

## One-time setup

Requires Docker Desktop, PowerShell and Python 3 on `PATH` (the build script
validates the ROM on the host and the tool tests run on the host).

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-toolchain.ps1
```

Downloads the toolchain package pinned in `dependencies.json` into `.deps/`,
verifies its SHA-256, builds the `helengine-snes-toolchain` image and records
the image id and compiler version back into `dependencies.json`.

## Build

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1
```

Runs `make` in the container and writes:

- `helengine_snes.sfc`: headerless 32 KiB LoROM image, title `HELENGINE SNES`, checksum patched
- `build/helengine_snes.elf`, `build/helengine_snes.map`
- `build/build-record.json` with the ROM SHA-256 and the pins used

`make` finalizes the title and checksum with `tools/finalize_rom.py` and
refuses to finish unless `tools/validate_rom.py` passes.

`scripts/build.ps1 -Clean` runs `make clean` first; two clean builds must give
the same ROM SHA-256.

## Check in an emulator

Headless acceptance through MesenCE's test-runner mode:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_in_emulator.ps1
```

Exit code 0 means the centre pixel is red, the corners are black and the
VBlank frame counter advanced between frames 30 and 60. The script reads the
emulator's frame buffer through Lua; nothing captures the desktop.

MesenCE shows a first-run wizard when it has no `settings.json`, and the
wizard blocks test-runner mode. A `settings.json` containing `{}` next to
`Mesen.exe` puts it in portable mode and skips the wizard.

For a look with your own eyes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\launch_in_emulator.ps1 -ArtifactPath .\helengine_snes.sfc -Visible
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\launch_in_emulator.ps1 -ArtifactPath .\helengine_snes.sfc -Visible -EmulatorPath C:\dev\helworks\emus\ares-v148-windows-x64\ares-v148\ares.exe
```

## Host tool tests

```powershell
python -m unittest discover -s tools/tests -t . -v
```

## Layout

- `src/main.cpp`: entry point
- `src/platform/snes/`: `SuperNintendoBootHost` (boot sequence), `SuperNintendoVideo` (PPU, DMA, NMI), `SuperNintendoRedSquareScene` (tile and tilemap data)
- `tools/`: `finalize_rom.py`, `validate_rom.py`, `mesen/red_square_check.lua`
- `scripts/`: setup, build, check and launch

## Toolchain notes

- The SDK's base `snes` platform is LoROM with one 32 KiB near-code bank.
  `snes-far` and `snes-hirom` exist for larger ROMs.
- `mos-snes-clang++` compiles C++20 without exceptions or RTTI.
- The SDK's weak `nmi` symbol is overridden by a C++ `extern "C"` handler
  with the `interrupt` attribute.
