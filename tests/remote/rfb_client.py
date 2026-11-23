#!/usr/bin/env python3
"""An RFB (VNC) client for tests of the image's remote display (RfbServer; RFC 6143), standard library only.

Speaks RFB 3.3 (the server picks the security type, as macOS Screen Sharing does) and 3.8 (TigerVNC), with VNC
authentication (DES, written here: the standard library has none) or VeNCrypt-Plain (the session token), decodes
FramebufferUpdates of Raw, CopyRect and ZRLE (one zlib stream for the session; CPIXELs by the viewers' rule) and the
pseudo-encodings Cursor, DesktopSize and LastRect, in any true-colour pixel format it asks for (SetPixelFormat), into a
BGRX framebuffer, and sends key, pointer and cut-text events. SCREEN_SHARING and TIGERVNC are what those viewers send.

  rfb_client.py --port N [--host H] [--version 3.3|3.8] [--auth vnc|vencrypt|none] [--secret-file F]
                [--encodings zrle,copyrect,cursor,desktopsize,lastrect] [--pixel-format 32/32/le/255,255,255/16,8,0]
                [--save out.ppm] [--compare shot.png]
connects, takes a full update and saves it (PPM) or compares it pixel for pixel with a PNG (exit 1 on a difference).
tests/remote/rfb_test.sh drives the rest through the library (RfbClient).
"""
import argparse
import socket
import struct
import sys
import time
import zlib

# ---------------------------------------------------------------- DES (FIPS 46-3), for VNC authentication

_IP = [58, 50, 42, 34, 26, 18, 10, 2, 60, 52, 44, 36, 28, 20, 12, 4, 62, 54, 46, 38, 30, 22, 14, 6, 64, 56, 48, 40, 32,
       24, 16, 8, 57, 49, 41, 33, 25, 17, 9, 1, 59, 51, 43, 35, 27, 19, 11, 3, 61, 53, 45, 37, 29, 21, 13, 5, 63, 55,
       47, 39, 31, 23, 15, 7]
_FP = [40, 8, 48, 16, 56, 24, 64, 32, 39, 7, 47, 15, 55, 23, 63, 31, 38, 6, 46, 14, 54, 22, 62, 30, 37, 5, 45, 13, 53,
       21, 61, 29, 36, 4, 44, 12, 52, 20, 60, 28, 35, 3, 43, 11, 51, 19, 59, 27, 34, 2, 42, 10, 50, 18, 58, 26, 33, 1,
       41, 9, 49, 17, 57, 25]
_E = [32, 1, 2, 3, 4, 5, 4, 5, 6, 7, 8, 9, 8, 9, 10, 11, 12, 13, 12, 13, 14, 15, 16, 17, 16, 17, 18, 19, 20, 21, 20, 21,
      22, 23, 24, 25, 24, 25, 26, 27, 28, 29, 28, 29, 30, 31, 32, 1]
_P = [16, 7, 20, 21, 29, 12, 28, 17, 1, 15, 23, 26, 5, 18, 31, 10, 2, 8, 24, 14, 32, 27, 3, 9, 19, 13, 30, 6, 22, 11, 4,
      25]
_PC1 = [57, 49, 41, 33, 25, 17, 9, 1, 58, 50, 42, 34, 26, 18, 10, 2, 59, 51, 43, 35, 27, 19, 11, 3, 60, 52, 44, 36, 63,
        55, 47, 39, 31, 23, 15, 7, 62, 54, 46, 38, 30, 22, 14, 6, 61, 53, 45, 37, 29, 21, 13, 5, 28, 20, 12, 4]
_PC2 = [14, 17, 11, 24, 1, 5, 3, 28, 15, 6, 21, 10, 23, 19, 12, 4, 26, 8, 16, 7, 27, 20, 13, 2, 41, 52, 31, 37, 47, 55,
        30, 40, 51, 45, 33, 48, 44, 49, 39, 56, 34, 53, 46, 42, 50, 36, 29, 32]
_SHIFTS = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1]
_S = [
    [14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7, 0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8,
     4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0, 15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13],
    [15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10, 3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5,
     0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15, 13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9],
    [10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8, 13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1,
     13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7, 1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12],
    [7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15, 13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9,
     10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4, 3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14],
    [2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9, 14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6,
     4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14, 11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3],
    [12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11, 10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8,
     9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6, 4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13],
    [4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1, 13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6,
     1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2, 6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12],
    [13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7, 1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2,
     7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8, 2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11]]


def _bits(data):
    return [(b >> (7 - i)) & 1 for b in data for i in range(8)]


def _permute(bits, table):
    return [bits[i - 1] for i in table]


def des_encrypt(key, block):
    """One 8-byte block under an 8-byte key."""
    cd = _permute(_bits(key), _PC1)
    c, d = cd[:28], cd[28:]
    subkeys = []
    for n in _SHIFTS:
        c, d = c[n:] + c[:n], d[n:] + d[:n]
        subkeys.append(_permute(c + d, _PC2))
    b = _permute(_bits(block), _IP)
    left, right = b[:32], b[32:]
    for k in subkeys:
        x = [a ^ b for a, b in zip(_permute(right, _E), k)]
        out = []
        for s in range(8):
            v = x[s * 6:s * 6 + 6]
            row, col = v[0] * 2 + v[5], v[1] * 8 + v[2] * 4 + v[3] * 2 + v[4]
            n = _S[s][row * 16 + col]
            out += [(n >> 3) & 1, (n >> 2) & 1, (n >> 1) & 1, n & 1]
        f = _permute(out, _P)
        left, right = right, [a ^ b for a, b in zip(left, f)]
    bits = _permute(right + left, _FP)
    return bytes(int(''.join(map(str, bits[i:i + 8])), 2) for i in range(0, 64, 8))


def vnc_response(challenge, password):
    """VNC authentication's answer: the challenge under DES, its key the password's first 8 bytes each bit-reversed."""
    key = bytes(int('{:08b}'.format(b)[::-1], 2) for b in password.encode('latin-1')[:8].ljust(8, b'\0'))
    return des_encrypt(key, challenge[:8]) + des_encrypt(key, challenge[8:16])


# ---------------------------------------------------------------- PNG (the image's screenshots)

def read_png(path_or_bytes):
    """(width, height, RGBA bytes) of an 8-bit RGB, RGBA or palette PNG, not interlaced (a path or the bytes)."""
    if isinstance(path_or_bytes, bytes):
        data, path = path_or_bytes, 'PNG'
    else:
        with open(path_or_bytes, 'rb') as f:
            data, path = f.read(), path_or_bytes
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError(path + ': not a PNG')
    pos, idat, palette, alpha = 8, b'', None, b''
    while pos < len(data):
        n, kind = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        pos += 12 + n
        if kind == b'IHDR':
            w, h, depth, ctype, _, _, interlace = struct.unpack('>IIBBBBB', body)
            if depth != 8 or ctype not in (2, 3, 6) or interlace:
                raise ValueError(path + ': only 8-bit RGB(A) or palette, not interlaced')
        elif kind == b'PLTE':
            palette = body
        elif kind == b'tRNS':
            alpha = body
        elif kind == b'IDAT':
            idat += body
        elif kind == b'IEND':
            break
    raw = zlib.decompress(idat)
    bpp = {6: 4, 2: 3, 3: 1}[ctype]
    stride = w * bpp
    out = bytearray(w * h * 4)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        ft = raw[p]
        line = bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if ft == 1:
                line[i] = (line[i] + a) & 255
            elif ft == 2:
                line[i] = (line[i] + b) & 255
            elif ft == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif ft == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        prev = line
        if bpp == 4:
            out[y * w * 4:(y + 1) * w * 4] = line
        elif bpp == 1:
            for x in range(w):
                i = line[x]
                out[(y * w + x) * 4:(y * w + x) * 4 + 4] = palette[i * 3:i * 3 + 3] + bytes([alpha[i] if i < len(alpha) else 255])
        else:
            for x in range(w):
                out[(y * w + x) * 4:(y * w + x) * 4 + 4] = line[x * 3:x * 3 + 3] + b'\xff'
    return w, h, bytes(out)


# ---------------------------------------------------------------- RFB

ENCODINGS = {'raw': 0, 'copyrect': 1, 'zrle': 16, 'cursor': -239, 'desktopsize': -223, 'lastrect': -224}


class PixelFormat:
    """An RFB pixel format (RFC 6143, 7.4), true colour, and how its pixels become BGRX."""

    def __init__(self, bpp=32, depth=24, big_endian=False, maxes=(255, 255, 255), shifts=(16, 8, 0), true_colour=True):
        self.bpp, self.depth, self.big_endian, self.true_colour = bpp, depth, big_endian, true_colour
        self.maxes, self.shifts = tuple(maxes), tuple(shifts)
        self.size = bpp // 8
        # each channel value as 8 bits, and what an 8-bit value comes back as through this format (the server rounds)
        self.expand = [[(v * 255 + m // 2) // m for v in range(m + 1)] for m in self.maxes]
        self.round_trip = [bytes(e[(c * m + 127) // 255] for c in range(256)) for e, m in zip(self.expand, self.maxes)]
        self.lossless = all(m == 255 for m in self.maxes)

    @classmethod
    def from_bytes(cls, b):
        """The 16 bytes of ServerInit's or SetPixelFormat's format."""
        bpp, depth, be, tc, rm, gm, bm, rs, gs, bs = struct.unpack('>BBBBHHHBBBxxx', b)
        return cls(bpp, depth, bool(be), (rm, gm, bm), (rs, gs, bs), bool(tc))

    @classmethod
    def parse(cls, text):
        """'bpp/depth/le|be/rmax,gmax,bmax/rshift,gshift,bshift', e.g. Screen Sharing's 32/32/le/255,255,255/16,8,0."""
        bpp, depth, order, maxes, shifts = text.split('/')
        return cls(int(bpp), int(depth), order == 'be', [int(m) for m in maxes.split(',')],
                   [int(s) for s in shifts.split(',')])

    def __repr__(self):
        return '%d/%d/%s/%s/%s' % (self.bpp, self.depth, 'be' if self.big_endian else 'le',
                                    ','.join(map(str, self.maxes)), ','.join(map(str, self.shifts)))

    def message(self):
        """SetPixelFormat."""
        return struct.pack('>BxxxBBBBHHHBBBxxx', 0, self.bpp, self.depth, 1 if self.big_endian else 0,
                           1 if self.true_colour else 0, *self.maxes, *self.shifts)

    def cpixel(self):
        """ZRLE's CPIXEL as (size, where its bytes start in the pixel, in wire order), by the viewers' rule (TigerVNC's,
        libvncclient's, macOS Screen Sharing's): a 32-bit true-colour pixel whose channels all fit in its least
        significant three bytes, or else its most significant three, travels as those three bytes, whatever its depth
        (RFC 6143 also asks for depth <= 24, but Screen Sharing asks for depth 32 and decodes 3 bytes); else the whole
        pixel."""
        if self.bpp != 32 or not self.true_colour:
            return self.size, 0
        used = 0
        for m, s in zip(self.maxes, self.shifts):
            used |= m << s
        if used < 1 << 24:
            return 3, 1 if self.big_endian else 0
        if used & 0xff == 0:
            return 3, 0 if self.big_endian else 1
        return 4, 0

    def _byte_of(self, shift):
        """The byte (wire order) of a 32-bit pixel that is the channel at shift, if a whole byte."""
        if shift % 8:
            return None
        return 3 - shift // 8 if self.big_endian else shift // 8

    def to_bgrx(self, data):
        """data's pixels as BGRX (X: the server's byte in its own format, else 255)."""
        n = len(data) // self.size
        if self.lossless and self.bpp == 32:
            r, g, b = (self._byte_of(s) for s in self.shifts)
            if (r, g, b) == (2, 1, 0):
                return bytes(data)
            if None not in (r, g, b):
                out = bytearray(b'\xff' * (n * 4))
                out[0::4], out[1::4], out[2::4] = data[b::4], data[g::4], data[r::4]
                return bytes(out)
        out = bytearray(b'\xff' * (n * 4))
        order, sz = 'big' if self.big_endian else 'little', self.size
        (rm, gm, bm), (rs, gs, bs), (er, eg, eb) = self.maxes, self.shifts, self.expand
        for i in range(n):
            v = int.from_bytes(data[i * sz:i * sz + sz], order)
            o = i * 4
            out[o], out[o + 1], out[o + 2] = eb[(v >> bs) & bm], eg[(v >> gs) & gm], er[(v >> rs) & rm]
        return bytes(out)


NATIVE = PixelFormat()
# What the viewers send after ServerInit, as the probe logged them (the scope's "Confirmed with real viewers").
# macOS Screen Sharing: RFB 3.3, VNC authentication, shared; depth 32 BGRX; Apple's own encodings (1000-1200), which a
# server must ignore, around Zlib, ZRLE, Cursor and DesktopSize.
SCREEN_SHARING_FORMAT = PixelFormat(32, 32, False, (255, 255, 255), (16, 8, 0))
SCREEN_SHARING_ENCODINGS = [1011, 1002, 6, 16, -239, 1104, 1100, -223, 1101, 1105, 1107, 1109, 1110]
# TigerVNC: RFB 3.8, VNC authentication; its full-colour format; Tight, CopyRect, JPEG, ZRLE, Hextile, RRE, Raw,
# CompressLevel2, JPEGQuality8, then pseudo-encodings: CursorWithAlpha, VMwareCursor, Cursor, XCursor, DesktopSize,
# ExtendedDesktopSize, LastRect, ExtendedClipboard, ContinuousUpdates, Fence, QEMUExtendedKeyEvent, DesktopName,
# QEMULEDState, VMware LED state.
TIGERVNC_FORMAT = PixelFormat(32, 24, False, (255, 255, 255), (16, 8, 0))
TIGERVNC_ENCODINGS = [7, 1, 21, 16, 5, 2, 0, -254, -24, -314, 0x574d5664, -239, -240, -223, -308, -224, -1063131698,
                      -313, -312, -258, -307, -261, 0x574d5668]
# The keysyms of a Mac's Command and Option (the probe's logs, and the operator's Screen Sharing): Screen Sharing sends
# Command as Alt_L and Option as Meta_L; TigerVNC Command as Mode_switch and Option as Alt_L.
SCREEN_SHARING_COMMAND, SCREEN_SHARING_OPTION = 0xffe9, 0xffe7
TIGERVNC_COMMAND, TIGERVNC_OPTION = 0xff7e, 0xffe9


class RfbError(Exception):
    pass


class RfbClient:
    """One connection. fb is the framebuffer, width * height BGRX pixels. encodings_seen: every encoding the server
    sent a rectangle in. With decode False, rectangles are read (ZRLE's stream inflated) but not drawn."""

    def __init__(self, host, port, timeout=20):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.buf = b''
        self.width = self.height = 0
        self.fb = bytearray()
        self.name = ''
        self.version = None
        self.zlib = zlib.decompressobj()
        self.cursor = None
        self.cut_texts = []
        self.bells = 0
        self.last_rects = []
        self.updates = 0
        self.bytes_read = 0
        self.encodings_seen = set()
        self.decode = True
        self.use_format(NATIVE)

    # -- bytes
    def recv(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(max(65536, n - len(self.buf)))
            if not chunk:
                raise RfbError('the server closed the connection')
            self.bytes_read += len(chunk)
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def u8(self):
        return self.recv(1)[0]

    def u16(self):
        return struct.unpack('>H', self.recv(2))[0]

    def u32(self):
        return struct.unpack('>I', self.recv(4))[0]

    def reason(self):
        return self.recv(self.u32()).decode('latin-1')

    def send(self, data):
        self.sock.sendall(data)

    def close(self):
        self.sock.close()

    # -- handshake
    def handshake(self, version='3.8', auth='vencrypt', secret=None, shared=True):
        """Version, security (auth: vnc, vencrypt or none), ClientInit and ServerInit. Raises RfbError(reason)."""
        server = self.recv(12)
        if not server.startswith(b'RFB 003.'):
            raise RfbError('not an RFB server: %r' % server)
        self.version = version
        self.send(b'RFB 003.003\n' if version == '3.3' else b'RFB 003.008\n')
        want = {'none': 1, 'vnc': 2, 'vencrypt': 19}[auth]
        if version == '3.3':
            kind = self.u32()
            if kind == 0:
                raise RfbError(self.reason())
            if kind != want:
                raise RfbError('the server picked security type %d' % kind)
        else:
            n = self.u8()
            if n == 0:
                raise RfbError(self.reason())
            self.offered = list(self.recv(n))
            if want not in self.offered:
                raise RfbError('security type %d not offered: %r' % (want, self.offered))
            kind = want
            self.send(bytes([kind]))
        if kind == 2:
            self.send(vnc_response(self.recv(16), secret))
        elif kind == 19:
            if self.recv(2) != b'\x00\x02':
                raise RfbError('VeNCrypt: not version 0.2')
            self.send(b'\x00\x02')
            if self.u8() != 0:
                raise RfbError('VeNCrypt: version refused')
            subtypes = [self.u32() for _ in range(self.u8())]
            if 256 not in subtypes:
                raise RfbError('VeNCrypt: no Plain: %r' % subtypes)
            user, password = b'samaltak', secret.encode('latin-1')
            self.send(struct.pack('>III', 256, len(user), len(password)) + user + password)
        if kind != 1 or version == '3.8':
            if self.u32() != 0:
                raise RfbError(self.reason() if version == '3.8' else 'authentication failed')
        self.send(bytes([1 if shared else 0]))
        self.width, self.height = self.u16(), self.u16()
        self.server_format = self.recv(16)
        self.use_format(PixelFormat.from_bytes(self.server_format))
        self.name = self.reason()
        self.fb = bytearray(self.width * self.height * 4)

    # -- client messages
    def use_format(self, pf):
        self.pf = pf
        self.cpixel_size, self.cpixel_offset = pf.cpixel()

    def set_pixel_format(self, pf):
        """SetPixelFormat to a PixelFormat (or its text, PixelFormat.parse); pixels come in it from then on."""
        if isinstance(pf, str):
            pf = PixelFormat.parse(pf)
        self.send(pf.message())
        self.use_format(pf)

    def set_pixel_format_rgbx(self):
        """32-bit true colour, red at 0, green 8, blue 16 (another byte order than the server's, decoded back to BGRX)."""
        self.set_pixel_format(PixelFormat(32, 24, False, (255, 255, 255), (0, 8, 16)))

    def set_encodings(self, names):
        codes = [ENCODINGS[n] if isinstance(n, str) else n for n in names]
        self.encodings = codes
        self.send(struct.pack('>BBH', 2, 0, len(codes)) + b''.join(struct.pack('>i', c) for c in codes))

    def request(self, incremental=True, rect=None):
        x, y, w, h = rect or (0, 0, self.width, self.height)
        self.send(struct.pack('>BBHHHH', 3, 1 if incremental else 0, x, y, w, h))

    def key(self, keysym, down):
        self.send(struct.pack('>BBxxI', 4, 1 if down else 0, keysym))

    def tap(self, keysym):
        self.key(keysym, True)
        self.key(keysym, False)

    def pointer(self, mask, x, y):
        self.send(struct.pack('>BBHH', 5, mask, x, y))

    def cut_text(self, text):
        data = text.encode('latin-1')
        self.send(struct.pack('>BxxxI', 6, len(data)) + data)

    # -- server messages
    def wait_readable(self, timeout):
        """Whether bytes are there (buffered, or arriving within timeout seconds)."""
        if self.buf:
            return True
        self.sock.settimeout(timeout)
        try:
            chunk = self.sock.recv(65536)
        except socket.timeout:
            return False
        finally:
            self.sock.settimeout(20)
        if not chunk:
            raise RfbError('the server closed the connection')
        self.bytes_read += len(chunk)
        self.buf += chunk
        return True

    def read_message(self, timeout=None):
        """One server message; answer its type, or None if none came within timeout (seconds)."""
        if timeout is not None and not self.wait_readable(timeout):
            return None
        t = self.u8()
        if t == 0:
            self.read_update()
        elif t == 2:
            self.bells += 1
        elif t == 3:
            self.recv(3)
            self.cut_texts.append(self.recv(self.u32()).decode('latin-1'))
        else:
            raise RfbError('unexpected server message %d' % t)
        return t

    def update(self, incremental=True, timeout=10):
        """Request and read the next FramebufferUpdate (other messages are kept); False if none came within timeout."""
        self.request(incremental)
        end = time.time() + timeout
        while time.time() < end:
            if self.read_message(max(0.01, end - time.time())) == 0:
                return True
        return False

    def read_update(self):
        self.recv(1)
        n = self.u16()
        self.last_rects = []
        self.updates += 1
        size = self.pf.size
        while n == 0xFFFF or len(self.last_rects) < n:
            x, y, w, h, enc = struct.unpack('>HHHHi', self.recv(12))
            self.last_rects.append((enc, (x, y, w, h)))
            self.encodings_seen.add(enc)
            if enc == -224:
                break
            elif enc == 0:
                data = self.recv(w * h * size)
                if self.decode:
                    self._put(x, y, w, h, self.pf.to_bgrx(data))
            elif enc == 1:
                sx, sy = self.u16(), self.u16()
                if self.decode:
                    rows = [bytes(self.fb[((sy + r) * self.width + sx) * 4:((sy + r) * self.width + sx + w) * 4])
                            for r in range(h)]
                    self._put(x, y, w, h, b''.join(rows))
            elif enc == 16:
                self._zrle(x, y, w, h)
            elif enc == -239:
                self.cursor = ((x, y), (w, h), self.recv(w * h * size), self.recv((w + 7) // 8 * h))
            elif enc == -223:
                self.width, self.height = w, h
                self.fb = bytearray(w * h * 4)
            else:
                raise RfbError('unknown encoding %d' % enc)

    def _put(self, x, y, w, h, bgrx):
        for r in range(h):
            o = ((y + r) * self.width + x) * 4
            self.fb[o:o + w * 4] = bgrx[r * w * 4:(r + 1) * w * 4]

    def _cpixels(self, raw):
        """CPIXELs as BGRX: 3-byte ones put back at their place in a pixel of the format, then converted."""
        cp, off = self.cpixel_size, self.cpixel_offset
        if cp == self.pf.size:
            return self.pf.to_bgrx(raw)
        n = len(raw) // cp
        px = bytearray(n * 4)
        for k in range(3):
            px[off + k::4] = raw[k::3]
        return self.pf.to_bgrx(bytes(px))

    def _zrle(self, x, y, w, h):
        data = self.zlib.decompress(self.recv(self.u32()))
        if not self.decode:
            return
        p = 0
        cp = self.cpixel_size

        def cpixels(n):
            nonlocal p
            px = self._cpixels(data[p:p + cp * n])
            p += cp * n
            return px

        def run_length():
            nonlocal p
            n = 1
            while True:
                b = data[p]
                p += 1
                n += b
                if b != 255:
                    return n

        for ty in range(0, h, 64):
            for tx in range(0, w, 64):
                tw, th = min(64, w - tx), min(64, h - ty)
                sub = data[p]
                p += 1
                if sub == 0:
                    tile = cpixels(tw * th)
                elif sub == 1:
                    tile = cpixels(1) * (tw * th)
                elif 2 <= sub <= 16:
                    palette = cpixels(sub)
                    palette = [palette[i * 4:i * 4 + 4] for i in range(sub)]
                    bits = 1 if sub == 2 else 2 if sub <= 4 else 4
                    pixels = []
                    for _ in range(th):
                        row_bytes = (tw * bits + 7) // 8
                        row = data[p:p + row_bytes]
                        p += row_bytes
                        for i in range(tw):
                            bit = i * bits
                            pixels.append(palette[(row[bit // 8] >> (8 - bits - bit % 8)) & ((1 << bits) - 1)])
                    tile = b''.join(pixels)
                elif sub == 128 or sub >= 130:
                    palette = None
                    if sub >= 130:
                        palette = cpixels(sub - 128)
                        palette = [palette[i * 4:i * 4 + 4] for i in range(sub - 128)]
                    pixels, count = [], 0
                    while count < tw * th:
                        if palette is None:
                            px = cpixels(1)
                            n = run_length()
                        else:
                            b = data[p]
                            p += 1
                            px = palette[b & 127]
                            n = run_length() if b & 128 else 1
                        pixels.append(px * n)
                        count += n
                    tile = b''.join(pixels)
                else:
                    raise RfbError('ZRLE: bad subencoding %d' % sub)
                if len(tile) != tw * th * 4:
                    raise RfbError('ZRLE: a %dx%d tile at %d,%d decoded to %d pixels' % (tw, th, x + tx, y + ty,
                                                                                         len(tile) // 4))
                self._put(x + tx, y + ty, tw, th, tile)
        if p != len(data):
            raise RfbError('ZRLE: %d bytes left over (CPIXEL %d bytes)' % (len(data) - p, cp))

    # -- comparing
    def differences(self, width, height, rgba, from_row=0):
        """Pixels whose colour differs from an RGBA image of the same size (the X/alpha byte aside), and the first;
        from from_row on. In a format of fewer bits a channel, the image's colours as that format keeps them."""
        if (width, height) != (self.width, self.height):
            return width * height, 'size %dx%d, framebuffer %dx%d' % (width, height, self.width, self.height)
        fb = bytes(self.fb[from_row * width * 4:])
        rgba = rgba[from_row * width * 4:]
        r, g, b = rgba[0::4], rgba[1::4], rgba[2::4]
        if not self.pf.lossless:
            r, g, b = (c.translate(t) for c, t in zip((r, g, b), self.pf.round_trip))
        if fb[2::4] == r and fb[1::4] == g and fb[0::4] == b:
            return 0, None
        count, first = 0, None
        for i in range(width * (height - from_row)):
            o = i * 4
            if (fb[o + 2], fb[o + 1], fb[o]) != (r[i], g[i], b[i]):
                count += 1
                if first is None:
                    first = 'at %d,%d: screenshot %r, RFB %r' % (i % width, i // width + from_row, (r[i], g[i], b[i]),
                                                                (fb[o + 2], fb[o + 1], fb[o]))
        return count, first

    def save_ppm(self, path):
        fb = bytes(self.fb)
        rgb = bytearray(self.width * self.height * 3)
        rgb[0::3], rgb[1::3], rgb[2::3] = fb[2::4], fb[1::4], fb[0::4]
        with open(path, 'wb') as f:
            f.write(b'P6 %d %d 255\n' % (self.width, self.height) + bytes(rgb))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--host', default='127.0.0.1')
    ap.add_argument('--port', type=int, required=True)
    ap.add_argument('--version', default='3.8', choices=['3.3', '3.8'])
    ap.add_argument('--auth', default='vencrypt', choices=['vnc', 'vencrypt', 'none'])
    ap.add_argument('--secret-file', help='the VNC password or the session token, its first line')
    ap.add_argument('--encodings', default='zrle,copyrect,cursor,desktopsize,lastrect',
                    help='names or numbers, comma-separated')
    ap.add_argument('--pixel-format', help='SetPixelFormat bpp/depth/le|be/rmax,gmax,bmax/rshift,gshift,bshift')
    ap.add_argument('--save', help='write the framebuffer as a PPM')
    ap.add_argument('--compare', help='compare the framebuffer with a PNG, pixel for pixel')
    a = ap.parse_args()
    secret = open(a.secret_file).readline().strip() if a.secret_file else None
    c = RfbClient(a.host, a.port)
    c.handshake(a.version, a.auth, secret)
    if a.pixel_format:
        c.set_pixel_format(a.pixel_format)
    c.set_encodings([e if e in ENCODINGS else int(e, 0) for e in a.encodings.split(',')])
    if not c.update(incremental=False):
        sys.exit('no update')
    print('%s %dx%d, %d bytes, rects %r' % (c.name, c.width, c.height, c.bytes_read, [e for e, _ in c.last_rects]))
    if a.save:
        c.save_ppm(a.save)
    if a.compare:
        n, first = c.differences(*read_png(a.compare))
        print('%d pixels differ%s' % (n, ', first ' + first if first else ''))
        sys.exit(1 if n else 0)


if __name__ == '__main__':
    main()
