Object subclass: #DamageRegion
	instanceVariableNames: 'bounds rects full maxRects fullFraction'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

DamageRegion comment: 'I am what changed in a frame of a target (a layer''s surface, the screen): a few rectangles of device pixels (integer Rectangles within my bounds), or all of it (full). Rectangles added are clipped to my bounds and merged with one they overlap, touch or nearly touch (16 pixels apart: the glyphs of a word) when their union wastes little (at most a quarter of it covers neither), so the glyphs of a typed line become one rectangle while a window dragged far keeps its old and its new rectangle instead of their bounding box. Beyond maxRects (8) the two whose union wastes least are merged; once the rectangles cover more than fullFraction (one half) of my bounds I am full: drawing that much in pieces would cost more than drawing it whole.

	| d |
	d := DamageRegion bounds: (0 @ 0 extent: 1920 @ 1080).
	d add: (10 @ 10 extent: 20 @ 16); add: (30 @ 10 extent: 8 @ 16).
	d rects        "one rectangle, 10@10 corner: 38@26"'!

!DamageRegion methodsFor: 'initialization'!
setBounds: aRectangle
	bounds := aRectangle.
	rects := OrderedCollection new.
	full := false.
	maxRects := 8.
	fullFraction := 0.5
! !

!DamageRegion methodsFor: 'accessing'!
bounds
	^bounds
!
rects
	"The damaged rectangles (all of my bounds when I am full), an Array."
	full ifTrue: [^Array with: bounds].
	^rects asArray
!
maxRects: anInteger
	maxRects := anInteger
!
fullFraction: aNumber
	fullFraction := aNumber
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
area
	"The pixels my rectangles cover (they do not overlap much: merging joins those that do)."
	full ifTrue: [^bounds area].
	^rects inject: 0 into: [:sum :each | sum + each area]
!
scissors
	"My rectangles as {x. y. width. height} Arrays (Renderer scissors)."
	^self rects collect: [:r | Array with: r left with: r top with: r width with: r height]
! !

!DamageRegion methodsFor: 'adding'!
clear
	"Nothing damaged again."
	full := false.
	rects isEmpty ifFalse: [rects := OrderedCollection new]
!
beFull
	full := true.
	rects := OrderedCollection new
!
add: aRectangle
	"Damage aRectangle (device pixels; fractional edges round outwards)."
	^self addLeft: aRectangle left top: aRectangle top right: aRectangle right bottom: aRectangle bottom
!
addLeft: l top: t right: r bottom: b
	"Damage the rectangle l t r b (fractional edges round outwards), clipped to my bounds."
	| x0 y0 x1 y1 |
	full ifTrue: [^self].
	x0 := l floor max: bounds left.
	y0 := t floor max: bounds top.
	x1 := r ceiling min: bounds right.
	y1 := b ceiling min: bounds bottom.
	(x0 < x1 and: [y0 < y1]) ifFalse: [^self].
	self insert: (Rectangle left: x0 right: x1 top: y0 bottom: y1)
!
addAll: aDamageRegion
	"Everything aDamageRegion damages (in the same coordinates)."
	aDamageRegion isFull ifTrue: [^self add: aDamageRegion bounds].
	aDamageRegion rects do: [:each | self add: each]
!
addAll: aDamageRegion translatedBy: aPoint
	aDamageRegion isFull ifTrue: [^self add: (aDamageRegion bounds translateBy: aPoint)].
	aDamageRegion rects do: [:each | self add: (each translateBy: aPoint)]
! !

!DamageRegion methodsFor: 'private'!
insert: aRectangle
	| r merged |
	r := aRectangle.
	(rects anySatisfy: [:each | each containsRect: r]) ifTrue: [^self].
	"Merge with whatever it overlaps or touches cheaply, as long as that goes on."
	[merged := rects detect: [:each | self cheaply: each joins: r] ifNone: [nil].
	 merged notNil] whileTrue: [
		rects remove: merged.
		r := r merge: merged].
	rects := rects reject: [:each | r containsRect: each].
	rects add: r.
	[rects size > maxRects] whileTrue: [self mergeCheapestPair].
	self area > (bounds area * fullFraction) ifTrue: [self beFull]
!
cheaply: a joins: b
	"Whether a and b overlap or are at most 16 pixels apart and their union wastes at most a quarter of itself."
	| union covered |
	(a left <= (b right + 16) and: [b left <= (a right + 16) and: [a top <= (b bottom + 16) and: [b top <= (a bottom + 16)]]]) ifFalse: [^false].
	union := (a merge: b) area.
	covered := a area + b area - (self overlapOf: a with: b).
	^covered * 4 >= (union * 3)
!
overlapOf: a with: b
	| w h |
	w := (a right min: b right) - (a left max: b left).
	h := (a bottom min: b bottom) - (a top max: b top).
	(w > 0 and: [h > 0]) ifFalse: [^0].
	^w * h
!
mergeCheapestPair
	| best bestWaste i j union |
	bestWaste := nil.
	1 to: rects size - 1 do: [:a |
		a + 1 to: rects size do: [:b | | waste ra rb |
			ra := rects at: a.
			rb := rects at: b.
			waste := (ra merge: rb) area - (ra area + rb area - (self overlapOf: ra with: rb)).
			(bestWaste isNil or: [waste < bestWaste]) ifTrue: [bestWaste := waste. i := a. j := b]]].
	union := (rects at: i) merge: (rects at: j).
	rects removeIndex: j.
	rects removeIndex: i.
	self insert: union
! !

!DamageRegion methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a DamageRegion('.
	full
		ifTrue: [aStream nextPutAll: 'full']
		ifFalse: [rects do: [:each | aStream print: each] separatedBy: [aStream nextPutAll: ' ']].
	aStream nextPut: $)
! !

!DamageRegion class methodsFor: 'instance creation'!
bounds: aRectangle
	"Nothing damaged yet within aRectangle (device pixels)."
	^self new setBounds: aRectangle
!
extent: aPoint
	^self bounds: (0 @ 0 extent: aPoint)
! !
