# SNES Red Square Boot ROM Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a reproducible Docker build of a headerless LoROM `.sfc` that boots in MesenCE and shows a 64x64 red square centred on a black screen, verified headlessly.

**Architecture:** A C++20 boot host under `src/platform/snes/` drives the PPU through the llvm-mos-65816 SNES SDK headers: reset, Mode 1, palette, two DMA uploads (tiles and tilemap), VBlank NMI, screen on, wait loop. The compiler runs inside a pinned Docker image. Host-side Python tools finalize the ROM header and validate it; a MesenCE Lua script run through its test-runner mode asserts the picture and the NMI counter.

**Tech Stack:** llvm-mos-65816 (`mos-snes-clang++`, clang 23 based) as a `.deb` on Ubuntu 24.04 in Docker; GNU make; Python 3 with `unittest`; PowerShell 5.1 scripts; MesenCE 2.2.1 and ares v148 in `C:\dev\helworks\emus\`.

**Spec:** `docs/superpowers/specs/2026-09-17-snes-red-square-boot-design.md`

## Global Constraints

- Work only on `main`. No branches, no worktrees. Commit after every task.
- Toolchain package: `https://apt.indri.studio/pool/main/l/llvm-mos-65816/llvm-mos-65816_0.0.0+git20260914.f9711be_amd64.deb`, SHA-256 `6485bf206b2db2f46c234e05204d0b51f2fa1949d5575d2022af3a62db4e84ac`.
- Base image: `ubuntu@sha256:69cecf4bbf72d2d44a9eef1b71fb98c7fb973d78af11399deccef19beb008ad9` (Ubuntu 24.04).
- Compiler flags: `-std=c++20 -fno-exceptions -fno-rtti -Os -Wall -Wextra -Isrc`.
- ROM title `HELENGINE SNES`. LoROM, SlowROM, ROM only, no SRAM, 32 KiB. Headerless (no 512-byte copier prefix).
- VRAM word addresses: BG1 tilemap `0x0000`, BG1 character data `0x1000`. Tile 0 transparent, tile 1 solid palette index 1. Square covers tilemap rows 10..17 and columns 12..19.
- CGRAM: colour 0 black, colour 1 red `SNES_RGB(31, 0, 0)`.
- Namespace `helengine::snes`, class prefix `SuperNintendo`, one class per file, `///` doc comment on every class and member, PascalCase fields, opening braces on the same line.
- Emulators: `C:\dev\helworks\emus\Mesen_2.2.1_Windows\Mesen.exe` (portable mode, `settings.json` beside it already exists) and `C:\dev\helworks\emus\ares-v148-windows-x64\ares-v148\ares.exe`.
- Build outputs go to `build/` in the repository and the ROM to the repository root, both gitignored. Never write outputs under `%TEMP%`.
- Cap unknown-size command output: `COMMAND 2>&1 | head -c 4000`.
- No screenshots of the desktop. The emulator check reads the emulator's own frame buffer.
- Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

---

## File Structure

| Path | Responsibility |
|---|---|
| `.gitignore`, `.gitattributes`, `.dockerignore` | Keep outputs and the downloaded package out of git; force LF on files the container reads. |
| `dependencies.json` | The pins: base image digest, package URL, file name and SHA-256, plus the toolchain image id and compiler version written by setup. |
| `Dockerfile` | Ubuntu 24.04 plus the `.deb`, `make` and `python3`. |
| `scripts/setup-toolchain.ps1` | Download and verify the package, build `helengine-snes-toolchain`, record image id and compiler version. |
| `scripts/build.ps1` | Run `make` in the container, validate the ROM, write `build/build-record.json`. |
| `scripts/launch_in_emulator.ps1` | Open the ROM in MesenCE or ares for a human look. |
| `scripts/check_in_emulator.ps1` | Headless MesenCE test-runner check; exit code is the verdict. |
| `Makefile` | Compile `src/**/*.cpp`, link to the raw image and map, finalize to `helengine_snes.sfc`. |
| `tools/finalize_rom.py` | Rewrite the title and compute the checksum pair. |
| `tools/validate_rom.py` | Static checks on the finished ROM. |
| `tools/tests/test_finalize_rom.py`, `tools/tests/test_validate_rom.py` | `unittest` coverage for the two tools using synthetic images. |
| `tools/mesen/red_square_check.lua` | Lua template for the MesenCE check. |
| `src/main.cpp` | Entry point: construct the boot host, return its code. |
| `src/platform/snes/SuperNintendoBootHost.hpp/.cpp` | Boot sequence and frame loop. |
| `src/platform/snes/SuperNintendoVideo.hpp/.cpp` | PPU reset and setup, palette, VRAM DMA, NMI handler and frame counter, VBlank wait. |
| `src/platform/snes/SuperNintendoRedSquareScene.hpp/.cpp` | Tile bytes and the constexpr tilemap for the square. |
| `README.md`, `THIRD_PARTY_NOTICES.md` | How to build, check and run; licence notice for the SDK runtime linked into the ROM. |

---

### Task 1: Repository scaffolding and pinned toolchain image

**Files:**
- Create: `.gitignore`, `.gitattributes`, `.dockerignore`, `dependencies.json`, `Dockerfile`, `scripts/setup-toolchain.ps1`

**Interfaces:**
- Produces: Docker image `helengine-snes-toolchain` with `mos-snes-clang++`, `make` and `python3` on `PATH`; `dependencies.json` with `toolchain.toolchainImage` and `toolchain.compilerVersion` filled in.

- [ ] **Step 1: Write the ignore and attribute files**

`.gitignore`:

```gitignore
# Downloaded toolchain package and other local dependency scratch.
.deps/

# Build outputs.
build/
*.sfc
*.elf
*.map

# Local tool and emulator state.
*.log
*.tmp
```

`.gitattributes` (the container reads these through a bind mount, so they must stay LF):

```gitattributes
* text=auto
Makefile text eol=lf
Dockerfile text eol=lf
*.py text eol=lf
*.lua text eol=lf
*.cpp text eol=lf
*.hpp text eol=lf
*.json text eol=lf
*.md text eol=lf
*.ps1 text eol=crlf
```

`.dockerignore` (only the package enters the build context):

```dockerignore
*
!.deps/*.deb
```

- [ ] **Step 2: Write `dependencies.json`**

```json
{
  "toolchain": {
    "baseImage": "ubuntu@sha256:69cecf4bbf72d2d44a9eef1b71fb98c7fb973d78af11399deccef19beb008ad9",
    "package": {
      "url": "https://apt.indri.studio/pool/main/l/llvm-mos-65816/llvm-mos-65816_0.0.0+git20260914.f9711be_amd64.deb",
      "fileName": "llvm-mos-65816_0.0.0+git20260914.f9711be_amd64.deb",
      "sha256": "6485bf206b2db2f46c234e05204d0b51f2fa1949d5575d2022af3a62db4e84ac"
    },
    "toolchainImage": null,
    "compilerVersion": null
  }
}
```

- [ ] **Step 3: Write the `Dockerfile`**

```dockerfile
# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ARG TOOLCHAIN_DEB
COPY .deps/${TOOLCHAIN_DEB} /tmp/${TOOLCHAIN_DEB}

RUN apt-get update \
    && apt-get install -y --no-install-recommends make python3 /tmp/${TOOLCHAIN_DEB} \
    && rm -rf /var/lib/apt/lists/* /tmp/${TOOLCHAIN_DEB}

WORKDIR /workspace
CMD ["/bin/bash"]
```

- [ ] **Step 4: Write `scripts/setup-toolchain.ps1`**

```powershell
[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$manifestPath = Join-Path $root 'dependencies.json'
$deps = Join-Path $root '.deps'

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$baseImage = $manifest.toolchain.baseImage
if ($baseImage -notmatch '^ubuntu@sha256:[0-9a-f]{64}$') {
    throw 'dependencies.json must contain an immutable Ubuntu base image digest.'
}
$package = $manifest.toolchain.package
if ([string]::IsNullOrWhiteSpace($package.url) -or [string]::IsNullOrWhiteSpace($package.fileName) -or $package.sha256 -notmatch '^[0-9a-f]{64}$') {
    throw 'dependencies.json must contain the toolchain package url, fileName and sha256.'
}

New-Item -ItemType Directory -Force -Path $deps | Out-Null
$packagePath = Join-Path $deps $package.fileName

if ($Force -or -not (Test-Path -LiteralPath $packagePath)) {
    Write-Output "Downloading $($package.url)"
    Invoke-WebRequest -Uri $package.url -OutFile $packagePath -UseBasicParsing
}

$actualHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $package.sha256) {
    Remove-Item -LiteralPath $packagePath -Force
    throw "Toolchain package hash mismatch: expected $($package.sha256), got $actualHash. The file was deleted."
}
Write-Output "Package hash verified: $actualHash"

$dockerArgs = @(
    'build',
    '--build-arg', "BASE_IMAGE=$baseImage",
    '--build-arg', "TOOLCHAIN_DEB=$($package.fileName)",
    '-t', 'helengine-snes-toolchain',
    '-f', (Join-Path $root 'Dockerfile'),
    $root
)
& docker @dockerArgs
if ($LASTEXITCODE -ne 0) { throw 'SNES toolchain image build failed.' }

$toolchainImageId = (& docker image inspect helengine-snes-toolchain --format '{{.Id}}').Trim()
$compilerVersion = (& docker run --rm helengine-snes-toolchain mos-snes-clang++ --version | Select-Object -First 1).Trim()
if (-not $toolchainImageId -or -not $compilerVersion) {
    throw 'Toolchain image identity or compiler version could not be recorded.'
}

$manifest.toolchain.toolchainImage = $toolchainImageId
$manifest.toolchain.compilerVersion = $compilerVersion
($manifest | ConvertTo-Json -Depth 5).Replace("`r`n", "`n") | Set-Content -LiteralPath $manifestPath -Encoding utf8 -NoNewline
Write-Output "toolchain image: $toolchainImageId"
Write-Output "compiler: $compilerVersion"
```

- [ ] **Step 5: Run the setup script**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup-toolchain.ps1 2>&1 | tail -c 3000`

Expected: last lines are `toolchain image: sha256:...` and `compiler: clang version 23.0.0git (https://github.com/llvm-mos/llvm-mos.git ...)`.

- [ ] **Step 6: Verify the image has the tools**

Run: `docker run --rm helengine-snes-toolchain bash -c "which mos-snes-clang++ make python3 && ls /usr/lib/llvm-mos-65816/mos-platform/snes/lib"`

Expected: three paths printed, then `crt0.o libc.a libcrt0.a link.ld`.

- [ ] **Step 7: Verify `dependencies.json` was updated and git ignores the package**

Run: `git status --short && grep -E '"(toolchainImage|compilerVersion)"' dependencies.json`

Expected: `.deps/` does not appear in the status; both fields are non-null strings.

- [ ] **Step 8: Commit**

```bash
git add .gitignore .gitattributes .dockerignore dependencies.json Dockerfile scripts/setup-toolchain.ps1
git commit -m "Add pinned llvm-mos-65816 toolchain image and repository scaffolding

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: ROM finalizer (title and checksum)

**Files:**
- Create: `tools/finalize_rom.py`, `tools/tests/__init__.py` (empty), `tools/tests/rom_fixtures.py`, `tools/tests/test_finalize_rom.py`

**Interfaces:**
- Produces: `finalize_rom.finalize(image: bytes, title: str) -> bytes` and CLI `python3 tools/finalize_rom.py --title TITLE INPUT OUTPUT`. Constants `HEADER_OFFSET = 0x7FC0`, `TITLE_LENGTH = 21`, `COMPLEMENT_OFFSET = 0x7FDC`, `CHECKSUM_OFFSET = 0x7FDE`. `rom_fixtures.make_lorom_image()` returns a 32 KiB bytearray with a valid header and vectors for tests.

- [ ] **Step 1: Write the shared test fixture**

`tools/tests/rom_fixtures.py`:

```python
"""Synthetic LoROM images for the tool tests."""

ROM_SIZE = 0x8000
HEADER_OFFSET = 0x7FC0


def make_lorom_image(title=b"LLVM-MOS SNES        "):
    """Return a 32 KiB image with a plausible LoROM header, zeroed checksum fields and vectors inside ROM."""
    image = bytearray(ROM_SIZE)
    for offset in range(0, ROM_SIZE, 7):
        image[offset] = (offset * 31) & 0xFF
    image[HEADER_OFFSET:HEADER_OFFSET + 21] = title
    image[0x7FD5] = 0x20  # LoROM, SlowROM
    image[0x7FD6] = 0x00  # ROM only
    image[0x7FD7] = 0x05  # 32 KiB
    image[0x7FD8] = 0x00  # no SRAM
    image[0x7FD9] = 0x01  # North America
    image[0x7FDC:0x7FDE] = b"\xFF\xFF"  # complement placeholder
    image[0x7FDE:0x7FE0] = b"\x00\x00"  # checksum placeholder
    image[0x7FEA:0x7FEC] = (0x802B).to_bytes(2, "little")  # native NMI
    image[0x7FFC:0x7FFE] = (0x8000).to_bytes(2, "little")  # emulation RESET
    return image
```

- [ ] **Step 2: Write the failing tests**

`tools/tests/test_finalize_rom.py`:

```python
import unittest

from tools import finalize_rom
from tools.tests.rom_fixtures import make_lorom_image


class FinalizeRomTests(unittest.TestCase):
    def test_title_is_written_space_padded(self):
        result = finalize_rom.finalize(bytes(make_lorom_image()), "HELENGINE SNES")
        self.assertEqual(result[0x7FC0:0x7FD5], b"HELENGINE SNES       ")

    def test_checksum_pair_is_consistent_and_matches_sum(self):
        result = finalize_rom.finalize(bytes(make_lorom_image()), "HELENGINE SNES")
        complement = int.from_bytes(result[0x7FDC:0x7FDE], "little")
        checksum = int.from_bytes(result[0x7FDE:0x7FE0], "little")
        self.assertEqual(complement ^ checksum, 0xFFFF)
        scratch = bytearray(result)
        scratch[0x7FDC:0x7FDE] = b"\xFF\xFF"
        scratch[0x7FDE:0x7FE0] = b"\x00\x00"
        self.assertEqual(checksum, sum(scratch) & 0xFFFF)

    def test_finalize_is_idempotent(self):
        once = finalize_rom.finalize(bytes(make_lorom_image()), "HELENGINE SNES")
        twice = finalize_rom.finalize(once, "HELENGINE SNES")
        self.assertEqual(once, twice)

    def test_rejects_title_longer_than_21_bytes(self):
        with self.assertRaises(ValueError):
            finalize_rom.finalize(bytes(make_lorom_image()), "THIS TITLE IS FAR TOO LONG")

    def test_rejects_non_power_of_two_size(self):
        with self.assertRaises(ValueError):
            finalize_rom.finalize(bytes(make_lorom_image()) + b"\x00" * 100, "HELENGINE SNES")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `python -m unittest tools.tests.test_finalize_rom -v 2>&1 | tail -c 2000`

Expected: `ModuleNotFoundError: No module named 'tools.finalize_rom'` (create an empty `tools/__init__.py` if Python complains that `tools` is not a package).

- [ ] **Step 4: Write the finalizer**

`tools/finalize_rom.py`:

```python
"""Finalize a raw LoROM image emitted by the SDK linker.

Writes the cartridge title into the internal header and computes the
checksum/complement pair. Only power-of-two image sizes are supported,
which is all the SDK's LoROM link script produces.
"""

import argparse
import sys

HEADER_OFFSET = 0x7FC0
TITLE_LENGTH = 21
COMPLEMENT_OFFSET = 0x7FDC
CHECKSUM_OFFSET = 0x7FDE
MIN_SIZE = 0x8000


def finalize(image, title):
    """Return a new image with the title and checksum pair written."""
    size = len(image)
    if size < MIN_SIZE or (size & (size - 1)) != 0:
        raise ValueError(f"image size {size} is not a power of two of at least {MIN_SIZE} bytes")
    encoded = title.encode("ascii")
    if len(encoded) > TITLE_LENGTH:
        raise ValueError(f"title {title!r} is longer than {TITLE_LENGTH} bytes")
    result = bytearray(image)
    result[HEADER_OFFSET:HEADER_OFFSET + TITLE_LENGTH] = encoded.ljust(TITLE_LENGTH, b" ")
    result[COMPLEMENT_OFFSET:COMPLEMENT_OFFSET + 2] = b"\xFF\xFF"
    result[CHECKSUM_OFFSET:CHECKSUM_OFFSET + 2] = b"\x00\x00"
    checksum = sum(result) & 0xFFFF
    complement = checksum ^ 0xFFFF
    result[COMPLEMENT_OFFSET:COMPLEMENT_OFFSET + 2] = complement.to_bytes(2, "little")
    result[CHECKSUM_OFFSET:CHECKSUM_OFFSET + 2] = checksum.to_bytes(2, "little")
    return bytes(result)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--title", required=True)
    parser.add_argument("input")
    parser.add_argument("output")
    args = parser.parse_args(argv)
    with open(args.input, "rb") as handle:
        image = handle.read()
    result = finalize(image, args.title)
    with open(args.output, "wb") as handle:
        handle.write(result)
    checksum = int.from_bytes(result[CHECKSUM_OFFSET:CHECKSUM_OFFSET + 2], "little")
    print(f"finalized {args.output}: {len(result)} bytes, checksum 0x{checksum:04X}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

Also create empty `tools/__init__.py` and `tools/tests/__init__.py`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `python -m unittest tools.tests.test_finalize_rom -v 2>&1 | tail -c 2000`

Expected: `Ran 5 tests` and `OK`.

- [ ] **Step 6: Commit**

```bash
git add tools/__init__.py tools/finalize_rom.py tools/tests/__init__.py tools/tests/rom_fixtures.py tools/tests/test_finalize_rom.py
git commit -m "Add ROM finalizer that writes the title and checksum pair

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: ROM validator

**Files:**
- Create: `tools/validate_rom.py`, `tools/tests/test_validate_rom.py`

**Interfaces:**
- Consumes: `finalize_rom.finalize`, `rom_fixtures.make_lorom_image`.
- Produces: `validate_rom.validate(image: bytes, expected_title: str) -> list[str]` returning problems (empty means valid) and CLI `python3 tools/validate_rom.py [--title TITLE] ROM` exiting 0 when valid and 1 otherwise. Default title `HELENGINE SNES`.

- [ ] **Step 1: Write the failing tests**

`tools/tests/test_validate_rom.py`:

```python
import unittest

from tools import finalize_rom, validate_rom
from tools.tests.rom_fixtures import make_lorom_image

TITLE = "HELENGINE SNES"


def good_image():
    return finalize_rom.finalize(bytes(make_lorom_image()), TITLE)


class ValidateRomTests(unittest.TestCase):
    def test_finalized_image_is_valid(self):
        self.assertEqual(validate_rom.validate(good_image(), TITLE), [])

    def test_copier_header_is_rejected(self):
        problems = validate_rom.validate(b"\x00" * 512 + good_image(), TITLE)
        self.assertTrue(any("copier" in p for p in problems), problems)

    def test_wrong_checksum_is_rejected(self):
        image = bytearray(good_image())
        image[0x7FDE] ^= 0x01
        problems = validate_rom.validate(bytes(image), TITLE)
        self.assertTrue(any("checksum" in p for p in problems), problems)

    def test_reset_vector_outside_rom_is_rejected(self):
        image = bytearray(make_lorom_image())
        image[0x7FFC:0x7FFE] = (0x1234).to_bytes(2, "little")
        problems = validate_rom.validate(finalize_rom.finalize(bytes(image), TITLE), TITLE)
        self.assertTrue(any("RESET" in p for p in problems), problems)

    def test_nmi_vector_outside_rom_is_rejected(self):
        image = bytearray(make_lorom_image())
        image[0x7FEA:0x7FEC] = (0x0000).to_bytes(2, "little")
        problems = validate_rom.validate(finalize_rom.finalize(bytes(image), TITLE), TITLE)
        self.assertTrue(any("NMI" in p for p in problems), problems)

    def test_wrong_title_is_rejected(self):
        problems = validate_rom.validate(good_image(), "SOMETHING ELSE")
        self.assertTrue(any("title" in p for p in problems), problems)

    def test_hirom_map_mode_is_rejected(self):
        image = bytearray(make_lorom_image())
        image[0x7FD5] = 0x21
        problems = validate_rom.validate(finalize_rom.finalize(bytes(image), TITLE), TITLE)
        self.assertTrue(any("map mode" in p for p in problems), problems)

    def test_rom_size_byte_must_match_file_size(self):
        image = bytearray(make_lorom_image())
        image[0x7FD7] = 0x06
        problems = validate_rom.validate(finalize_rom.finalize(bytes(image), TITLE), TITLE)
        self.assertTrue(any("ROM size" in p for p in problems), problems)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python -m unittest tools.tests.test_validate_rom -v 2>&1 | tail -c 2000`

Expected: `ImportError: cannot import name 'validate_rom'`.

- [ ] **Step 3: Write the validator**

`tools/validate_rom.py`:

```python
"""Static checks on a finished headerless LoROM image.

Exit code 0 when every check passes, 1 otherwise, with one line per problem.
"""

import argparse
import sys

BANK_SIZE = 0x8000
HEADER_OFFSET = 0x7FC0
TITLE_LENGTH = 21
MAP_MODE_OFFSET = 0x7FD5
CHIPSET_OFFSET = 0x7FD6
ROM_SIZE_OFFSET = 0x7FD7
COMPLEMENT_OFFSET = 0x7FDC
CHECKSUM_OFFSET = 0x7FDE
NATIVE_NMI_VECTOR_OFFSET = 0x7FEA
EMULATION_RESET_VECTOR_OFFSET = 0x7FFC
DEFAULT_TITLE = "HELENGINE SNES"


def _word(image, offset):
    return int.from_bytes(image[offset:offset + 2], "little")


def validate(image, expected_title=DEFAULT_TITLE):
    """Return a list of problem descriptions; an empty list means the image is valid."""
    problems = []
    size = len(image)
    if size % BANK_SIZE == 512:
        problems.append(f"image has a 512-byte copier header (size {size})")
        return problems
    if size < BANK_SIZE or size % BANK_SIZE != 0:
        problems.append(f"image size {size} is not a multiple of {BANK_SIZE}")
        return problems

    title = image[HEADER_OFFSET:HEADER_OFFSET + TITLE_LENGTH]
    expected = expected_title.encode("ascii").ljust(TITLE_LENGTH, b" ")
    if title != expected:
        problems.append(f"title {title!r} does not match expected {expected!r}")

    map_mode = image[MAP_MODE_OFFSET]
    if map_mode & 0x0F != 0x00 or map_mode & 0x20 != 0x20:
        problems.append(f"map mode 0x{map_mode:02X} is not LoROM")

    chipset = image[CHIPSET_OFFSET]
    if chipset != 0x00:
        problems.append(f"chipset 0x{chipset:02X} is not ROM only")

    declared_size = 1024 << image[ROM_SIZE_OFFSET]
    if declared_size != size:
        problems.append(f"ROM size byte declares {declared_size} bytes but the image is {size} bytes")

    complement = _word(image, COMPLEMENT_OFFSET)
    checksum = _word(image, CHECKSUM_OFFSET)
    if complement ^ checksum != 0xFFFF:
        problems.append(f"checksum 0x{checksum:04X} and complement 0x{complement:04X} do not XOR to 0xFFFF")
    scratch = bytearray(image)
    scratch[COMPLEMENT_OFFSET:COMPLEMENT_OFFSET + 2] = b"\xFF\xFF"
    scratch[CHECKSUM_OFFSET:CHECKSUM_OFFSET + 2] = b"\x00\x00"
    computed = sum(scratch) & 0xFFFF
    if computed != checksum:
        problems.append(f"checksum 0x{checksum:04X} does not match computed 0x{computed:04X}")

    for name, offset in (("RESET", EMULATION_RESET_VECTOR_OFFSET), ("NMI", NATIVE_NMI_VECTOR_OFFSET)):
        vector = _word(image, offset)
        if not 0x8000 <= vector <= 0xFFFF:
            problems.append(f"{name} vector 0x{vector:04X} points outside ROM")
    return problems


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--title", default=DEFAULT_TITLE)
    parser.add_argument("rom")
    args = parser.parse_args(argv)
    with open(args.rom, "rb") as handle:
        image = handle.read()
    problems = validate(image, args.title)
    for problem in problems:
        print(f"validate_rom: {problem}")
    if problems:
        return 1
    print(f"validate_rom: {args.rom} is a valid {len(image)}-byte LoROM image")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

- [ ] **Step 4: Run all tool tests to verify they pass**

Run: `python -m unittest discover -s tools/tests -t . -v 2>&1 | tail -c 2500`

Expected: `Ran 13 tests` and `OK`.

- [ ] **Step 5: Commit**

```bash
git add tools/validate_rom.py tools/tests/test_validate_rom.py
git commit -m "Add static LoROM validator with header, checksum and vector checks

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Makefile, entry point and a minimal boot host that builds

**Files:**
- Create: `Makefile`, `src/main.cpp`, `src/platform/snes/SuperNintendoBootHost.hpp`, `src/platform/snes/SuperNintendoBootHost.cpp`

**Interfaces:**
- Consumes: `tools/finalize_rom.py`, `tools/validate_rom.py`, image `helengine-snes-toolchain`.
- Produces: `make` in the container yields `build/helengine_snes.elf`, `build/helengine_snes.map`, `build/helengine_snes.raw.sfc` and the finalized `helengine_snes.sfc` at the root. Class `helengine::snes::SuperNintendoBootHost` with `int Run()`; later tasks replace its body.

- [ ] **Step 1: Write the `Makefile`** (recipes must be indented with a tab)

```make
.DEFAULT_GOAL := all

TARGET := helengine_snes
BUILD_DIR := build
ROM_TITLE := HELENGINE SNES

CXX := mos-snes-clang++
CXXFLAGS := -std=c++20 -fno-exceptions -fno-rtti -Os -Wall -Wextra -Isrc -MMD -MP

SOURCES := $(wildcard src/*.cpp) $(wildcard src/platform/snes/*.cpp)
OBJECTS := $(patsubst src/%.cpp,$(BUILD_DIR)/%.o,$(SOURCES))
RAW_ROM := $(BUILD_DIR)/$(TARGET).raw.sfc
ELF := $(BUILD_DIR)/$(TARGET).elf
MAP := $(BUILD_DIR)/$(TARGET).map
ROM := $(TARGET).sfc

.PHONY: all clean

all: $(ROM)

$(BUILD_DIR)/%.o: src/%.cpp
	@mkdir -p $(dir $@)
	@echo "    [CXX] $<"
	$(CXX) $(CXXFLAGS) -c -o $@ $<

# The SDK link script emits the raw 32 KiB image directly and drops an ELF
# sidecar next to it as <output>.elf; move the sidecar to the documented name.
$(RAW_ROM): $(OBJECTS)
	@echo "    [LD]  $@"
	$(CXX) $(CXXFLAGS) -Wl,-Map,$(MAP) -o $@ $(OBJECTS)
	mv $@.elf $(ELF)

$(ROM): $(RAW_ROM) tools/finalize_rom.py
	python3 tools/finalize_rom.py --title "$(ROM_TITLE)" $(RAW_ROM) $@
	python3 tools/validate_rom.py --title "$(ROM_TITLE)" $@

clean:
	rm -rf $(BUILD_DIR) $(ROM)

-include $(OBJECTS:.o=.d)
```

- [ ] **Step 2: Write the boot host header**

`src/platform/snes/SuperNintendoBootHost.hpp`:

```cpp
#pragma once

namespace helengine::snes {

/// Owns the SNES boot sequence for the diagnostic ROM: brings the PPU to a
/// known state, uploads the red-square scene and then idles on VBlank forever.
class SuperNintendoBootHost {
public:
    /// Runs the boot sequence. Returns a distinct non-zero code for each stage
    /// that can fail; never returns while the display is running.
    int Run();
};

} // namespace helengine::snes
```

- [ ] **Step 3: Write the minimal boot host body** (backdrop only; proves the pipeline)

`src/platform/snes/SuperNintendoBootHost.cpp`:

```cpp
#include "platform/snes/SuperNintendoBootHost.hpp"

#include <snes.h>

namespace helengine::snes {

int SuperNintendoBootHost::Run() {
    snes_ppu_reset_blank();
    REG_CGADD = 0;
    REG_CGDATA = static_cast<uint8_t>(SNES_RGB(0, 0, 0));
    REG_CGDATA = static_cast<uint8_t>(SNES_RGB(0, 0, 0) >> 8);
    REG_INIDISP = INIDISP_ON;
    for (;;) {
    }
}

} // namespace helengine::snes
```

- [ ] **Step 4: Write the entry point**

`src/main.cpp`:

```cpp
#include "platform/snes/SuperNintendoBootHost.hpp"

/// Program entry after the SDK crt0 has switched to native mode and cleared RAM.
int main() {
    helengine::snes::SuperNintendoBootHost host;
    return host.Run();
}
```

- [ ] **Step 5: Build in the container**

Run: `docker run --rm -v "$(pwd -W):/workspace" -w /workspace helengine-snes-toolchain make 2>&1 | tail -c 3000`

Expected: `[CXX]` lines for both sources, `[LD]`, then `finalized helengine_snes.sfc: 32768 bytes, checksum 0x....` and `validate_rom: helengine_snes.sfc is a valid 32768-byte LoROM image`. If the linker reports `region 'rom' overflowed`, the near-code window is full; that must not happen with this much code, so investigate rather than switch platform.

If `mv` fails because no `.raw.sfc.elf` sidecar exists, run `ls build` and adapt the recipe to the sidecar name the SDK actually produced (the spike produced `hello_cpp.sfc.elf` next to `hello_cpp.sfc`).

- [ ] **Step 6: Confirm the artifacts and that they are ignored**

Run: `ls -la build helengine_snes.sfc && git status --short`

Expected: `helengine_snes.elf`, `helengine_snes.map`, `helengine_snes.raw.sfc` and `.o`/`.d` files under `build/`; a 32768-byte `helengine_snes.sfc`; git status lists only the new source files, no outputs.

- [ ] **Step 7: Confirm the map names the boot host**

Run: `grep -c "SuperNintendoBootHost" build/helengine_snes.map`

Expected: a number greater than 0.

- [ ] **Step 8: Commit**

```bash
git add Makefile src/main.cpp src/platform/snes/SuperNintendoBootHost.hpp src/platform/snes/SuperNintendoBootHost.cpp
git commit -m "Add Makefile and minimal C++ boot host that links to a valid LoROM

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Headless emulator check (the failing test for the square)

**Files:**
- Create: `tools/mesen/red_square_check.lua`, `scripts/check_in_emulator.ps1`

**Interfaces:**
- Consumes: `helengine_snes.sfc`, `build/helengine_snes.map`, MesenCE at `C:\dev\helworks\emus\Mesen_2.2.1_Windows\Mesen.exe`.
- Produces: `scripts/check_in_emulator.ps1 [-RomPath] [-MesenPath]` exiting 0 on pass, 3 on wrong colours, 4 when the frame counter did not advance, 2 on a Lua error, and a non-zero code from MesenCE itself on timeout. The Lua template contains the literal token `__FRAME_COUNTER_ADDRESS__` which the script replaces with the WRAM address of the symbol `HelengineSnesFrameCounter` read from the map file (Task 6 defines that symbol; until then the script substitutes `0` and the Lua skips the counter check when the address is `0`).

- [ ] **Step 1: Write the Lua template**

`tools/mesen/red_square_check.lua`:

```lua
-- Headless acceptance check for the red-square boot ROM, run through
-- MesenCE's --testrunner mode. Exit codes (via emu.stop):
--   0 pass, 2 script error, 3 wrong colours, 4 frame counter did not advance.
-- No file or OS access is used: MesenCE's Lua sandbox blocks it by default.

local FRAME_COUNTER_ADDRESS = __FRAME_COUNTER_ADDRESS__
local SAMPLE_FRAME = 30
local COUNTER_FRAME = 60

local frames = 0
local counterAtSample = nil

local function channels(px)
  return (px >> 16) & 0xFF, (px >> 8) & 0xFF, px & 0xFF
end

local function isRed(px)
  local r, g, b = channels(px)
  return r > 200 and g < 40 and b < 40
end

local function isBlack(px)
  local r, g, b = channels(px)
  return r < 24 and g < 24 and b < 24
end

local function readCounter()
  return emu.readWord(FRAME_COUNTER_ADDRESS, emu.memType.snesWorkRam)
end

local function checkPicture()
  local size = emu.getScreenSize()
  local w, h = size.width, size.height
  local buf = emu.getScreenBuffer()
  local function at(x, y) return buf[y * w + x + 1] end
  local cx, cy = math.floor(w / 2), math.floor(h / 2)
  if not isRed(at(cx, cy)) then return false end
  local inset = 4
  local corners = { at(inset, inset), at(w - 1 - inset, inset), at(inset, h - 1 - inset), at(w - 1 - inset, h - 1 - inset) }
  for _, px in ipairs(corners) do
    if not isBlack(px) then return false end
  end
  return true
end

local function onFrame()
  frames = frames + 1
  local ok, code = pcall(function()
    if frames == SAMPLE_FRAME then
      if not checkPicture() then return 3 end
      if FRAME_COUNTER_ADDRESS == 0 then return 0 end
      counterAtSample = readCounter()
      return nil
    end
    if frames == COUNTER_FRAME then
      if readCounter() == counterAtSample then return 4 end
      return 0
    end
    return nil
  end)
  if not ok then
    emu.stop(2)
  elseif code ~= nil then
    emu.stop(code)
  end
end

emu.addEventCallback(onFrame, emu.eventType.endFrame)
```

- [ ] **Step 2: Write the check script**

`scripts/check_in_emulator.ps1`:

```powershell
[CmdletBinding()]
param(
    [string]$RomPath = '',
    [string]$MesenPath = 'C:\dev\helworks\emus\Mesen_2.2.1_Windows\Mesen.exe',
    [int]$TimeoutSeconds = 20
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($RomPath)) { $RomPath = Join-Path $root 'helengine_snes.sfc' }
$rom = (Resolve-Path -LiteralPath $RomPath).Path
if ((Get-Item -LiteralPath $rom).Length -le 0) { throw "ROM artifact is empty: $rom" }
if ([System.IO.Path]::GetExtension($rom) -ine '.sfc') { throw "Expected a .sfc artifact: $rom" }

$mesen = (Resolve-Path -LiteralPath $MesenPath).Path
$portableSettings = Join-Path (Split-Path -Parent $mesen) 'settings.json'
if (-not (Test-Path -LiteralPath $portableSettings)) {
    throw "MesenCE needs a portable settings.json next to Mesen.exe or its first-run wizard blocks test-runner mode. Create '$portableSettings' containing {} and retry."
}

# Resolve the frame counter's WRAM address from the linker map so the Lua
# check can prove the VBlank NMI is firing. 0 disables that part of the check.
$mapPath = Join-Path $root 'build\helengine_snes.map'
$counterAddress = 0
if (Test-Path -LiteralPath $mapPath) {
    foreach ($line in Get-Content -LiteralPath $mapPath) {
        if ($line -match '^\s*([0-9a-fA-F]+)\s+[0-9a-fA-F]+\s+[0-9a-fA-F]+\s+\d+\s+HelengineSnesFrameCounter\s*$') {
            $counterAddress = [Convert]::ToInt32($Matches[1], 16)
            break
        }
    }
}

$template = Get-Content -LiteralPath (Join-Path $root 'tools\mesen\red_square_check.lua') -Raw
$generatedDir = Join-Path $root 'build'
New-Item -ItemType Directory -Force -Path $generatedDir | Out-Null
$generatedLua = Join-Path $generatedDir 'red_square_check.generated.lua'
$template.Replace('__FRAME_COUNTER_ADDRESS__', [string]$counterAddress) | Set-Content -LiteralPath $generatedLua -Encoding ascii

Write-Output "ROM=$rom"
Write-Output "FRAME_COUNTER_ADDRESS=0x$($counterAddress.ToString('X4'))"
$process = Start-Process -FilePath $mesen -ArgumentList @('--testrunner', "--timeout=$TimeoutSeconds", "`"$rom`"", "`"$generatedLua`"") -PassThru -Wait -WindowStyle Hidden
$code = $process.ExitCode
switch ($code) {
    0 { Write-Output 'RESULT=pass (red centre, black corners, frame counter advancing)' }
    2 { Write-Output 'RESULT=fail (Lua error inside the check)' }
    3 { Write-Output 'RESULT=fail (wrong colours)' }
    4 { Write-Output 'RESULT=fail (frame counter did not advance; NMI not firing)' }
    default { Write-Output "RESULT=fail (MesenCE exit code $code; timeout or ROM did not load)" }
}
exit $code
```

- [ ] **Step 3: Run the check against the Task 4 ROM to see it fail**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check_in_emulator.ps1; echo "exit=$?"`

Expected: `FRAME_COUNTER_ADDRESS=0x0000`, `RESULT=fail (wrong colours)`, `exit=3`. The centre is black because nothing is drawn yet. If the exit is a large number and the run took the full timeout, the wizard is blocking: confirm `settings.json` exists next to `Mesen.exe`.

- [ ] **Step 4: Commit**

```bash
git add tools/mesen/red_square_check.lua scripts/check_in_emulator.ps1
git commit -m "Add headless MesenCE acceptance check for the red square

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Video backend with NMI frame counter

**Files:**
- Create: `src/platform/snes/SuperNintendoVideo.hpp`, `src/platform/snes/SuperNintendoVideo.cpp`

**Interfaces:**
- Produces:
  - `constexpr uint16_t Bg1TilemapWordAddress = 0x0000;` and `constexpr uint16_t Bg1CharacterWordAddress = 0x1000;`
  - class `SuperNintendoVideo` with `bool Initialize()`, `void WritePalette(uint8_t index, uint16_t bgr555)`, `void UploadVram(uint16_t wordAddress, const void* source, uint16_t byteCount)`, `void EnableVBlankInterrupt()`, `void ScreenOn()`, `void WaitForVBlank()`, `static uint16_t FrameCount()`.
  - C symbol `HelengineSnesFrameCounter` (`volatile uint16_t`) incremented by the NMI handler `nmi`.

- [ ] **Step 1: Write the header**

`src/platform/snes/SuperNintendoVideo.hpp`:

```cpp
#pragma once

#include <stdint.h>

namespace helengine::snes {

/// VRAM word address of the BG1 32x32 tilemap (2 KiB).
constexpr uint16_t Bg1TilemapWordAddress = 0x0000;

/// VRAM word address of the BG1 4bpp character data.
constexpr uint16_t Bg1CharacterWordAddress = 0x1000;

/// Thin PPU backend for the boot ROM: register setup, palette writes, VRAM
/// uploads over DMA channel 0, and VBlank synchronisation through the NMI.
/// Every write here happens while the screen is force-blanked or during
/// VBlank, which is the only time VRAM and CGRAM are safe to touch.
class SuperNintendoVideo {
public:
    /// Force-blanks, zeroes the PPU control registers, selects Mode 1 with
    /// BG1 only on the main screen and points BG1 at the fixed VRAM layout.
    bool Initialize();

    /// Writes one CGRAM entry. Colour is BGR555 as produced by SNES_RGB.
    void WritePalette(uint8_t index, uint16_t bgr555);

    /// Copies byteCount bytes from near memory (ROM or WRAM in bank 0) to
    /// VRAM starting at the given word address, using DMA channel 0.
    void UploadVram(uint16_t wordAddress, const void* source, uint16_t byteCount);

    /// Enables the VBlank NMI so the frame counter starts advancing.
    void EnableVBlankInterrupt();

    /// Releases force-blank at full brightness.
    void ScreenOn();

    /// Blocks until the NMI handler has counted one more frame.
    void WaitForVBlank();

    /// Number of VBlank interrupts seen since boot, wrapping at 16 bits.
    static uint16_t FrameCount();
};

} // namespace helengine::snes
```

- [ ] **Step 2: Write the implementation**

`src/platform/snes/SuperNintendoVideo.cpp`:

```cpp
#include "platform/snes/SuperNintendoVideo.hpp"

#include <snes.h>

/// VBlank counter advanced by the NMI handler. Unmangled C linkage so the
/// linker map lists it by this exact name for the emulator check.
extern "C" volatile uint16_t HelengineSnesFrameCounter = 0;

/// VBlank NMI handler. Overrides the SDK's weak `nmi` stub. Reads RDNMI to
/// acknowledge the interrupt and bumps the frame counter; nothing else.
extern "C" void nmi() __attribute__((interrupt, noinline));
extern "C" void nmi() {
    (void)REG_RDNMI;
    HelengineSnesFrameCounter = static_cast<uint16_t>(HelengineSnesFrameCounter + 1);
}

namespace helengine::snes {

bool SuperNintendoVideo::Initialize() {
    snes_ppu_reset_blank();
    REG_BGMODE = BGMODE_1;
    REG_BG1SC = SNES_BGSC(Bg1TilemapWordAddress, 0);
    // BG12NBA bits 3-0 select BG1's character base in 4K-word units.
    REG_BG12NBA = static_cast<uint8_t>((Bg1CharacterWordAddress >> 12) & 0x0F);
    REG_TM = TM_BG1;
    return true;
}

void SuperNintendoVideo::WritePalette(uint8_t index, uint16_t bgr555) {
    REG_CGADD = index;
    REG_CGDATA = static_cast<uint8_t>(bgr555);
    REG_CGDATA = static_cast<uint8_t>(bgr555 >> 8);
}

void SuperNintendoVideo::UploadVram(uint16_t wordAddress, const void* source, uint16_t byteCount) {
    REG_VMAIN = VMAIN_INC_HIGH_1;
    REG_VMADD = wordAddress;
    REG_DMAP0 = DMAP_TO_PPU | DMAP_ADDR_INC | DMAP_UNIT_2;
    REG_BBAD0 = BBAD_VMDATA;
    // Near pointers are 16-bit bank-0 addresses on this platform: ROM at
    // $8000-$FFFF and low WRAM at $0000-$1FFF, both reachable by DMA from bank 0.
    const uint16_t address = static_cast<uint16_t>(reinterpret_cast<uintptr_t>(source));
    REG_A1T0L = static_cast<uint8_t>(address);
    REG_A1T0H = static_cast<uint8_t>(address >> 8);
    REG_A1B0 = 0x00;
    REG_DAS0L = static_cast<uint8_t>(byteCount);
    REG_DAS0H = static_cast<uint8_t>(byteCount >> 8);
    REG_MDMAEN = 0x01;
}

void SuperNintendoVideo::EnableVBlankInterrupt() {
    (void)REG_RDNMI;
    REG_NMITIMEN = NMITIMEN_NMI;
}

void SuperNintendoVideo::ScreenOn() {
    REG_INIDISP = INIDISP_ON;
}

void SuperNintendoVideo::WaitForVBlank() {
    const uint16_t start = HelengineSnesFrameCounter;
    while (HelengineSnesFrameCounter == start) {
    }
}

uint16_t SuperNintendoVideo::FrameCount() {
    return HelengineSnesFrameCounter;
}

} // namespace helengine::snes
```

- [ ] **Step 3: Build in the container**

Run: `docker run --rm -v "$(pwd -W):/workspace" -w /workspace helengine-snes-toolchain make 2>&1 | tail -c 3000`

Expected: compiles and links with no warnings and the validator passes. If clang rejects `extern "C" volatile uint16_t HelengineSnesFrameCounter = 0;` with a warning about an initialised extern declaration, wrap the definition in `extern "C" { volatile uint16_t HelengineSnesFrameCounter = 0; }` instead. If the `interrupt` attribute is reported as unknown for C++, that is the risk called out in the spec: replace the C++ handler with a `.s` stub that does `inc HelengineSnesFrameCounter`, `rti` and add `src/platform/snes/*.s` to the Makefile.

- [ ] **Step 4: Confirm the counter symbol is in the map and in WRAM**

Run: `grep -E "HelengineSnesFrameCounter|\bnmi\b" build/helengine_snes.map | head -5`

Expected: a line whose first hex field is between `200` and `1fff` for `HelengineSnesFrameCounter`, and a `nmi` line whose address is `8000` or above.

- [ ] **Step 5: Commit**

```bash
git add src/platform/snes/SuperNintendoVideo.hpp src/platform/snes/SuperNintendoVideo.cpp
git commit -m "Add SNES video backend with DMA upload and NMI frame counter

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Red-square scene and boot host wiring (make the check pass)

**Files:**
- Create: `src/platform/snes/SuperNintendoRedSquareScene.hpp`, `src/platform/snes/SuperNintendoRedSquareScene.cpp`
- Modify: `src/platform/snes/SuperNintendoBootHost.hpp`, `src/platform/snes/SuperNintendoBootHost.cpp`

**Interfaces:**
- Consumes: `SuperNintendoVideo`, `Bg1TilemapWordAddress`, `Bg1CharacterWordAddress`.
- Produces: class `SuperNintendoRedSquareScene` with `static const uint8_t* Tiles()`, `static constexpr uint16_t TileByteCount = 64`, `static const uint16_t* TilemapEntries()`, `static constexpr uint16_t TilemapByteCount = 2048`.

- [ ] **Step 1: Write the scene header**

`src/platform/snes/SuperNintendoRedSquareScene.hpp`:

```cpp
#pragma once

#include <stdint.h>

namespace helengine::snes {

/// Static graphics for the diagnostic scene: two 4bpp tiles and a 32x32
/// tilemap that places a 64x64 pixel square of tile 1 at the screen centre.
/// All data is built at compile time and lives in ROM.
class SuperNintendoRedSquareScene {
public:
    /// Size in bytes of the two 4bpp 8x8 tiles returned by Tiles().
    static constexpr uint16_t TileByteCount = 64;

    /// Size in bytes of the 32x32 tilemap returned by TilemapEntries().
    static constexpr uint16_t TilemapByteCount = 2048;

    /// Tile 0 is fully transparent (palette index 0), tile 1 is solid palette index 1.
    static const uint8_t* Tiles();

    /// 1024 tilemap words: tile 0 everywhere except rows 10..17, columns 12..19, which use tile 1.
    static const uint16_t* TilemapEntries();
};

} // namespace helengine::snes
```

- [ ] **Step 2: Write the scene data**

`src/platform/snes/SuperNintendoRedSquareScene.cpp`:

```cpp
#include "platform/snes/SuperNintendoRedSquareScene.hpp"

namespace helengine::snes {

namespace {

/// 4bpp SNES tile layout: 8 rows of (plane0, plane1) byte pairs, then 8 rows
/// of (plane2, plane3). Palette index 1 means plane 0 set, all others clear.
constexpr uint8_t TileData[SuperNintendoRedSquareScene::TileByteCount] = {
    // Tile 0: transparent.
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    // Tile 1: every pixel palette index 1.
    0xFF, 0, 0xFF, 0, 0xFF, 0, 0xFF, 0, 0xFF, 0, 0xFF, 0, 0xFF, 0, 0xFF, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
};

constexpr uint8_t MapColumns = 32;
constexpr uint8_t MapRows = 32;
constexpr uint8_t SquareFirstColumn = 12;
constexpr uint8_t SquareLastColumn = 19;
constexpr uint8_t SquareFirstRow = 10;
constexpr uint8_t SquareLastRow = 17;

/// Holds the whole tilemap so a constexpr function can return it by value.
struct TilemapImage {
    uint16_t Entries[MapColumns * MapRows];
};

/// Tilemap word format: bits 9-0 tile, 12-10 palette, 13 priority, 14 hflip, 15 vflip.
constexpr TilemapImage BuildTilemap() {
    TilemapImage image = {};
    for (uint16_t row = 0; row < MapRows; ++row) {
        for (uint16_t column = 0; column < MapColumns; ++column) {
            const bool inside = row >= SquareFirstRow && row <= SquareLastRow &&
                                column >= SquareFirstColumn && column <= SquareLastColumn;
            image.Entries[row * MapColumns + column] = inside ? 0x0001 : 0x0000;
        }
    }
    return image;
}

constexpr TilemapImage TilemapData = BuildTilemap();

static_assert(sizeof(TilemapData.Entries) == SuperNintendoRedSquareScene::TilemapByteCount);
static_assert(sizeof(TileData) == SuperNintendoRedSquareScene::TileByteCount);

} // namespace

const uint8_t* SuperNintendoRedSquareScene::Tiles() {
    return TileData;
}

const uint16_t* SuperNintendoRedSquareScene::TilemapEntries() {
    return TilemapData.Entries;
}

} // namespace helengine::snes
```

- [ ] **Step 3: Update the boot host header to own the video backend**

Replace `src/platform/snes/SuperNintendoBootHost.hpp` with:

```cpp
#pragma once

#include "platform/snes/SuperNintendoVideo.hpp"

namespace helengine::snes {

/// Owns the SNES boot sequence for the diagnostic ROM: brings the PPU to a
/// known state, uploads the red-square scene and then idles on VBlank forever.
class SuperNintendoBootHost {
    /// PPU backend used for every register and memory write.
    SuperNintendoVideo Video;

public:
    /// Runs the boot sequence. Returns 1 if video initialisation fails;
    /// never returns once the display is running.
    int Run();
};

} // namespace helengine::snes
```

- [ ] **Step 4: Replace the boot host body with the full sequence**

`src/platform/snes/SuperNintendoBootHost.cpp`:

```cpp
#include "platform/snes/SuperNintendoBootHost.hpp"

#include "platform/snes/SuperNintendoRedSquareScene.hpp"

#include <snes.h>

namespace helengine::snes {

int SuperNintendoBootHost::Run() {
    if (!Video.Initialize()) {
        return 1;
    }
    Video.WritePalette(0, SNES_RGB(0, 0, 0));
    Video.WritePalette(1, SNES_RGB(31, 0, 0));
    Video.UploadVram(Bg1CharacterWordAddress, SuperNintendoRedSquareScene::Tiles(),
                     SuperNintendoRedSquareScene::TileByteCount);
    Video.UploadVram(Bg1TilemapWordAddress, SuperNintendoRedSquareScene::TilemapEntries(),
                     SuperNintendoRedSquareScene::TilemapByteCount);
    Video.EnableVBlankInterrupt();
    Video.ScreenOn();
    for (;;) {
        Video.WaitForVBlank();
    }
}

} // namespace helengine::snes
```

- [ ] **Step 5: Build in the container**

Run: `docker run --rm -v "$(pwd -W):/workspace" -w /workspace helengine-snes-toolchain make 2>&1 | tail -c 3000`

Expected: no warnings; validator passes. If clang reports the constexpr evaluation exceeded its step limit, add `-fconstexpr-steps=2000000` to `CXXFLAGS` in the Makefile.

- [ ] **Step 6: Run the emulator check to see it pass**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check_in_emulator.ps1; echo "exit=$?"`

Expected: `FRAME_COUNTER_ADDRESS=0x0...` non-zero, `RESULT=pass (...)`, `exit=0`. If the result is 3, dump VRAM from MesenCE's debugger or check `REG_BG12NBA` and the tile plane bytes; if it is 4, the NMI never fired: confirm `nmi` appears in the map at a ROM address and that `REG_NMITIMEN` is written after `RDNMI` is read.

- [ ] **Step 7: Confirm the pass is deterministic**

Run: `for i in 1 2 3; do powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check_in_emulator.ps1 | tail -1; done`

Expected: three `RESULT=pass` lines.

- [ ] **Step 8: Commit**

```bash
git add src/platform/snes/SuperNintendoRedSquareScene.hpp src/platform/snes/SuperNintendoRedSquareScene.cpp src/platform/snes/SuperNintendoBootHost.hpp src/platform/snes/SuperNintendoBootHost.cpp
git commit -m "Draw a centred red square on BG1 and idle on the VBlank NMI

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Build and launch scripts, notices and README

**Files:**
- Create: `scripts/build.ps1`, `scripts/launch_in_emulator.ps1`, `README.md`, `THIRD_PARTY_NOTICES.md`
- Modify: `docs/superpowers/specs/2026-09-17-snes-red-square-boot-design.md` (one sentence: the build runs in the toolchain image directly; there is no separate build image)

**Interfaces:**
- Consumes: image `helengine-snes-toolchain`, `Makefile`, `tools/validate_rom.py`, `dependencies.json`.
- Produces: `scripts/build.ps1 [-Clean]` writing `build/build-record.json`; `scripts/launch_in_emulator.ps1 -ArtifactPath <rom> [-EmulatorPath <exe>] [-Visible]`.

- [ ] **Step 1: Write `scripts/build.ps1`**

```powershell
[CmdletBinding()]
param(
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$image = 'helengine-snes-toolchain'
$buildPath = Join-Path $root 'build'
$romPath = Join-Path $root 'helengine_snes.sfc'
$elfPath = Join-Path $buildPath 'helengine_snes.elf'
$mapPath = Join-Path $buildPath 'helengine_snes.map'
$manifestPath = Join-Path $root 'dependencies.json'

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if (-not (Test-Path -LiteralPath (Join-Path $root ".deps\$($manifest.toolchain.package.fileName)"))) {
    throw 'Pinned toolchain package is missing. Run scripts/setup-toolchain.ps1 first.'
}
& docker image inspect $image --format '{{.Id}}' | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Docker image '$image' is missing. Run scripts/setup-toolchain.ps1 first." }

$makePrefix = @('run', '--rm', '-v', "${root}:/workspace", '-w', '/workspace', $image, 'make')
if ($Clean) {
    & docker @($makePrefix + @('clean'))
    if ($LASTEXITCODE -ne 0) { throw 'SNES clean failed.' }
}
& docker @makePrefix
if ($LASTEXITCODE -ne 0) { throw 'SNES ROM build failed.' }

foreach ($path in @($romPath, $elfPath, $mapPath)) {
    if (-not (Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).Length -le 0) {
        throw "Expected non-empty build artifact is missing: $path"
    }
}

& python (Join-Path $root 'tools\validate_rom.py') $romPath
if ($LASTEXITCODE -ne 0) { throw 'ROM validation failed on the host.' }

$hash = (Get-FileHash -LiteralPath $romPath -Algorithm SHA256).Hash.ToLowerInvariant()
$toolchainId = (& docker image inspect $image --format '{{.Id}}').Trim()
$record = [ordered]@{
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    command = "docker run ... make$(if ($Clean) { ' clean && make' })"
    rom = [ordered]@{ path = 'helengine_snes.sfc'; sha256 = $hash; bytes = (Get-Item -LiteralPath $romPath).Length }
    elf = [ordered]@{ path = 'build/helengine_snes.elf'; bytes = (Get-Item -LiteralPath $elfPath).Length }
    map = [ordered]@{ path = 'build/helengine_snes.map'; bytes = (Get-Item -LiteralPath $mapPath).Length }
    docker = [ordered]@{ toolchainImage = $toolchainId }
    dependencies = $manifest.toolchain
    video = [ordered]@{ mode = 1; layers = 'BG1'; resolution = '256x224'; cartridge = 'LoROM SlowROM 32 KiB' }
}
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $buildPath 'build-record.json') -Encoding utf8
Write-Output "ROM SHA-256: $hash"
```

- [ ] **Step 2: Write `scripts/launch_in_emulator.ps1`**

```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ArtifactPath,
    [string]$EmulatorPath = 'C:\dev\helworks\emus\Mesen_2.2.1_Windows\Mesen.exe',
    [switch]$Visible
)

$ErrorActionPreference = 'Stop'
$artifact = (Resolve-Path -LiteralPath $ArtifactPath).Path
if ((Get-Item -LiteralPath $artifact).Length -le 0) { throw "ROM artifact is empty: $artifact" }
if ([System.IO.Path]::GetExtension($artifact) -ine '.sfc') { throw "Expected a .sfc artifact: $artifact" }

$emulator = (Resolve-Path -LiteralPath $EmulatorPath).Path
if (-not (Test-Path -LiteralPath $emulator -PathType Leaf)) { throw "Emulator executable does not exist: $emulator" }

# Both MesenCE and ares take the ROM path as their positional argument.
$windowStyle = if ($Visible) { 'Normal' } else { 'Minimized' }
Start-Process -FilePath $emulator -ArgumentList @("`"$artifact`"") -WindowStyle $windowStyle
Write-Output "EMULATOR=$emulator"
Write-Output "ARTIFACT=$artifact"
```

- [ ] **Step 3: Write `THIRD_PARTY_NOTICES.md`**

```markdown
# Third-party notices

## llvm-mos-65816 SNES platform runtime

The ROM links the SNES platform runtime from the llvm-mos-65816 project
(`crt0`, cartridge header, link script, `libc.a` runtime pieces such as the
`.data` copy, `.bss` clear and far memory helpers). Those sources are
licensed under the Apache License 2.0 with LLVM Exceptions, following the
llvm-mos-sdk licence.

- Project: https://github.com/wbniv/llvm-mos-65816
- Upstream SDK: https://github.com/llvm-mos/llvm-mos-sdk
- Licence text: https://llvm.org/LICENSE.txt

The compiler itself, MesenCE and ares are build and test tools. They are
not redistributed with, or linked into, the ROM.
```

- [ ] **Step 4: Write `README.md`**

```markdown
# Helengine Super Nintendo Host

Super Nintendo platform host for Helengine. Current milestone: a diagnostic
ROM that boots to a centred red square on a black background, built with a
pinned llvm-mos-65816 C++ toolchain inside Docker.

Design: `docs/superpowers/specs/2026-09-17-snes-red-square-boot-design.md`.
Background reading: `docs/SuperNintendoDevelopment.md`, `docs/super-nintendo-cpp.md`.

## One-time setup

Requires Docker Desktop and PowerShell.

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
```

- [ ] **Step 5: Fix the spec sentence about the build image**

In `docs/superpowers/specs/2026-09-17-snes-red-square-boot-design.md`, replace

```
`scripts/build.ps1` builds the `helengine-snes-build` image from the Dockerfile,
runs `make` in the container with the repository mounted at `/workspace`,
```

with

```
`scripts/build.ps1` runs `make` in the `helengine-snes-toolchain` container
with the repository mounted at `/workspace`,
```

- [ ] **Step 6: Run a clean build through the script**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Clean 2>&1 | tail -c 3000`

Expected: make output, `validate_rom: ... is a valid 32768-byte LoROM image`, `ROM SHA-256: ...`. Then `cat build/build-record.json | head -c 1500` shows the record.

- [ ] **Step 7: Run the check and the host tests once more**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check_in_emulator.ps1 | tail -1; python -m unittest discover -s tools/tests -t . 2>&1 | tail -3`

Expected: `RESULT=pass (...)` and `OK`.

- [ ] **Step 8: Cross-check in ares by hand**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/launch_in_emulator.ps1 -ArtifactPath helengine_snes.sfc -Visible -EmulatorPath C:\dev\helworks\emus\ares-v148-windows-x64\ares-v148\ares.exe`

Expected: ares opens showing a red square on black. Report what was seen; this step is the human acceptance and is not automated. Close ares afterwards.

- [ ] **Step 9: Confirm a rebuild is byte-identical**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Clean | tail -1; powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Clean | tail -1`

Expected: the same `ROM SHA-256` twice.

- [ ] **Step 10: Commit**

```bash
git add scripts/build.ps1 scripts/launch_in_emulator.ps1 README.md THIRD_PARTY_NOTICES.md docs/superpowers/specs/2026-09-17-snes-red-square-boot-design.md
git commit -m "Add build and launch scripts, README and third-party notices

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Self-review notes

- Spec coverage: toolchain pinning (Task 1), build and finalize (Tasks 2, 4), validation (Task 3), ROM behaviour steps 1 to 8 (Tasks 6, 7), source layout (Tasks 4, 6, 7), emulators and portable settings (Task 5, README), automated acceptance including the NMI proof (Tasks 5, 7), human look and ares cross-check (Task 8), error codes and deterministic rebuild (Tasks 7, 8), notices (Task 8).
- The spec names `build/helengine_snes.elf`; the Makefile renames the SDK's `.elf` sidecar to that path.
- The spec lists `scripts/build.ps1` as building a separate build image; Task 8 corrects the spec to the single toolchain image, which is all this milestone needs.
