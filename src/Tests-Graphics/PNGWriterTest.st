GraphicsTestCase subclass: #PNGWriterTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Graphics'!

PNGWriterTest comment: 'I check the PNG encoder: checksums against known values, and written files (a rendered scene; indexed, RGB and RGBA Forms) decoded by Python''s zlib (stdlib only, the filters undone in Python) with every chunk CRC verified. PNGCodecTest checks the encodings against PNGReader without a GPU.'!

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
testCompressedFormsThroughPython
	"Indexed (with a translucent color), RGB and RGBA Forms, written compressed, decoded by python3."
	| indexed rgb rgba path |
	indexed := Form width: 40 height: 30.
	1 to: indexed bits size do: [:i | indexed bits at: i put: (#(16rFF0000FF 16rFFFFFFFF 16r80402010) at: i \\ 3 + 1)].
	rgb := Form width: 300 height: 200.
	rgba := Form width: 300 height: 200.
	0 to: 199 do: [:y | 0 to: 299 do: [:x | | v |
		v := (x \\ 256) + (y bitShift: 8) + (x * y \\ 256 bitShift: 16).
		rgb bits at: y * 300 + x + 1 put: v + (255 bitShift: 24).
		rgba bits at: y * 300 + x + 1 put: v + (x + y \\ 256 bitShift: 24)]].
	path := self scratchPath: 'compressed.png'.
	PNGWriter write: indexed to: path.
	self assert: (self python: self decoderScript arguments: {path. '40'. '30'. '0,0,255,255,255,255'. '1,0,16,32,64,128'. '2,0,255,0,0,255'. '39,29,255,0,0,255'}) equals: 0.
	PNGWriter write: rgb to: path.
	self assert: (self python: self decoderScript arguments: {path. '300'. '200'. '0,0,0,0,0,255'. '299,199,43,199,109,255'. '17,5,17,5,85,255'}) equals: 0.
	PNGWriter write: rgba to: path.
	self assert: (self python: self decoderScript arguments: {path. '300'. '200'. '0,0,0,0,0,0'. '299,199,43,199,109,242'. '17,5,17,5,85,22'}) equals: 0
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

!PNGWriterTest methodsFor: 'filtering'!
assertFilterOf: rgba width: w height: h
	"The VM's pngFilter primitive and the Smalltalk loop give the same rows, RGB and RGBA."
	#(3 4) do: [:n | | raw |
		raw := ByteArray new: (w * n + 1) * h.
		self assert: (PNGWriter primFilter: rgba width: w height: h channels: n into: raw) == raw.
		self assert: raw equals: (PNGWriter filteredInSmalltalk: rgba width: w height: h channels: n).
		self assert: (PNGWriter filtered: rgba width: w height: h channels: n) equals: raw]
!
testFilterPrimitiveOnRandomBytes
	| random |
	random := Random seed: 1618.
	#(1 2 3 5 6 16 17 21 64 101) do: [:w | #(1 2 7) do: [:h | | rgba mode |
		mode := random nextInt: 3.
		rgba := ((1 to: w * h * 4) collect: [:i |
			mode = 1
				ifTrue: [#(0 1 127 128 254 255) at: (random nextInt: 6)]
				ifFalse: [mode = 2 ifTrue: [random nextInt: 4] ifFalse: [(random nextInt: 256) - 1]]]) asByteArray.
		self assertFilterOf: rgba width: w height: h]]
!
testFilterPrimitiveOnRenderedScreen
	"A rendered screen: text, fills, translucent strokes."
	| form |
	form := self render: [:c |
		c fillRect: (0 @ 0 extent: 640 @ 30) color: Color ultramarine.
		c drawString: 'PNG rows, filtered 16 bytes at a time' at: 12 @ 6 font: Font ui color: Color white.
		0 to: 40 do: [:i |
			c fillRect: (i * 15 @ 60 extent: 12 @ 200) color: (Color r: i / 40 g: 0.5 b: 1 - (i / 40) a: 0.6).
			c drawString: i printString at: i * 15 @ 280 font: Font ui color: Color black]] extent: 640 @ 360.
	self assertFilterOf: form asByteArray width: form width height: form height
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
p = 8; idat = b""; w = h = None; plte = b""; trns = b""
while p < len(d):
    n, = struct.unpack(">I", d[p:p+4]); t = d[p+4:p+8]; body = d[p+8:p+8+n]
    crc, = struct.unpack(">I", d[p+8+n:p+12+n])
    assert zlib.crc32(t + body) & 0xffffffff == crc, t
    if t == b"IHDR": w, h, depth, ctype = struct.unpack(">IIBB", body[:10]); assert depth == 8 and ctype in (2, 3, 6)
    if t == b"PLTE": plte = body
    if t == b"tRNS": trns = body
    if t == b"IDAT": idat += body
    p += 12 + n
assert (w, h) == (int(sys.argv[2]), int(sys.argv[3])), (w, h)
n = {2: 3, 3: 1, 6: 4}[ctype]
raw = zlib.decompress(idat)
assert len(raw) == h * (1 + n * w)
rows = []; prior = bytearray(n * w)
for y in range(h):
    f = raw[y * (1 + n * w)]; line = bytearray(raw[y * (1 + n * w) + 1:(y + 1) * (1 + n * w)])
    for i in range(len(line)):
        a = line[i - n] if i >= n else 0; b = prior[i]; c = prior[i - n] if i >= n else 0
        if f == 1: line[i] = (line[i] + a) & 255
        elif f == 2: line[i] = (line[i] + b) & 255
        elif f == 3: line[i] = (line[i] + (a + b) // 2) & 255
        elif f == 4:
            q = a + b - c; pa, pb, pc = abs(q - a), abs(q - b), abs(q - c)
            line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        else: assert f == 0, f
    rows.append(line); prior = line
def px(x, y):
    o = rows[y][n * x:n * x + n]
    if ctype == 3: i = o[0]; return tuple(plte[3 * i:3 * i + 3]) + ((trns[i] if i < len(trns) else 255),)
    return tuple(o) + ((255,) if n == 3 else ())
for spec in sys.argv[4:]:
    x, y, r, g, b, a = map(int, spec.split(","))
    assert px(x, y) == (r, g, b, a), (spec, px(x, y))
'
!
python: script arguments: anArray
	"Run python3 -c script with the arguments; answer its exit status."
	| pid |
	pid := (File primSpawn: ({'python3'. '-c'. script} , anArray)) ifNil: [
		^self fail: 'spawnProcess failed'].
	^(File primWait: pid blocking: true) ifNil: [self fail: 'processWait failed']
! !
