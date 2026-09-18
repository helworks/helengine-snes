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
