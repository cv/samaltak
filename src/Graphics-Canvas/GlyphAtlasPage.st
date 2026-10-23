Object subclass: #GlyphAtlasPage
	instanceVariableNames: 'size pixels shelves dirtyTop dirtyBottom texture uploadedGeneration'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

GlyphAtlasPage comment: 'I am one square R8 page of a GlyphAtlas: the CPU copy of the coverage (pixels, a ByteArray, rows top to bottom), shelf packing state, and the GPU texture, which I upload when rows changed (only the dirty band) or when the texture lost its contents (new session).'!

!GlyphAtlasPage methodsFor: 'initialization'!
setSize: anInteger
	size := anInteger.
	pixels := ByteArray new: anInteger * anInteger.
	shelves := OrderedCollection new.
	dirtyTop := nil.
	uploadedGeneration := nil
! !

!GlyphAtlasPage methodsFor: 'accessing'!
size
	^size
!
pixels
	^pixels
!
coverageAtX: x y: y
	"0-based pixel coordinates."
	^pixels at: y * size + x + 1
!
usedHeight
	shelves isEmpty ifTrue: [^0].
	^(shelves last at: 1) + (shelves last at: 2)
! !

!GlyphAtlasPage methodsFor: 'packing'!
allocateWidth: w height: h
	"Answer the 0-based top-left (x@y) of a free w×h area (keeping 1 px of padding), or nil if I am full."
	| pw ph shelf y x |
	pw := w + 1.
	ph := h + 1.
	pw > size ifTrue: [^nil].
	shelves do: [:each |
		"each is {y. height. nextX}; reuse shelves no more than a third taller than needed"
		((each at: 2) >= ph and: [(each at: 2) * 3 <= (ph * 4 + 3) and: [(each at: 3) + pw <= size]]) ifTrue: [
			x := each at: 3.
			each at: 3 put: x + pw.
			^x @ (each at: 1)]].
	y := self usedHeight.
	y + ph > size ifTrue: [^nil].
	shelf := Array with: y with: ph with: pw.
	shelves add: shelf.
	^0 @ y
!
store: coverage width: w height: h at: aPoint
	"Copy a w×h coverage ByteArray into my pixels at aPoint (0-based)."
	| x y |
	x := aPoint x.
	y := aPoint y.
	0 to: h - 1 do: [:row |
		pixels replaceFrom: (y + row) * size + x + 1 to: (y + row) * size + x + w with: coverage startingAt: row * w + 1].
	dirtyTop isNil
		ifTrue: [dirtyTop := y. dirtyBottom := y + h]
		ifFalse: [dirtyTop := dirtyTop min: y. dirtyBottom := dirtyBottom max: y + h]
! !

!GlyphAtlasPage methodsFor: 'rendering'!
textureOn: aDevice
	"Answer my GPU texture, uploading what changed since the last upload."
	| generation band |
	(texture isNil or: [texture device ~~ aDevice]) ifTrue: [
		texture := aDevice textureWidth: size height: size format: #r8 usage: #(#sampler).
		uploadedGeneration := nil].
	generation := texture generation.
	uploadedGeneration = generation
		ifFalse: [
			texture upload: pixels.
			uploadedGeneration := generation.
			dirtyTop := nil]
		ifTrue: [
			dirtyTop isNil ifFalse: [
				band := pixels copyFrom: dirtyTop * size + 1 to: dirtyBottom * size.
				texture upload: band x: 0 y: dirtyTop width: size height: dirtyBottom - dirtyTop bytesPerRow: size.
				dirtyTop := nil]].
	^texture
!
isLinearFiltered
	"Glyphs are placed on device pixels: sample them exactly."
	^false
! !

!GlyphAtlasPage class methodsFor: 'instance creation'!
size: anInteger
	^self new setSize: anInteger
! !
