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
