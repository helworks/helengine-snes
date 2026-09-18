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
    // BG1HOFS/BG1VOFS are write-twice ports (low byte, then high bits); the
    // single write in snes_ppu_reset_blank leaves the power-on latch in the
    // low bits, so write each twice to pin the scroll at 0.
    REG_BG1HOFS = 0; REG_BG1HOFS = 0;
    REG_BG1VOFS = 0; REG_BG1VOFS = 0;
    REG_HDMAEN = 0;
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
    if (byteCount == 0) { return; }
    REG_VMAIN = VMAIN_INC_HIGH_1;
    REG_VMADD = wordAddress;
    REG_DMAP0 = DMAP_TO_PPU | DMAP_ADDR_INC | DMAP_UNIT_2;
    REG_BBAD0 = BBAD_VMDATA;
    // Near pointers are bank 0 on the `snes` platform: ROM at $8000-$FFFF and
    // low WRAM at $0000-$1FFF, both reachable by DMA from bank 0. Far
    // platforms carry the bank in bits 16-23 of the pointer, so take the DMA
    // source bank from the pointer itself rather than hardcoding it.
    const uint32_t address = static_cast<uint32_t>(reinterpret_cast<uintptr_t>(source));
    REG_A1T0L = static_cast<uint8_t>(address);
    REG_A1T0H = static_cast<uint8_t>(address >> 8);
    REG_A1B0 = static_cast<uint8_t>(address >> 16);
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
