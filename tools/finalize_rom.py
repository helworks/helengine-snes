"""Finalize a raw LoROM image emitted by the SDK linker.

Writes the cartridge title into the internal header and computes the
checksum/complement pair. Only power-of-two image sizes are supported,
which is all the SDK's LoROM link script produces.
"""

import argparse
import sys

HEADER_OFFSET = 0x7FC0
TITLE_LENGTH = 21
COMPLEMENT_OFFSET = 0x7FDC
CHECKSUM_OFFSET = 0x7FDE
MIN_SIZE = 0x8000


def finalize(image, title):
    """Return a new image with the title and checksum pair written."""
    size = len(image)
    if size < MIN_SIZE or (size & (size - 1)) != 0:
        raise ValueError(f"image size {size} is not a power of two of at least {MIN_SIZE} bytes")
    encoded = title.encode("ascii")
    if len(encoded) > TITLE_LENGTH:
        raise ValueError(f"title {title!r} is longer than {TITLE_LENGTH} bytes")
    result = bytearray(image)
    result[HEADER_OFFSET:HEADER_OFFSET + TITLE_LENGTH] = encoded.ljust(TITLE_LENGTH, b" ")
    result[COMPLEMENT_OFFSET:COMPLEMENT_OFFSET + 2] = b"\xFF\xFF"
    result[CHECKSUM_OFFSET:CHECKSUM_OFFSET + 2] = b"\x00\x00"
    checksum = sum(result) & 0xFFFF
    complement = checksum ^ 0xFFFF
    result[COMPLEMENT_OFFSET:COMPLEMENT_OFFSET + 2] = complement.to_bytes(2, "little")
    result[CHECKSUM_OFFSET:CHECKSUM_OFFSET + 2] = checksum.to_bytes(2, "little")
    return bytes(result)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--title", required=True)
    parser.add_argument("input")
    parser.add_argument("output")
    args = parser.parse_args(argv)
    with open(args.input, "rb") as handle:
        image = handle.read()
    result = finalize(image, args.title)
    with open(args.output, "wb") as handle:
        handle.write(result)
    checksum = int.from_bytes(result[CHECKSUM_OFFSET:CHECKSUM_OFFSET + 2], "little")
    print(f"finalized {args.output}: {len(result)} bytes, checksum 0x{checksum:04X}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
