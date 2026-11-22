Object subclass: #DisplayList
	instanceVariableNames: 'vertices vertexCount batches extent scale batchBounds'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

DisplayList comment: 'I am the frozen result of drawing on a Canvas: vertex data in a ByteArray plus a short list of DisplayBatches (texture source, scissor, first, count). Once a Canvas hands me out I am never mutated, so a Renderer may draw me any number of times, from any process.

Vertex format (40 bytes, six vertices per quad, all six equal: the vertex shader picks the corner from the vertex index):
	0 rect float4: x0 y0 x1 y1, device pixels relative to origin
	16 uv0 uint: u0 | v0 << 16, texels (or a Float for line quads)
	20 uv1 uint: u1 | v1 << 16
	24 color: premultiplied RGBA8
	28 mode uint: bits 0-7 mode (0 solid, 1 glyph, 2 image, 3 halftone, 4 stripes, 5 antialiased line), 8-15 pattern cell (device px), 16-23 pattern variant, bit 31: explicit position (rect xy is this vertex''s position; used by line quads)
	32 origin float2: device pixels added to the position'!

!DisplayList methodsFor: 'private'!
setVertices: aByteArray count: anInteger batches: anArray extent: aPoint scale: aNumber
	vertices := aByteArray.
	vertexCount := anInteger.
	batches := anArray.
	extent := aPoint.
	scale := aNumber
! !

!DisplayList methodsFor: 'accessing'!
vertices
	"The vertex ByteArray (only the first vertexCount * 40 bytes are used)."
	^vertices
!
vertexCount
	^vertexCount
!
byteCount
	^vertexCount * 40
!
quadCount
	^vertexCount // 6
!
batches
	^batches
!
extent
	"Size in points."
	^extent
!
scale
	^scale
!
pixelExtent
	^(extent x * scale) ceiling @ (extent y * scale) ceiling
!
isEmpty
	^vertexCount = 0
!
boundsOfBatch: i
	"The device pixels batch i's quads cover, {x. y. width. height} before its translation (a pixel more around), or nil if it has none: for drawing only the batches that reach a damaged rectangle (Renderer>>render:into:clear:commandBuffer:within:). Found the first time asked, then kept (the vertices do not change)."
	batchBounds isNil ifTrue: [batchBounds := Array new: batches size].
	^(batchBounds at: i) ifNil: [batchBounds at: i put: (self computeBoundsOf: (batches at: i))]
! !

!DisplayList methodsFor: 'private'!
computeBoundsOf: aBatch
	| x0 y0 out found |
	aBatch count = 0 ifTrue: [^#none].
	out := ByteArray new: 16.
	found := SoftwareRaster quadBoundsOf: vertices from: aBatch first // 6 count: aBatch count // 6 into: out.
	found == false ifTrue: [^#none].
	found == true ifTrue: [| at |
		at := [:i | | w | w := out uint32At: i. w >= 16r80000000 ifTrue: [w - 16r100000000] ifFalse: [w]].
		x0 := (at value: 1) - 1.
		y0 := (at value: 5) - 1.
		^Array with: x0 with: y0 with: (at value: 9) + 1 - x0 with: (at value: 13) + 1 - y0].
	^self slowBoundsOf: aBatch
!
slowBoundsOf: aBatch
	"computeBoundsOf: in Smalltalk (a VM without the rasterQuadBounds primitive)."
	| v x0 y0 x1 y1 |
	aBatch count = 0 ifTrue: [^#none].
	v := vertices.
	x0 := y0 := 1.0e30.
	x1 := y1 := -1.0e30.
	aBatch first // 6 to: aBatch first + aBatch count // 6 - 1 do: [:q | | p ox oy |
		p := q * 240 + 1.
		((v uint32At: p + 28) bitAnd: 16r80000000) = 0
			ifTrue: [| a b |
				ox := v float32At: p + 32.
				oy := v float32At: p + 36.
				(a := (v float32At: p) + ox) < x0 ifTrue: [x0 := a].
				(b := (v float32At: p + 8) + ox) > x1 ifTrue: [x1 := b].
				(a := (v float32At: p + 4) + oy) < y0 ifTrue: [y0 := a].
				(b := (v float32At: p + 12) + oy) > y1 ifTrue: [y1 := b]]
			ifFalse: [
				0 to: 5 do: [:k | | r x y |
					r := p + (k * 40).
					x := (v float32At: r) + (v float32At: r + 32).
					y := (v float32At: r + 4) + (v float32At: r + 36).
					x < x0 ifTrue: [x0 := x]. x > x1 ifTrue: [x1 := x].
					y < y0 ifTrue: [y0 := y]. y > y1 ifTrue: [y1 := y]]]].
	x0 > x1 ifTrue: [^#none].
	x0 := x0 floor - 1.
	y0 := y0 floor - 1.
	^Array with: x0 with: y0 with: x1 ceiling + 1 - x0 with: y1 ceiling + 1 - y0
! !

!DisplayList methodsFor: 'inspecting'!
quadAt: index
	"Answer a Dictionary describing quad index (1-based): #rect #origin #color #mode #uv0 #uv1. For tests and debugging."
	| p |
	p := index - 1 * 240 + 1.
	^Dictionary new
		at: #rect put: (Rectangle left: (vertices float32At: p) right: (vertices float32At: p + 8) top: (vertices float32At: p + 4) bottom: (vertices float32At: p + 12));
		at: #origin put: (vertices float32At: p + 32) @ (vertices float32At: p + 36);
		at: #color put: (vertices uint32At: p + 24);
		at: #mode put: (vertices uint32At: p + 28);
		at: #uv0 put: (vertices uint32At: p + 16);
		at: #uv1 put: (vertices uint32At: p + 20);
		yourself
! !

!DisplayList methodsFor: 'comparing'!
quadTuples
	"One Array per quad, as the Renderer draws it: {texture (glyph and image quads only). scissor. mode. color} followed by uv0 uv1 x0 y0 x1 y1 (origin and the batch's move added), or for explicit-position quads by u v x y of each of the six vertices. For comparing drawings (drawsLike:)."
	| result |
	result := OrderedCollection new.
	batches do: [:b |
		b first to: b first + b count - 1 by: 6 do: [:v | | p mode kind t ox oy |
			p := v * 40 + 1.
			mode := vertices uint32At: p + 28.
			kind := mode bitAnd: 255.
			t := OrderedCollection new.
			t add: ((kind = 1 or: [kind = 2]) ifTrue: [b texture]); add: b scissor; add: mode; add: (vertices uint32At: p + 24).
			(mode bitAnd: self class explicitPosition) = 0
				ifTrue: [
					ox := (vertices float32At: p + 32) + b dx.
					oy := (vertices float32At: p + 36) + b dy.
					t add: (vertices uint32At: p + 16); add: (vertices uint32At: p + 20);
						add: (vertices float32At: p) + ox; add: (vertices float32At: p + 4) + oy;
						add: (vertices float32At: p + 8) + ox; add: (vertices float32At: p + 12) + oy]
				ifFalse: [
					0 to: 5 do: [:k | | q |
						q := p + (k * 40).
						t add: (vertices float32At: q + 16); add: (vertices float32At: q + 20);
							add: (vertices float32At: q) + (vertices float32At: q + 32) + b dx;
							add: (vertices float32At: q + 4) + (vertices float32At: q + 36) + b dy]].
			result add: t asArray]].
	^result asArray
!
drawsLike: aDisplayList
	"Answer whether aDisplayList draws the same quads in the same order with the same textures, clips and colors (positions within 1/100 device pixel), however they are batched and moved."
	^(self firstDifferenceFrom: aDisplayList) isNil
!
firstDifferenceFrom: aDisplayList
	"Answer nil if aDisplayList draws like me, else {index. my quad tuple. its quad tuple} of the first quad that differs (nil for a missing one)."
	| mine theirs |
	mine := self quadTuples.
	theirs := aDisplayList quadTuples.
	1 to: (mine size max: theirs size) do: [:i | | a b |
		a := i <= mine size ifTrue: [mine at: i].
		b := i <= theirs size ifTrue: [theirs at: i].
		(a notNil and: [b notNil and: [self class tuple: a closeTo: b]]) ifFalse: [^Array with: i with: a with: b]].
	^nil
! !

!DisplayList methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a DisplayList('; print: self quadCount; nextPutAll: ' quads, '; print: batches size; nextPutAll: ' batches)'
! !

!DisplayList class methodsFor: 'vertex format'!
vertexSize
	^40
!
quadSize
	^240
!
modeSolid
	^0
!
modeGlyph
	^1
!
modeImage
	^2
!
modeHalftone
	^3
!
modeStripes
	^4
!
modeLine
	^5
!
explicitPosition
	^16r80000000
!
glyphTemplateLeft: left top: top width: w height: h atlasX: ax atlasY: ay
	"Answer the 40-byte vertex of a glyph quad, relative to the pen (color and origin to be filled in)."
	| t |
	t := ByteArray new: 40.
	t float32At: 1 put: left.
	t float32At: 5 put: top.
	t float32At: 9 put: left + w.
	t float32At: 13 put: top + h.
	t uint32At: 17 put: ax + (ay bitShift: 16).
	t uint32At: 21 put: ax + w + (ay + h bitShift: 16).
	t uint32At: 29 put: self modeGlyph.
	^t
! !

!DisplayList class methodsFor: 'comparing'!
tuple: a closeTo: b
	a size = b size ifFalse: [^false].
	1 to: a size do: [:i | | x y |
		x := a at: i.
		y := b at: i.
		(x isFloat and: [y isFloat])
			ifTrue: [(x - y) abs <= 0.01 ifFalse: [^false]]
			ifFalse: [x = y ifFalse: [^false]]].
	^true
! !

!DisplayList class methodsFor: 'instance creation'!
vertices: aByteArray count: anInteger batches: anArray extent: aPoint scale: aNumber
	^self new setVertices: aByteArray count: anInteger batches: anArray extent: aPoint scale: aNumber
! !
