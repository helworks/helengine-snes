"""Static checks on a finished headerless LoROM image.

Exit code 0 when every check passes, 1 otherwise, with one line per problem.
"""

import argparse
import sys

BANK_SIZE = 0x8000
HEADER_OFFSET = 0x7FC0
TITLE_LENGTH = 21
MAP_MODE_OFFSET = 0x7FD5
CHIPSET_OFFSET = 0x7FD6
ROM_SIZE_OFFSET = 0x7FD7
COMPLEMENT_OFFSET = 0x7FDC
CHECKSUM_OFFSET = 0x7FDE
NATIVE_NMI_VECTOR_OFFSET = 0x7FEA
EMULATION_RESET_VECTOR_OFFSET = 0x7FFC
DEFAULT_TITLE = "HELENGINE SNES"


def _word(image, offset):
    return int.from_bytes(image[offset:offset + 2], "little")


def validate(image, expected_title=DEFAULT_TITLE):
    """Return a list of problem descriptions; an empty list means the image is valid."""
    problems = []
    size = len(image)
    if size % BANK_SIZE == 512:
        problems.append(f"image has a 512-byte copier header (size {size})")
        return problems
    if size < BANK_SIZE or size % BANK_SIZE != 0:
        problems.append(f"image size {size} is not a multiple of {BANK_SIZE}")
        return problems

    title = image[HEADER_OFFSET:HEADER_OFFSET + TITLE_LENGTH]
    expected = expected_title.encode("ascii").ljust(TITLE_LENGTH, b" ")
    if title != expected:
        problems.append(f"title {title!r} does not match expected {expected!r}")

    map_mode = image[MAP_MODE_OFFSET]
    if map_mode & 0x0F != 0x00 or map_mode & 0x20 != 0x20:
        problems.append(f"map mode 0x{map_mode:02X} is not LoROM")

    chipset = image[CHIPSET_OFFSET]
    if chipset != 0x00:
        problems.append(f"chipset 0x{chipset:02X} is not ROM only")

    declared_size = 1024 << image[ROM_SIZE_OFFSET]
    if declared_size != size:
        problems.append(f"ROM size byte declares {declared_size} bytes but the image is {size} bytes")

    complement = _word(image, COMPLEMENT_OFFSET)
    checksum = _word(image, CHECKSUM_OFFSET)
    if complement ^ checksum != 0xFFFF:
        problems.append(f"checksum 0x{checksum:04X} and complement 0x{complement:04X} do not XOR to 0xFFFF")
    scratch = bytearray(image)
    scratch[COMPLEMENT_OFFSET:COMPLEMENT_OFFSET + 2] = b"\xFF\xFF"
    scratch[CHECKSUM_OFFSET:CHECKSUM_OFFSET + 2] = b"\x00\x00"
    computed = sum(scratch) & 0xFFFF
    if computed != checksum:
        problems.append(f"checksum 0x{checksum:04X} does not match computed 0x{computed:04X}")

    for name, offset in (("RESET", EMULATION_RESET_VECTOR_OFFSET), ("NMI", NATIVE_NMI_VECTOR_OFFSET)):
        vector = _word(image, offset)
        if not 0x8000 <= vector <= 0xFFFF:
            problems.append(f"{name} vector 0x{vector:04X} points outside ROM")
    return problems


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--title", default=DEFAULT_TITLE)
    parser.add_argument("rom")
    args = parser.parse_args(argv)
    with open(args.rom, "rb") as handle:
        image = handle.read()
    problems = validate(image, args.title)
    for problem in problems:
        print(f"validate_rom: {problem}")
    if problems:
        return 1
    print(f"validate_rom: {args.rom} is a valid {len(image)}-byte LoROM image")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
