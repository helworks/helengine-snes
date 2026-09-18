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
