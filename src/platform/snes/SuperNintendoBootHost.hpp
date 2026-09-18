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
