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
