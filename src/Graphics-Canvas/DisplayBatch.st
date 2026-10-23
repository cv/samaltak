Object subclass: #DisplayBatch
	instanceVariableNames: 'texture scissor first count dx dy'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

DisplayBatch comment: 'I am a run of vertices of a DisplayList drawn with one texture source (a GlyphAtlasPage, Form or Surface, or nil when only solid and pattern quads are in me) and one scissor rectangle ({x. y. w. h} in device pixels, or nil for the whole target). dx and dy (whole device pixels, usually 0) move my vertices: a replayed DisplaySegment that moved since it was recorded.'!

!DisplayBatch methodsFor: 'private'!
setTexture: aTextureSource scissor: anArrayOrNil first: firstVertex
	texture := aTextureSource.
	scissor := anArrayOrNil.
	first := firstVertex.
	count := 0.
	dx := 0.
	dy := 0
!
setTexture: aTextureSource scissor: anArrayOrNil first: firstVertex count: vertexCount dx: x dy: y
	texture := aTextureSource.
	scissor := anArrayOrNil.
	first := firstVertex.
	count := vertexCount.
	dx := x.
	dy := y
!
texture: aTextureSource
	texture := aTextureSource
!
count: anInteger
	count := anInteger
! !

!DisplayBatch methodsFor: 'accessing'!
texture
	^texture
!
scissor
	^scissor
!
first
	"0-based index of my first vertex."
	^first
!
count
	"Number of vertices."
	^count
!
dx
	"Device pixels added to my vertices' x."
	^dx
!
dy
	^dy
! !

!DisplayBatch methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a DisplayBatch('; print: first; nextPutAll: '+'; print: count.
	texture isNil ifFalse: [aStream space; print: texture].
	scissor isNil ifFalse: [aStream nextPutAll: ' scissor '; print: scissor].
	(dx = 0 and: [dy = 0]) ifFalse: [aStream nextPutAll: ' moved '; print: dx @ dy].
	aStream nextPut: $)
! !

!DisplayBatch class methodsFor: 'instance creation'!
texture: aTextureSource scissor: anArrayOrNil first: firstVertex
	^self new setTexture: aTextureSource scissor: anArrayOrNil first: firstVertex
!
texture: aTextureSource scissor: anArrayOrNil first: firstVertex count: vertexCount dx: x dy: y
	^self new setTexture: aTextureSource scissor: anArrayOrNil first: firstVertex count: vertexCount dx: x dy: y
! !
