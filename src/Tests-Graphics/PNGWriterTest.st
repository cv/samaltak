GraphicsTestCase subclass: #PNGWriterTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Graphics'!

PNGWriterTest comment: 'I check the PNG encoder: checksums against known values, and a written file decoded by Python''s zlib (stdlib only) with every chunk CRC verified.'!

!PNGWriterTest methodsFor: 'tests'!
testCRC32
	self assert: (PNGWriter crc32Of: '123456789' asByteArray) equals: 16rCBF43926.
	self assert: (PNGWriter crc32Of: ByteArray new) equals: 0
!
testAdler32
	self assert: (PNGWriter adler32Of: 'Wikipedia' asByteArray) equals: 16r11E60398.
	self assert: (PNGWriter adler32Of: (ByteArray new: 100000 withAll: 255)) equals: (self slowAdler32: (ByteArray new: 100000 withAll: 255))
!
testStoredBlocksSplitAt65535
	| raw z |
	raw := ByteArray new: 70000 withAll: 7.
	z := PNGWriter zlibStored: raw.
	self assert: z size equals: 2 + 5 + 65535 + 5 + 4465 + 4.
	self assert: (z at: 3) equals: 0.
	self assert: (z at: 3 + 5 + 65535) equals: 1
!
testRoundTripThroughPython
	"Render a scene, write it, and let python3 decode it and check size, CRCs and a few pixels."
	| form path status |
	form := self render: [:c |
		c fillRect: (0 @ 0 extent: 10 @ 10) color: Color ultramarine.
		c drawString: 'PNG' at: 12 @ 0 font: Font ui color: Color black] extent: 60 @ 300.
	path := self scratchPath: 'test.png'.
	PNGWriter write: form to: path.
	status := self python: self decoderScript arguments: {path. '120'. '600'. '5,5,27,58,140,255'. '119,599,255,255,255,255'}.
	self assert: status equals: 0
!
testCropForm
	| form crop |
	form := Form width: 4 height: 3.
	0 to: 2 do: [:y | 0 to: 3 do: [:x | form pixelValueAt: x@y put: y * 4 + x]].
	crop := form croppedTo: (1@1 corner: 9@9).
	self assert: crop extent equals: 3@2.
	self assert: (crop pixelValueAt: 0@0) equals: 5.
	self assert: (crop pixelValueAt: 2@1) equals: 11.
	crop := form croppedTo: (-2@ -2 corner: 1.2@1.2).
	self assert: crop extent equals: 2@2.
	self should: [form croppedTo: (9@9 extent: 1@1)] raise: Error.
	self assert: form extent equals: 4@3
! !

!PNGWriterTest methodsFor: 'support'!
slowAdler32: bytes
	| a b |
	a := 1.
	b := 0.
	bytes do: [:x | a := a + x \\ 65521. b := b + a \\ 65521].
	^(b bitShift: 16) + a
!
decoderScript
	^'import sys, zlib, struct
d = open(sys.argv[1], "rb").read()
assert d[:8] == b"\x89PNG\r\n\x1a\n"
p = 8; idat = b""; w = h = None
while p < len(d):
    n, = struct.unpack(">I", d[p:p+4]); t = d[p+4:p+8]; body = d[p+8:p+8+n]
    crc, = struct.unpack(">I", d[p+8+n:p+12+n])
    assert zlib.crc32(t + body) & 0xffffffff == crc, t
    if t == b"IHDR": w, h, depth, ctype = struct.unpack(">IIBB", body[:10]); assert depth == 8 and ctype == 6
    if t == b"IDAT": idat += body
    p += 12 + n
assert (w, h) == (int(sys.argv[2]), int(sys.argv[3])), (w, h)
raw = zlib.decompress(idat)
assert len(raw) == h * (1 + 4 * w)
for spec in sys.argv[4:]:
    x, y, r, g, b, a = map(int, spec.split(","))
    o = y * (1 + 4 * w) + 1 + 4 * x
    assert raw[y * (1 + 4 * w)] == 0
    assert tuple(raw[o:o+4]) == (r, g, b, a), (spec, tuple(raw[o:o+4]))
'
!
python: script arguments: anArray
	"Run python3 -c script with the arguments; answer its exit status."
	| pid |
	pid := self spawn: ({'python3'. '-c'. script} , anArray).
	^self waitFor: pid blocking: true
!
spawn: argv
	<primitive: 'spawnProcess'>
	^self fail: 'spawnProcess failed'
!
waitFor: pid blocking: aBoolean
	<primitive: 'processWait'>
	^self fail: 'processWait failed'
! !
