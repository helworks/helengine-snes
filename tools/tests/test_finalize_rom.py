import unittest

from tools import finalize_rom
from tools.tests.rom_fixtures import make_lorom_image


class FinalizeRomTests(unittest.TestCase):
    def test_title_is_written_space_padded(self):
        result = finalize_rom.finalize(bytes(make_lorom_image()), "HELENGINE SNES")
        self.assertEqual(result[0x7FC0:0x7FD5], b"HELENGINE SNES       ")

    def test_checksum_pair_is_consistent_and_matches_sum(self):
        result = finalize_rom.finalize(bytes(make_lorom_image()), "HELENGINE SNES")
        complement = int.from_bytes(result[0x7FDC:0x7FDE], "little")
        checksum = int.from_bytes(result[0x7FDE:0x7FE0], "little")
        self.assertEqual(complement ^ checksum, 0xFFFF)
        scratch = bytearray(result)
        scratch[0x7FDC:0x7FDE] = b"\xFF\xFF"
        scratch[0x7FDE:0x7FE0] = b"\x00\x00"
        self.assertEqual(checksum, sum(scratch) & 0xFFFF)

    def test_finalize_is_idempotent(self):
        once = finalize_rom.finalize(bytes(make_lorom_image()), "HELENGINE SNES")
        twice = finalize_rom.finalize(once, "HELENGINE SNES")
        self.assertEqual(once, twice)

    def test_rejects_title_longer_than_21_bytes(self):
        with self.assertRaises(ValueError):
            finalize_rom.finalize(bytes(make_lorom_image()), "THIS TITLE IS FAR TOO LONG")

    def test_rejects_non_power_of_two_size(self):
        with self.assertRaises(ValueError):
            finalize_rom.finalize(bytes(make_lorom_image()) + b"\x00" * 100, "HELENGINE SNES")


if __name__ == "__main__":
    unittest.main()
