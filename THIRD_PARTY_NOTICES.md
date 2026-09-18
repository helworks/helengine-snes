# Third-party notices

## llvm-mos-65816 SNES platform runtime

The ROM links the SNES platform runtime from the llvm-mos-65816 project
(`crt0`, cartridge header, link script, `libc.a` runtime pieces such as the
`.data` copy, `.bss` clear and far memory helpers). Those sources are
licensed under the Apache License 2.0 with LLVM Exceptions, following the
llvm-mos-sdk licence.

- Project: https://github.com/wbniv/llvm-mos-65816
- Upstream SDK: https://github.com/llvm-mos/llvm-mos-sdk
- Licence text: https://llvm.org/LICENSE.txt

The compiler itself, MesenCE and ares are build and test tools. They are
not redistributed with, or linked into, the ROM.
