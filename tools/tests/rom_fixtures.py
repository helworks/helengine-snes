"""Synthetic LoROM images for the tool tests."""

ROM_SIZE = 0x8000
HEADER_OFFSET = 0x7FC0


def make_lorom_image(title=b"LLVM-MOS SNES        "):
    """Return a 32 KiB image with a plausible LoROM header, zeroed checksum fields and vectors inside ROM."""
    image = bytearray(ROM_SIZE)
    for offset in range(0, ROM_SIZE, 7):
        image[offset] = (offset * 31) & 0xFF
    image[HEADER_OFFSET:HEADER_OFFSET + 21] = title
    image[0x7FD5] = 0x20  # LoROM, SlowROM
    image[0x7FD6] = 0x00  # ROM only
    image[0x7FD7] = 0x05  # 32 KiB
    image[0x7FD8] = 0x00  # no SRAM
    image[0x7FD9] = 0x01  # North America
    image[0x7FDC:0x7FDE] = b"\xFF\xFF"  # complement placeholder
    image[0x7FDE:0x7FE0] = b"\x00\x00"  # checksum placeholder
    image[0x7FEA:0x7FEC] = (0x802B).to_bytes(2, "little")  # native NMI
    image[0x7FFC:0x7FFE] = (0x8000).to_bytes(2, "little")  # emulation RESET
    return image
