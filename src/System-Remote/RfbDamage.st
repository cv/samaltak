Object subclass: #RfbDamage
	instanceVariableNames: 'bounds rects full maxRects'
	classVariableNames: ''
	package: 'System-Remote'!

RfbDamage comment: 'I am what changed on the screen since an RFB client''s last update (RfbConnection): a few rectangles of pixels within my bounds, or all of it (full). Rectangles added are clipped to my bounds; one that overlaps or nearly touches (16 pixels) another is merged with it when their union wastes little (at most a quarter of it covers neither); beyond maxRects (32: a client pays per byte, not per rectangle) the pair whose union wastes least is merged; past half of my bounds I am full. A client that asks seldom so gets fewer, larger updates, and missed frames cost nothing. Graphics-Canvas'' DamageRegion is the compositor''s like of me (tuned for Blts, and on a higher layer).'!

!RfbDamage methodsFor: 'initialization'!
setBounds: aRectangle
	bounds := aRectangle.
	rects := OrderedCollection new.
	full := false.
	maxRects isNil ifTrue: [maxRects := 32]
! !

!RfbDamage methodsFor: 'accessing'!
bounds
	^bounds
!
bounds: aRectangle
	"The screen changed size: all of it is new."
	self setBounds: aRectangle.
	self beFull
!
maxRects: anInteger
	maxRects := anInteger
!
isFull
	^full
!
isEmpty
	^full not and: [rects isEmpty]
!
notEmpty
	^self isEmpty not
!
rects
	"The rectangles (all of my bounds when I am full)."
	full ifTrue: [^OrderedCollection with: bounds].
	^rects copy
!
area
	^self rects inject: 0 into: [:sum :r | sum + r area]
!
intersects: aRectangle
	^self rects anySatisfy: [:r | r intersects: aRectangle]
! !

!RfbDamage methodsFor: 'adding'!
beFull
	full := true.
	rects := OrderedCollection new
!
reset
	full := false.
	rects := OrderedCollection new
!
add: aRectangle
	| r joined |
	full ifTrue: [^self].
	r := aRectangle intersect: bounds.
	r isEmpty ifTrue: [^self].
	[joined := rects detect: [:each | self cheaply: each joins: r] ifNone: [nil].
	 joined isNil] whileFalse: [
		rects remove: joined.
		r := r merge: joined].
	rects add: r.
	[rects size > maxRects] whileTrue: [self mergeCheapestPair].
	self area * 2 > bounds area ifTrue: [self beFull]
!
addAll: aCollection
	aCollection do: [:each | self add: each]
!
takeWithin: aRectangle
	"Answer my rectangles' parts inside aRectangle and keep only what lies outside it."
	| inside outside |
	inside := OrderedCollection new.
	outside := OrderedCollection new.
	self rects do: [:r | | i |
		i := r intersect: aRectangle.
		i isEmpty
			ifTrue: [outside add: r]
			ifFalse: [
				inside add: i.
				(r areasOutside: aRectangle) do: [:each | each isEmpty ifFalse: [outside add: each]]]].
	self reset.
	outside do: [:each | self add: each].
	^inside
! !

!RfbDamage methodsFor: 'private'!
cheaply: a joins: b
	| u |
	((a expandBy: 16) intersects: b) ifFalse: [^false].
	(a containsRect: b) | (b containsRect: a) ifTrue: [^true].
	u := a merge: b.
	^(u area - (a area + b area - (self overlapOf: a with: b))) * 4 <= u area
!
overlapOf: a with: b
	| i |
	i := a intersect: b.
	^i isEmpty ifTrue: [0] ifFalse: [i area]
!
mergeCheapestPair
	| best bestWaste i j |
	bestWaste := nil.
	1 to: rects size - 1 do: [:m |
		m + 1 to: rects size do: [:n | | a b waste |
			a := rects at: m.
			b := rects at: n.
			waste := (a merge: b) area - a area - b area + (self overlapOf: a with: b).
			(bestWaste isNil or: [waste < bestWaste]) ifTrue: [bestWaste := waste. i := m. j := n]]].
	best := (rects at: i) merge: (rects at: j).
	rects removeIndex: j.
	rects at: i put: best
! !

!RfbDamage methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'RfbDamage '.
	full ifTrue: [^aStream nextPutAll: 'full'].
	aStream print: rects size; nextPutAll: ' rects'
! !

!RfbDamage class methodsFor: 'instance creation'!
bounds: aRectangle
	^self new setBounds: aRectangle
!
extent: aPoint
	^self bounds: (0 @ 0 extent: aPoint)
! !
