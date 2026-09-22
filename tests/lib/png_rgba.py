import struct
import zlib


def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def read_png_rgba(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos = 8
    idat = b""
    width = height = bitdepth = colortype = None
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        ctype = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        if ctype == b"IHDR":
            width, height, bitdepth, colortype = struct.unpack(">IIBB", chunk[:10])
        elif ctype == b"IDAT":
            idat += chunk
        pos += 8 + length + 4
    raw = zlib.decompress(idat)
    assert bitdepth == 8 and colortype == 6, "expected 8-bit RGBA PNG"
    bpp = 4
    stride = width * bpp + 1
    pixels = []
    prev = bytearray(width * bpp)
    for row in range(height):
        line = raw[row * stride:(row + 1) * stride]
        ftype = line[0]
        cur = bytearray(line[1:])
        for i in range(len(cur)):
            left = cur[i - bpp] if i >= bpp else 0
            up = prev[i]
            upleft = prev[i - bpp] if i >= bpp else 0
            if ftype == 0:
                pass
            elif ftype == 1:
                cur[i] = (cur[i] + left) & 0xFF
            elif ftype == 2:
                cur[i] = (cur[i] + up) & 0xFF
            elif ftype == 3:
                cur[i] = (cur[i] + (left + up) // 2) & 0xFF
            elif ftype == 4:
                cur[i] = (cur[i] + _paeth(left, up, upleft)) & 0xFF
            else:
                raise AssertionError("unsupported filter %d" % ftype)
        for i in range(0, len(cur), bpp):
            pixels.append(tuple(cur[i:i + bpp]))
        prev = cur
    return pixels, width, height
