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
