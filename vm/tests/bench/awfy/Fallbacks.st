"The VM's scalar performance primitives against their Smalltalk fallbacks (docs/benchmarks.md, Fallbacks): Fb<Name> runs the fallback, Fb<Name>Prim the primitive, on a real 1440x900 screenshot (prototypes/screenshots/proto-4-morphic.png, 5.18 MB of RGBA). A primitive retired leaves its Fb<Name>Prim failing (it no longer exists)."!

Benchmark subclass: #FbScreen
	instanceVariableNames: 'rgba width height'
	classVariableNames: 'Cache'
	package: 'AWFY'!

FbScreen subclass: #FbAdler
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

FbScreen subclass: #FbAdlerPrim
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

FbScreen subclass: #FbCompress
	instanceVariableNames: 'filtered'
	classVariableNames: ''
	package: 'AWFY'!

FbScreen subclass: #FbPixelDiff
	instanceVariableNames: 'source frames changed'
	classVariableNames: ''
	package: 'AWFY'!

FbPixelDiff subclass: #FbPixelDiffPrim
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

FbScreen subclass: #FbMismatch
	instanceVariableNames: 'other'
	classVariableNames: ''
	package: 'AWFY'!

FbMismatch subclass: #FbMismatchPrim
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

FbScreen subclass: #FbPack
	instanceVariableNames: 'out'
	classVariableNames: ''
	package: 'AWFY'!

FbPack subclass: #FbPackPrim
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

FbScreen subclass: #FbZrle
	instanceVariableNames: 'encoder'
	classVariableNames: ''
	package: 'AWFY'!

FbZrle subclass: #FbZrlePrim
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

FbScreen subclass: #FbPngFilter
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

FbPngFilter subclass: #FbPngFilterPrim
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

!FbScreen class methodsFor: 'data'!
screenshot: aName
	"The RGBA bytes of a screenshot of the repository's (next to the image's build directory)."
	| p f |
	Cache isNil ifTrue: [Cache := Dictionary new].
	^Cache at: aName ifAbsentPut: [
		p := Smalltalk vm imagePath.
		f := PNGReader formFromFile: (p copyFrom: 1 to: (p lastIndexOf: $/)) , '../prototypes/screenshots/' , aName.
		{f asByteArray. f width. f height}]
! !

!FbScreen methodsFor: 'initialization'!
initialize
	| s |
	s := self class screenshot: 'proto-4-morphic.png'.
	rgba := s at: 1.
	width := s at: 2.
	height := s at: 3
! !

!FbAdler methodsFor: 'benchmarking'!
benchmark
	"Adler-32 of the 5.18 MB, 10 times."
	| r |
	10 timesRepeat: [r := ZLib adler32InSmalltalkOf: rgba].
	^r
!
verifyResult: result
	^result = (ZLib adler32Of: rgba)
! !

!FbAdlerPrim methodsFor: 'benchmarking'!
benchmark
	| r |
	10 timesRepeat: [r := ZLib primAdler32Of: rgba].
	^r
!
verifyResult: result
	^result = (ZLib adler32InSmalltalkOf: rgba)
! !

!FbCompress methodsFor: 'benchmarking'!
initialize
	super initialize.
	filtered := PNGWriter filtered: rgba width: width height: height channels: 4
!
benchmark
	"ZLib compress of the filtered screenshot (5.2 MB to about 830 KB): what a PNG of it takes."
	^ZLib compress: filtered
!
verifyResult: result
	^(ZLib decompress: result) = filtered
! !

!FbPixelDiff methodsFor: 'initialization'!
initialize
	"The screen and the screen with a line of text, a cursor and a window's content changed, compared in turns as a whole frame (an RfbDiffSource's damage of a frame: 1440x900)."
	| other b |
	super initialize.
	other := (self class screenshot: 'proto-3-tiling.png') at: 1.
	b := rgba copy.
	"a line of text: 16 rows of 600 pixels"
	400 to: 415 do: [:y | b replaceFrom: y * width + 100 * 4 + 1 to: y * width + 700 * 4 with: other startingAt: y * width + 100 * 4 + 1].
	"the pointer: 16x16"
	200 to: 215 do: [:y | b replaceFrom: y * width + 900 * 4 + 1 to: y * width + 916 * 4 with: other startingAt: y * width + 900 * 4 + 1].
	"a window's content: 300x200"
	500 to: 699 do: [:y | b replaceFrom: y * width + 1000 * 4 + 1 to: y * width + 1300 * 4 with: other startingAt: y * width + 1000 * 4 + 1].
	frames := {b. rgba}.
	source := RfbDiffSource new.
	source instVarNamed: 'extent' put: width @ height.
	source instVarNamed: 'copy' put: rgba copy.
	changed := OrderedCollection new
!
compare: bytes
	source compareInSmalltalk: (0 @ 0 extent: width @ height) with: bytes into: changed
!
benchmark
	"20 frames, every other one changed in three places."
	changed := OrderedCollection new.
	10 timesRepeat: [frames do: [:each | self compare: each]].
	^changed inject: 0 into: [:sum :r | sum + r area]
!
verifyResult: result
	"the blocks of the three changes, in 10 of the frames"
	^result > 0 and: [result \\ 10 = 0]
! !

!FbPixelDiffPrim methodsFor: 'benchmarking'!
compare: bytes
	source compare: (0 @ 0 extent: width @ height) with: bytes into: changed
! !

!FbMismatch methodsFor: 'benchmarking'!
initialize
	super initialize.
	other := rgba copy
!
benchmark
	"The 5.18 MB against an equal copy, 5 times."
	| r |
	5 timesRepeat: [r := rgba fbMismatchAt: 1 with: other at: 1 size: rgba size].
	^r
!
verifyResult: result
	^result = 0
! !

!FbMismatchPrim methodsFor: 'benchmarking'!
benchmark
	| r |
	5 timesRepeat: [r := rgba indexOfMismatchAt: 1 with: other at: 1 size: rgba size].
	^r
! !

!FbPack methodsFor: 'benchmarking'!
initialize
	super initialize.
	out := ByteArray new: width * height * 3
!
pack
	PixelPack packInSmalltalk: rgba stride: width * 4 x: 0 y: 0 width: width height: height swap: true into: out
!
benchmark
	"The 1440x900 pixels packed to 3 bytes each, swapped, 10 times."
	10 timesRepeat: [self pack].
	^out
!
verifyResult: result
	^(result at: 1) = (rgba at: 3) and: [(result at: result size) = (rgba at: rgba size - 3)]
! !

!FbPackPrim methodsFor: 'benchmarking'!
pack
	PixelPack primPack: rgba stride: width * 4 x: 0 y: 0 width: width height: height swap: 1 into: out
! !

!FbZrle methodsFor: 'benchmarking'!
initialize
	super initialize.
	encoder := RfbZrleEncoder new
!
tiles
	^encoder tilesInSmalltalk: rgba width: width height: height bytesPerPixel: 4 cpixelSize: 3 offset: 0
!
benchmark
	"The ZRLE tiles of the 1440x900 frame (3-byte CPIXELs)."
	^self tiles size
!
verifyResult: result
	^result > 0
! !

!FbZrlePrim methodsFor: 'benchmarking'!
tiles
	| buffer n |
	buffer := ByteArray new: width * height * 3 + ((width + 63 // 64) * (height + 63 // 64)).
	n := encoder primTiles: rgba width: width height: height bytesPerPixel: 4 cpixelSize: 3 offset: 0 scratch: encoder scratch into: buffer.
	^buffer copyFrom: 1 to: n
! !

!FbPngFilter methodsFor: 'benchmarking'!
filtered
	^PNGWriter filteredInSmalltalk: rgba width: width height: height channels: 4
!
benchmark
	"The PNG rows of the 1440x900 RGBA, each with its best filter."
	^self filtered size
!
verifyResult: result
	^result = (width * 4 + 1 * height)
! !

!FbPngFilterPrim methodsFor: 'benchmarking'!
filtered
	| raw |
	raw := ByteArray new: (width * 4 + 1) * height.
	PNGWriter primFilter: rgba width: width height: height channels: 4 into: raw.
	^raw
! !

!ByteArray methodsFor: '*AWFY'!
fbMismatchAt: start with: anObject at: otherStart size: n
	"indexOfMismatchAt:with:at:size:'s Smalltalk (where its primitive fails)."
	(start >= 1 and: [otherStart >= 1 and: [n >= 0 and: [start + n - 1 <= self size and: [otherStart + n - 1 <= anObject size]]]]) ifFalse: [^self error: 'range outside'].
	1 to: n do: [:i | (self at: start + i - 1) = (anObject at: otherStart + i - 1) ifFalse: [^i]].
	^0
! !
