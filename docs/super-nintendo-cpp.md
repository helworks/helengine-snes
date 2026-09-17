# Super Nintendo C++ Development

Yes — **you can use C++ for Super Nintendo today**, but it is not as turnkey as C.

## CPU and Modern Compiler Support

The SNES CPU is the **WDC 65C816**.

A particularly interesting modern option is **LLVM-MOS**. Its Clang backend supports the 65816 through:

```bash
-mcpu=mosw65816
```

LLVM-MOS supports a substantial freestanding C++ subset, including:

- Classes and structs
- Templates
- Virtual functions
- `new` / `delete`
- RTTI
- Static constructors and destructors
- Namespaces
- References
- `constexpr`
- Inline functions

C++ exceptions are not supported.

Reference:

- https://www.llvm-mos.org/wiki/C_compiler

## The Main Problem: SNES Platform Support

The compiler itself is no longer the biggest obstacle.

The official LLVM-MOS SDK supports several 6502-family systems, including platforms such as:

- NES
- Commodore 64
- Atari systems
- PC Engine

However, it does **not currently provide a complete ready-made SNES platform definition**.

That means a SNES LLVM-MOS environment needs platform-specific infrastructure such as:

- Startup/reset code
- ROM header generation
- Interrupt vectors
- Linker layout
- LoROM / HiROM mapping
- PPU register definitions
- DMA / HDMA support
- VRAM management
- CGRAM management
- OAM management
- NMI / IRQ handlers
- SPC700 communication
- Runtime initialization

Reference:

- https://github.com/llvm-mos/llvm-mos-sdk

## Existing SNES Tooling: PVSnesLib

The established SNES homebrew framework **PVSnesLib** primarily targets C and assembly.

Its toolchain uses approximately:

```text
C
 ↓
816-tcc
 ↓
optimized assembly
 ↓
WLA-65816
 ↓
SNES ROM
```

PVSnesLib provides mature SNES-specific functionality such as:

- Graphics
- Sprites
- Input
- Audio
- DMA
- Video initialization
- Console startup

Reference:

- https://github.com/alekmaul/pvsneslib

## Possible Helengine Architecture

For Helengine, a modern C++ SNES backend could look like this:

```text
Helengine C++ game code
        │
        ▼
     LLVM-MOS
    clang++ / 65816
        │
        ▼
 SNES platform/runtime
 ├── startup/reset vector
 ├── LoROM/HiROM linker script
 ├── IRQ/NMI handlers
 ├── DMA / HDMA
 ├── PPU abstraction
 ├── VRAM/CGRAM/OAM
 └── SPC700 communication
        │
        ▼
       .sfc
```

This would allow Helengine's higher-level API to remain relatively consistent with other platforms while keeping SNES-specific hardware code isolated inside the backend.

## Example C++

Basic engine code can remain reasonably idiomatic:

```cpp
struct Sprite {
    int16_t x;
    int16_t y;
    uint16_t tile;
};

void update(Sprite& sprite)
{
    sprite.x += 1;
}
```

There is nothing inherently problematic about code like this on the 65816.

The important consideration is what abstractions generate at the machine-code level.

## Recommended C++ Subset

### Good Choices

These are generally good candidates for SNES engine code:

```text
struct
class
constexpr
templates
references
inline
enum class
namespaces
```

Small compile-time abstractions can make engine code considerably cleaner without necessarily introducing runtime overhead.

### Use Carefully

These features can work, but their generated code and memory costs should be inspected:

```text
virtual functions
new/delete
RTTI
```

Virtual dispatch is possible, but function-pointer tables and indirect calls may be relatively expensive on a 65C816.

Dynamic allocation should ideally be avoided during gameplay.

### Avoid

Desktop-oriented C++ facilities are usually inappropriate:

```text
exceptions
iostream
std::vector
std::string
heavy STL usage
large inheritance trees
frequent runtime allocation
```

The goal should be **freestanding embedded C++**, not desktop C++.

## Hardware Constraints

The SNES has only **128 KiB of main WRAM**.

The 65C816 generally operates at roughly **2.68–3.58 MHz**, depending on the memory region being accessed.

Because of this, abstraction costs matter significantly more than they do on later consoles.

Things to watch carefully include:

- Function-call overhead
- Indirect calls
- Bank transitions
- 16-bit vs 8-bit accumulator/index state
- Memory copying
- Heap allocation
- Large object graphs
- Runtime type information
- Unnecessary temporary objects

C++ itself is not necessarily slow.

The danger is using language features whose generated code is poorly suited to the 65C816 architecture.

## LLVM-MOS 65816 Work

There is also newer LLVM-MOS-derived work targeting the 65816 and SNES specifically.

One project provides a C-oriented SNES/65816 compiler environment and runtime infrastructure:

- https://indri.studio/apps/llvm-mos-65816/

Although currently presented primarily as a C toolchain, the underlying LLVM-MOS infrastructure makes it potentially useful as a starting point for a proper SNES `clang++` environment.

Instead of building every SNES runtime component from scratch, Helengine could potentially reuse or adapt parts of this work.

## Recommended Strategy for Helengine

For Helengine, the ideal model would be:

> **Use modern C++ syntax and compile-time abstractions, while treating the SNES as a freestanding embedded system.**

A sensible language target would resemble **C++17-style code**, but without assuming the presence of a full modern standard library.

LLVM-MOS advertises broad C++11 freestanding compatibility, with additional newer language features also working.

A good engine architecture would separate:

```text
Game / Engine C++
        │
        ▼
Helengine Platform API
        │
        ▼
SNES backend
        │
        ├── PPU
        ├── DMA
        ├── HDMA
        ├── OAM
        ├── VRAM
        ├── CGRAM
        ├── Input
        ├── SPC700
        └── Cartridge / memory mapping
```

Game code should ideally never need to know whether these systems are implemented in:

- C++
- C
- 65816 assembly

The SNES backend can use assembly selectively for the critical paths.

## Comparison With Other Helengine Targets

| Console | C++ Situation |
|---|---|
| PlayStation 1 | ✅ Very reasonable |
| Nintendo 64 | ✅ Very reasonable |
| Dreamcast | ✅ Excellent |
| **Super Nintendo** | 🟡 Possible; modern tooling is emerging |
| NES | 🟡 LLVM-MOS C++ works surprisingly well |
| Game Boy | 🟡 Possible, but awkward |

## Conclusion

C++ on the SNES is now technically realistic.

The difficult problem is no longer:

```text
C++ → 65816
```

LLVM-MOS has largely solved that part.

The missing piece is closer to:

```text
C++ → good SNES SDK/runtime → production-quality .sfc
```

For Helengine, that creates an interesting opportunity: build a thin SNES runtime around LLVM-MOS and expose the platform through the same engine abstractions used by the other console backends.

The best approach is likely a hybrid:

```text
C++          engine architecture / gameplay
C or C++     hardware abstraction
Assembly     extremely hot paths / interrupt code
```

That gives Helengine modern source organization while still respecting the limitations of the SNES hardware.
