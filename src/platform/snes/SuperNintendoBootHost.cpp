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
