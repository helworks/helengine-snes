#pragma once

#include <stdint.h>

namespace helengine::snes {

/// VRAM word address of the BG1 32x32 tilemap (2 KiB).
constexpr uint16_t Bg1TilemapWordAddress = 0x0000;

/// VRAM word address of the BG1 4bpp character data.
constexpr uint16_t Bg1CharacterWordAddress = 0x1000;

/// Thin PPU backend for the boot ROM: register setup, palette writes, VRAM
/// uploads over DMA channel 0, and VBlank synchronisation through the NMI.
/// Every write here must happen while the screen is force-blanked or during
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
    /// byteCount must be even and non-zero; zero is a no-op.
    void UploadVram(uint16_t wordAddress, const void* source, uint16_t byteCount);

    /// Enables the VBlank NMI so the frame counter starts advancing.
    void EnableVBlankInterrupt();

    /// Releases force-blank at full brightness.
    void ScreenOn();

    /// Blocks until the NMI handler has counted one more frame.
    /// Precondition: EnableVBlankInterrupt() has been called; otherwise this
    /// never returns. Do not use the SDK's snes_wait_vblank() alongside this
    /// class: the NMI handler read-clears RDNMI, so that helper never sees
    /// the flag.
    void WaitForVBlank();

    /// Number of VBlank interrupts seen since boot, wrapping at 16 bits.
    static uint16_t FrameCount();
};

} // namespace helengine::snes
