Object subclass: #RfbPixelFormat
	instanceVariableNames: 'bitsPerPixel depth bigEndian trueColour redMax greenMax blueMax redShift greenShift blueShift'
	classVariableNames: ''
	package: 'System-Remote'!

RfbPixelFormat comment: 'I am an RFB pixel format (RFC 6143, 7.4): bits per pixel (8, 16 or 32), depth, byte order, and for true colour each channel''s maximum and shift. The server''s own (native) is 32 bits, depth 24, little-endian, red at shift 16, green 8, blue 0: the bytes Blue Green Red X, the order of the FirmwareScreen''s shadow copy and of what RfbFrameSource>>bgraOf: answers, so it goes out as it is. convertBgra:count: makes any other true-colour format the client asks for (SetPixelFormat): a byte shuffle where each channel is a whole byte of a 32-bit pixel, else channel by channel. Colour maps are not supported (a client that asks for one is refused).

For ZRLE (cpixelSize, cpixelOffset): a 32-bit pixel whose channels all fit in its low or high three bytes travels as those three bytes.'!

!RfbPixelFormat methodsFor: 'initialization'!
setBitsPerPixel: bpp depth: d bigEndian: be trueColour: tc maxes: anArray shifts: shifts
	bitsPerPixel := bpp.
	depth := d.
	bigEndian := be.
	trueColour := tc.
	redMax := anArray at: 1.
	greenMax := anArray at: 2.
	blueMax := anArray at: 3.
	redShift := shifts at: 1.
	greenShift := shifts at: 2.
	blueShift := shifts at: 3
! !

!RfbPixelFormat methodsFor: 'accessing'!
bitsPerPixel
	^bitsPerPixel
!
bytesPerPixel
	^bitsPerPixel // 8
!
depth
	^depth
!
isBigEndian
	^bigEndian
!
isTrueColour
	^trueColour
!
maxes
	^Array with: redMax with: greenMax with: blueMax
!
shifts
	^Array with: redShift with: greenShift with: blueShift
!
= other
	^(other isKindOf: RfbPixelFormat) and: [self asBytes = other asBytes]
!
hash
	^self asBytes hash
! !

!RfbPixelFormat methodsFor: 'testing'!
problem
	"Why I cannot be served, or nil."
	(#(8 16 32) includes: bitsPerPixel) ifFalse: [^'bits per pixel ', bitsPerPixel printString].
	trueColour ifFalse: [^'colour maps are not supported'].
	(self maxes anySatisfy: [:m | m < 1 or: [m > 255]]) ifTrue: [^'channel maxima above 255 are not supported'].
	^nil
!
isNative
	"Blue Green Red X in memory: what the frame source gives."
	^bitsPerPixel = 32 and: [trueColour and: [self isByteAligned and: [
		(self byteOfShift: redShift) = 2 and: [(self byteOfShift: greenShift) = 1 and: [(self byteOfShift: blueShift) = 0]]]]]
!
isByteAligned
	"32 bits with each channel a whole byte."
	^bitsPerPixel = 32 and: [trueColour and: [
		(self maxes allSatisfy: [:m | m = 255]) and: [self shifts allSatisfy: [:s | s \\ 8 = 0 and: [s <= 24]]]]]
!
byteOfShift: aShift
	"The byte (0-based, in memory) of a 32-bit pixel holding the channel at aShift."
	^bigEndian ifTrue: [3 - (aShift // 8)] ifFalse: [aShift // 8]
! !

!RfbPixelFormat methodsFor: 'ZRLE'!
cpixelSize
	"ZRLE's CPIXEL: 3 bytes for a true-colour 32-bit pixel of depth <= 24 whose channels fit in its low or high three bytes, else the whole pixel."
	^self cpixelOffset isNil ifTrue: [self bytesPerPixel] ifFalse: [3]
!
cpixelOffset
	"Where the 3-byte CPIXEL starts inside a pixel in memory (0 or 1), or nil when CPIXEL is the whole pixel."
	| used low |
	(bitsPerPixel = 32 and: [trueColour and: [depth <= 24]]) ifFalse: [^nil].
	used := ((redMax bitShift: redShift) bitOr: (greenMax bitShift: greenShift)) bitOr: (blueMax bitShift: blueShift).
	used < 16r1000000 ifTrue: [low := true] ifFalse: [
		(used bitAnd: 255) = 0 ifFalse: [^nil].
		low := false].
	^low = bigEndian ifTrue: [1] ifFalse: [0]
! !

!RfbPixelFormat methodsFor: 'converting'!
convertBgra: bytes count: n
	"n pixels of BGRA8 bytes in my format (bytes itself when I am native)."
	| out map |
	self isNative ifTrue: [^bytes].
	self isByteAligned ifTrue: [
		out := ByteArray new: n * 4.
		map := Array with: (self byteOfShift: blueShift) + 1 with: (self byteOfShift: greenShift) + 1 with: (self byteOfShift: redShift) + 1.
		(map = #(3 2 1) and: [self swapRedBlue: bytes into: out count: n]) ifTrue: [^out].
		0 to: n - 1 do: [:i | | o |
			o := i * 4.
			out at: o + (map at: 1) put: (bytes at: o + 1).
			out at: o + (map at: 2) put: (bytes at: o + 2).
			out at: o + (map at: 3) put: (bytes at: o + 3)].
		^out].
	^self convertGenerally: bytes count: n
!
convertGenerally: bytes count: n
	| bpp out |
	bpp := self bytesPerPixel.
	out := ByteArray new: n * bpp.
	0 to: n - 1 do: [:i | | o v |
		o := i * 4.
		v := (((((bytes at: o + 3) * redMax + 127) // 255) bitShift: redShift)
			bitOr: ((((bytes at: o + 2) * greenMax + 127) // 255) bitShift: greenShift))
			bitOr: ((((bytes at: o + 1) * blueMax + 127) // 255) bitShift: blueShift).
		self put: v into: out at: i * bpp + 1].
	^out
!
put: aPixel into: bytes at: index
	"aPixel's bytesPerPixel bytes at index, in my byte order."
	| bpp |
	bpp := self bytesPerPixel.
	1 to: bpp do: [:k |
		bytes at: index + (bigEndian ifTrue: [bpp - k] ifFalse: [k - 1]) put: ((aPixel bitShift: (k - 1) * -8) bitAnd: 255)]
!
pixelOfRed: r green: g blue: b
	"The pixel value (an Integer) of 8-bit r, g, b in my format."
	^((((r * redMax + 127) // 255) bitShift: redShift)
		bitOr: (((g * greenMax + 127) // 255) bitShift: greenShift))
		bitOr: (((b * blueMax + 127) // 255) bitShift: blueShift)
!
swapRedBlue: bytes into: out count: n
	"With the raster primitive where there is one; answer whether it ran."
	^[SoftwareRaster copy: out stride: n * 4 from: bytes stride: n * 4 width: n height: 1 bytesPerPixel: 4 mode: 1. true]
		on: Error do: [:e | e return: false]
! !

!RfbPixelFormat methodsFor: 'encoding'!
asBytes
	"The 16 bytes of PIXEL_FORMAT."
	| b |
	b := ByteArray new: 16.
	b at: 1 put: bitsPerPixel.
	b at: 2 put: depth.
	b at: 3 put: (bigEndian ifTrue: [1] ifFalse: [0]).
	b at: 4 put: (trueColour ifTrue: [1] ifFalse: [0]).
	b at: 5 put: (redMax bitShift: -8); at: 6 put: (redMax bitAnd: 255).
	b at: 7 put: (greenMax bitShift: -8); at: 8 put: (greenMax bitAnd: 255).
	b at: 9 put: (blueMax bitShift: -8); at: 10 put: (blueMax bitAnd: 255).
	b at: 11 put: redShift; at: 12 put: greenShift; at: 13 put: blueShift.
	^b
!
printOn: aStream
	aStream nextPutAll: 'RfbPixelFormat '; print: bitsPerPixel; nextPutAll: ' bpp depth '; print: depth.
	aStream nextPutAll: (bigEndian ifTrue: [' BE'] ifFalse: [' LE']).
	trueColour ifFalse: [^aStream nextPutAll: ' colour map'].
	aStream nextPutAll: ' max '; print: redMax; nextPut: $/; print: greenMax; nextPut: $/; print: blueMax.
	aStream nextPutAll: ' shift '; print: redShift; nextPut: $/; print: greenShift; nextPut: $/; print: blueShift
! !

!RfbPixelFormat class methodsFor: 'instance creation'!
native
	"BGRX: 32 bits, depth 24, little-endian, red 16, green 8, blue 0."
	^self bitsPerPixel: 32 depth: 24 bigEndian: false maxes: #(255 255 255) shifts: #(16 8 0)
!
bitsPerPixel: bpp depth: d bigEndian: be maxes: maxes shifts: shifts
	^self new setBitsPerPixel: bpp depth: d bigEndian: be trueColour: true maxes: maxes shifts: shifts
!
fromBytes: b
	"From the 16 bytes of PIXEL_FORMAT."
	^self new
		setBitsPerPixel: (b at: 1) depth: (b at: 2) bigEndian: (b at: 3) ~= 0 trueColour: (b at: 4) ~= 0
		maxes: (Array with: (b uint16BigEndianAt: 5) with: (b uint16BigEndianAt: 7) with: (b uint16BigEndianAt: 9))
		shifts: (Array with: (b at: 11) with: (b at: 12) with: (b at: 13))
! !
