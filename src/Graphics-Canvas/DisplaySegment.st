Object subclass: #DisplaySegment
	instanceVariableNames: 'vertices byteOffset vertexCount batches parts runStart scale opacity deviceX deviceY clipLeft clipTop clipRight clipBottom volatile glyphGeneration'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

DisplaySegment comment: 'I am a recorded piece of a Canvas''s drawing (Canvas>>record:), to be drawn again on a later Canvas with replay: instead of drawing it anew. I remember the drawing state I was recorded in: scale, opacity, the device origin and the clip. A replay draws me when that state matches: the same scale and opacity, the same clip relative to the origin, and the origin moved by whole device pixels (my batches then carry the move; the Renderer applies it).

I am either a leaf (vertexCount vertices at byteOffset in the vertex bytes of the Canvas I was drawn on last, never copied, and DisplayBatches, first relative to me) or, when other segments were recorded or replayed while I was recorded, a sequence of parts: segments with the move to apply to each. So a segment that contains replayed ones costs no copies.

	| canvas segment |
	canvas := Canvas extent: 400 @ 300 scale: 2.
	segment := canvas record: [canvas fillRect: (0 @ 0 extent: 40 @ 20) color: Color black].
	canvas := Canvas extent: 400 @ 300 scale: 2.
	canvas translateBy: 10 @ 0 during: [canvas replay: segment]     "true: the same quad, 20 device pixels to the right"

volatile: what I show was computed while drawing (Canvas>>noteVolatile); replay: refuses me.'!

!DisplaySegment methodsFor: 'private'!
setScale: s opacity: o deviceX: x deviceY: y clipLeft: l top: t right: r bottom: b
	scale := s.
	opacity := o.
	deviceX := x.
	deviceY := y.
	clipLeft := l.
	clipTop := t.
	clipRight := r.
	clipBottom := b.
	volatile := false
!
setVertices: aByteArray offset: byteIndex count: anInteger batches: anArray
	vertices := aByteArray.
	byteOffset := byteIndex.
	vertexCount := anInteger.
	batches := anArray.
	volatile := false
!
runStart
	"While I am being recorded: the first vertex of the Canvas's drawing not yet in my parts."
	^runStart
!
runStart: vertexIndex
	runStart := vertexIndex
!
addPart: aDisplaySegment dx: x dy: y
	parts isNil ifTrue: [parts := OrderedCollection new].
	parts add: aDisplaySegment; add: x; add: y
!
finish
	"Recording ended: freeze my parts (a single unmoved leaf becomes me)."
	| leaf |
	runStart := nil.
	parts isNil ifTrue: [
		vertexCount := 0.
		batches := #().
		^self].
	(parts size = 3 and: [(parts at: 2) = 0 and: [(parts at: 3) = 0 and: [(leaf := parts first) isLeaf]]]) ifTrue: [
		vertices := leaf vertices.
		byteOffset := leaf byteOffset.
		vertexCount := leaf vertexCount.
		batches := leaf batches.
		parts := nil.
		^self].
	parts := parts asArray
!
beVolatile
	volatile := true
!
glyphGeneration: anObject
	glyphGeneration := anObject
!
vertices: aByteArray offset: byteIndex
	"A leaf was replayed: its vertices are also there now (frozen once that Canvas is done), so the older bytes can go."
	vertices := aByteArray.
	byteOffset := byteIndex
! !

!DisplaySegment methodsFor: 'accessing'!
vertices
	"A leaf's vertex bytes: vertexCount * 40 of them from byteOffset + 1."
	^vertices
!
byteOffset
	^byteOffset
!
vertexCount
	| n |
	parts isNil ifTrue: [^vertexCount].
	n := 0.
	self partsDo: [:each :x :y | n := n + each vertexCount].
	^n
!
quadCount
	^self vertexCount // 6
!
batches
	"A leaf's DisplayBatches (first relative to me)."
	^batches
!
isLeaf
	^parts isNil
!
isEmpty
	^self vertexCount = 0
!
isVolatile
	^volatile
!
glyphGeneration
	"The Canvas glyphsChanged count when I was recorded."
	^glyphGeneration
!
scale
	^scale
!
opacity
	^opacity
!
deviceX
	"The Canvas origin I was recorded at, in device pixels."
	^deviceX
!
deviceY
	^deviceY
!
clipLeft
	"The Canvas clip I was recorded in (device pixels)."
	^clipLeft
!
clipTop
	^clipTop
!
clipRight
	^clipRight
!
clipBottom
	^clipBottom
! !

!DisplaySegment methodsFor: 'enumerating'!
partsDo: aBlock
	"Evaluate aBlock with each part and its move (device pixels)."
	1 to: parts size by: 3 do: [:i | aBlock value: (parts at: i) value: (parts at: i + 1) value: (parts at: i + 2)]
! !

!DisplaySegment methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a DisplaySegment('; print: self quadCount; nextPutAll: ' quads'.
	parts isNil ifFalse: [aStream nextPutAll: ', '; print: parts size // 3; nextPutAll: ' parts'].
	volatile ifTrue: [aStream nextPutAll: ', volatile'].
	aStream nextPut: $)
! !

!DisplaySegment class methodsFor: 'instance creation'!
scale: s opacity: o deviceX: x deviceY: y clipLeft: l top: t right: r bottom: b
	^self new setScale: s opacity: o deviceX: x deviceY: y clipLeft: l top: t right: r bottom: b
!
vertices: aByteArray offset: byteIndex count: anInteger batches: anArray
	^self new setVertices: aByteArray offset: byteIndex count: anInteger batches: anArray
! !
