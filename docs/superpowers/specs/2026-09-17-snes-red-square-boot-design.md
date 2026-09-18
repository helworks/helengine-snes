# SNES Handler: Red Square Boot ROM Design

Date: 2026-09-17
Status: approved

## Goal

Stand up the helengine SNES handler repository with a reproducible build that
produces a headerless LoROM `.sfc`, boots in an emulator, and shows a red
square on a black background. This is the first milestone of the SNES 2D
backend. It proves the toolchain, the cartridge header and vectors, CGRAM,
VRAM, DMA, Mode 1 backgrounds and the VBlank NMI, which are the foundation
every later 2D feature builds on.

Out of scope for this milestone: the C# builder assembly, editor registration
through `platform-plugin.json`, the generated core, sprites, input, audio and
FastROM.

## Decisions

| Decision | Choice | Reason |
|---|---|---|
| Compiler | llvm-mos-65816 preview toolchain (clang + lld + SNES SDK) | Only 65816 toolchain that compiles C++, which helengine's C# to C++ codegen requires. PVSnesLib's 816-tcc is C only. |
| Language | C++20, no exceptions, no RTTI, freestanding | Same C++20 level as the other handlers (they use `-std=gnu++20`; this handler uses strict `-std=c++20` until the generated core shows it needs GNU extensions) and the generated core's needs while staying inside what the 65816 backend supports. |
| Host build | Docker on a digest-pinned Ubuntu 24.04 image with the Linux x86-64 `.deb` package | Same pattern as the DS and N64 handlers. The Windows toolchain zip is untested upstream. |
| SDK platform | `snes` (LoROM, one 32 KiB bank, near-only code) | Simplest mapping. `snes-far` and `snes-hirom` remain available when the generated core needs more ROM. |
| Cartridge | LoROM, SlowROM, no enhancement chip, no SRAM | Smallest test matrix, as recommended in `docs/SuperNintendoDevelopment.md`. |
| Video | Mode 1, BG1 only, 256x224 | Recommended general 2D baseline. |
| The square | BG1 tilemap of one solid 4bpp tile | Proves the background path a 2D engine lives on. Backdrop colour alone proves too little; an OAM sprite skips the tilemap path. |
| Debug emulator | MesenCE 2.2.1 | Open source, SNES debugger, Lua scripting. |
| Cross-check emulator | ares v148 | Independent implementation. |
| Scope | Standalone ROM, no editor integration | Same shape as the N64 diagnostic mode. |

## Toolchain pinning

The upstream project publishes the Linux x86-64 toolchain as a Debian package
in its apt repository. The tarball links on its product page are dead, so the
`.deb` is the pinned artifact.

`dependencies.json` records:

- the Ubuntu 24.04 base image digest,
- the package URL
  `https://apt.indri.studio/pool/main/l/llvm-mos-65816/llvm-mos-65816_0.0.0+git20260914.f9711be_amd64.deb`,
- the package SHA-256
  `6485bf206b2db2f46c234e05204d0b51f2fa1949d5575d2022af3a62db4e84ac`,
- the Docker toolchain image id and the compiler version string, filled in by
  `scripts/setup-toolchain.ps1` after it builds the image.

`scripts/setup-toolchain.ps1` downloads the package into `.deps/` (gitignored),
verifies the SHA-256, fails on mismatch, builds the `helengine-snes-toolchain`
Docker image and writes the image id and compiler version back into
`dependencies.json`.

The Dockerfile installs the package with `apt-get install` from the local file,
which places the toolchain under `/usr/lib/llvm-mos-65816` and puts the
`mos-snes-clang` and `mos-clang` drivers on `PATH`. Nothing from the toolchain
is committed.

## Build

`Makefile` compiles every `.cpp` under `src/` and `src/platform/snes/` with
the package's C++ driver:

```
mos-snes-clang++ -std=c++20 -fno-exceptions -fno-rtti -Os -Wall -Wextra -Isrc
```

A throwaway spike on 2026-09-17 confirmed this driver compiles a C++20 file
with namespaces, a class, a member template and the SDK headers into a
32 KiB LoROM image that boots in MesenCE and shows the expected backdrop
colour, so C++ on this SDK is verified rather than assumed.

and links to `build/helengine_snes.elf`, then lets the SDK emit the raw
`.sfc` image together with `build/helengine_snes.map`. The SDK's header
carries the title `LLVM-MOS SNES` and leaves the checksum fields at
`0x0000`/`0xFFFF`. `tools/finalize_rom.py` rewrites the title to
`HELENGINE SNES`, computes the real checksum and complement, and writes
`helengine_snes.sfc` at the repository root. The ROM is headerless: no
512-byte copier prefix.

`scripts/build.ps1` runs `make` in the `helengine-snes-toolchain` container
with the repository mounted at `/workspace`,
fails if the ROM, ELF or map is missing or empty, runs `tools/validate_rom.py`,
and writes `build/build-record.json` with the ROM SHA-256, sizes, Docker image
ids and the dependency pins.

Build outputs live in `build/` and the ROM at the repository root, both
gitignored, matching the N64 handler.

## ROM behaviour

The SDK crt0 already switches the CPU to native mode, sets the stack, clears
`.bss`, copies `.data`, force-blanks the PPU and calls `main`.

`main` constructs `helengine::snes::SuperNintendoBootHost` and calls `Run`,
which does the following in order:

1. Reset every PPU control register while force-blanked
   (`snes_ppu_reset_blank`).
2. Set `BGMODE` to Mode 1 with 8x8 tiles, point BG1's tilemap and character
   base at fixed VRAM word addresses, and enable BG1 alone on the main screen.
3. Write CGRAM: entry 0 is black (the backdrop), entry 1 is red
   `SNES_RGB(31, 0, 0)`.
4. DMA two 4bpp tiles (64 bytes) to the BG1 character base: tile 0 has every
   pixel at palette index 0, which is transparent so the backdrop shows
   through, and tile 1 has every pixel at palette index 1, solid red.
5. DMA a 32x32 tilemap (2 KiB) to the BG1 tilemap base. Every entry uses
   palette 0 and tile 0, except the 8x8 entry block covering rows 10 to 17 and
   columns 12 to 19, which uses tile 1. That is a 64x64 pixel red square
   centred on the 256x224 screen.
6. Enable the VBlank NMI in `NMITIMEN`. The NMI handler is a C++ function with
   the `interrupt` attribute named `nmi`, overriding the SDK's weak default. It
   reads `RDNMI` to acknowledge and increments a volatile frame counter.
7. Set `INIDISP` to screen on, full brightness.
8. Loop forever waiting for the frame counter to change.

VRAM layout for this milestone, in word addresses:

| Word address | Content |
|---|---|
| `0x0000` | BG1 tilemap, 32x32 entries, 2 KiB |
| `0x1000` | BG1 character data: tile 0 transparent, tile 1 solid red |

## Source layout

Namespace `helengine::snes`, class prefix `SuperNintendo`, one class per file,
matching the `Nintendo64` and `NintendoDs` handlers.

- `src/main.cpp`: constructs the boot host and returns its exit code.
- `src/platform/snes/SuperNintendoBootHost.hpp/.cpp`: owns the boot sequence
  above and the frame loop.
- `src/platform/snes/SuperNintendoVideo.hpp/.cpp`: PPU reset, mode and layer
  setup, palette writes, VRAM DMA through channel 0, NMI enable, and
  `WaitForVBlank` on the frame counter. The `nmi` handler lives here. This
  class is the seed of the future 2D render manager.
- `src/platform/snes/SuperNintendoRedSquareScene.hpp/.cpp`: the two tiles and
  the tilemap builder for the square. Kept separate so it can be deleted when
  real content arrives.
- `Makefile`, `Dockerfile`, `dependencies.json`, `.gitignore`, `README.md`,
  `THIRD_PARTY_NOTICES.md`.
- `scripts/setup-toolchain.ps1`, `scripts/build.ps1`,
  `scripts/launch_in_emulator.ps1`, `scripts/check_in_emulator.ps1`.
- `tools/finalize_rom.py` and `tools/validate_rom.py`, with their tests in
  `tools/tests/`.
- `tools/mesen/red_square_check.lua` for the automated frame check.

`THIRD_PARTY_NOTICES.md` carries the Apache-2.0 with LLVM exceptions notice for
the SDK crt0 and runtime linked into the ROM. Emulators and the compiler are
build tools and are not redistributed.

## Emulators

MesenCE 2.2.1 (Windows zip from the nesdev-org/MesenCE 2.2.1 release) is
unpacked to `C:\dev\helworks\emus\Mesen_2.2.1_Windows\`, and ares v148
(`ares-windows-x64.zip`) to `C:\dev\helworks\emus\ares-v148-windows-x64\`,
next to the other handlers' emulators. Both are already in place.

MesenCE shows a first-run setup wizard whenever no `settings.json` exists, and
that wizard blocks test-runner mode too. A `settings.json` containing `{}`
next to `Mesen.exe` puts it in portable mode and skips the wizard; it is in
place and the README documents it.

`scripts/launch_in_emulator.ps1` takes `-ArtifactPath`, defaults to the MesenCE
path above, accepts `-EmulatorPath` to point at ares instead, and passes the
ROM as the positional argument. It refuses empty or non-`.sfc` files.

## Validation

`tools/validate_rom.py` fails the build unless all of these hold:

- file size is a multiple of 32 KiB and not 512 bytes over one, so no copier
  header;
- the LoROM internal header at file offset `0x7FC0` has the title
  `HELENGINE SNES` padded to 21 bytes, a LoROM map mode byte, ROM-only
  chipset, a checksum equal to the 16-bit sum of the image computed with the
  checksum fields treated as `0x0000`/`0xFFFF`, and a complement that XORs
  with it to `0xFFFF`;
- the emulation-mode reset vector and the native NMI vector at `0x7FFC` and
  `0x7FEA` point into `0x8000..0xFFFF`.

`tools/tests/test_validate_rom.py` exercises the validator with synthetic
images: a good LoROM image, a copier-headered image, a bad checksum, and a
vector outside ROM.

Emulator acceptance is automated. `scripts/check_in_emulator.ps1` runs

```
Mesen.exe --testrunner --timeout=20 helengine_snes.sfc tools/mesen/red_square_check.lua
```

and MesenCE's exit code is the Lua script's `emu.stop` code, or a non-zero
timeout code if the script never stops. The spike confirmed this on 2026-09-17:
a script stopping with code 7 produced exit code 7, and a centre-pixel colour
check on the spike ROM produced exit code 0 in about one second.

`red_square_check.lua` waits 30 frames, reads the emulator's own frame buffer
through `emu.getScreenBuffer`, and stops with code 0 when the centre pixel is
red and all four corners are black, 3 when the colours are wrong, and 2 when
the check itself raised an error. It uses no file or OS access because
MesenCE's Lua sandbox blocks those by default. This reads emulator memory,
never the desktop.

`scripts/build.ps1` then `scripts/launch_in_emulator.ps1` shows the square
for a human look. ares is run by hand as the cross-check before the milestone
is called done.

## Error handling

There is no operating system to report to. Boot host methods return `bool`
and `Run` returns a distinct non-zero code per failed stage, mirroring the N64
boot host, even though today no stage can fail at runtime. The build scripts
throw on any missing artifact, hash mismatch or non-zero child exit code and
never fall back silently.

## Risks

- The spike compiled a small C++ file. The full boot host uses more of the
  language (static data tables, an interrupt-attributed handler, a few
  classes). If something fails at link time, fix it in the Makefile or a
  small `src/platform/snes` support file and record what was needed in the
  README.
- The toolchain is a preview whose codegen patches are not yet upstream. The
  pin is by package hash so the build stays reproducible if the download
  changes, and the package is kept in `.deps/` so a vanished upstream URL
  does not block local builds.
- The NMI handler relies on the SDK's `interrupt` attribute support for the
  65816 native mode. If the generated prologue is wrong, the handler moves to
  a short assembly stub in `src/platform/snes/`.

## Later milestones

Follow the roadmap in `docs/SuperNintendoDevelopment.md`: input and a moving
sprite, a VBlank DMA queue, scrolling, audio, then the builder assembly and
generated core on the `snes-far` or `snes-hirom` platform.
