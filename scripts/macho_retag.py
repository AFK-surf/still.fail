# Rewrites the platform of a Mach-O object's LC_BUILD_VERSION in place
# (macOS -> iOS simulator), for the prebuilt MoonBit runtime object.
import struct, sys
src, dst, platform, minos = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
b = bytearray(open(src, 'rb').read())
magic, cputype, sub, ftype, ncmds, sizecmds, flags, _ = struct.unpack_from('<IiiIIIII', b, 0)
assert magic == 0xFEEDFACF, hex(magic)
off = 32
maj, mn = (int(x) for x in minos.split('.'))
ver = (maj << 16) | (mn << 8)
done = 0
for _ in range(ncmds):
    cmd, size = struct.unpack_from('<II', b, off)
    if cmd == 0x32:  # LC_BUILD_VERSION: platform, minos, sdk
        struct.pack_into('<III', b, off + 8, platform, ver, ver)
        done += 1
    off += size
assert done, 'no LC_BUILD_VERSION'
open(dst, 'wb').write(b)
print('retagged', done)
