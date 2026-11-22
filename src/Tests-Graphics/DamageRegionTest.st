TestCase subclass: #DamageRegionTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Graphics'!

DamageRegionTest comment: 'Tests DamageRegion''s merge policy: neighbours join, far rectangles stay apart (a dragged window''s old and new rectangle), beyond maxRects the cheapest pair merges, past half the bounds it is full; clipping and rounding outwards.'!

!DamageRegionTest methodsFor: 'tests'!
testNeighboursJoin
	| d |
	d := DamageRegion extent: 1920 @ 1080.
	d add: (10 @ 10 extent: 20 @ 16); add: (34 @ 10 extent: 8 @ 16).
	self assert: d rects equals: (Array with: (10 @ 10 corner: 42 @ 26))
!
testFarRectanglesStayApart
	"A window dragged: its old and its new rectangle, not their bounding box."
	| d |
	d := DamageRegion extent: 1920 @ 1080.
	d add: (100 @ 100 extent: 300 @ 200); add: (700 @ 400 extent: 300 @ 200).
	self assert: d rects size equals: 2.
	self assert: d area equals: 2 * 300 * 200
!
testOverlappingDragJoinsWhenCheap
	| d |
	d := DamageRegion extent: 1920 @ 1080.
	d add: (100 @ 100 extent: 300 @ 200); add: (110 @ 104 extent: 300 @ 200).
	self assert: d rects equals: (Array with: (100 @ 100 corner: 410 @ 304))
!
testContainedIsAbsorbed
	| d |
	d := DamageRegion extent: 1920 @ 1080.
	d add: (100 @ 100 extent: 300 @ 200); add: (150 @ 150 extent: 10 @ 10).
	self assert: d rects equals: (Array with: (100 @ 100 extent: 300 @ 200))
!
testClipAndRoundOutwards
	| d |
	d := DamageRegion extent: 100 @ 100.
	d add: (-10.5 @ 20.25 corner: 30.5 @ 40.75).
	self assert: d rects equals: (Array with: (0 @ 20 corner: 31 @ 41)).
	d add: (200 @ 200 extent: 10 @ 10).
	self assert: d rects size equals: 1
!
testMaxRects
	| d |
	d := DamageRegion extent: 1920 @ 1080.
	d maxRects: 3.
	0 to: 5 do: [:i | d add: ((i * 200) @ 0 extent: 10 @ 10)].
	self assert: d rects size <= 3.
	0 to: 5 do: [:i | self assert: (d rects anySatisfy: [:r | r containsRect: ((i * 200) @ 0 extent: 10 @ 10)])]
!
testFullPastHalf
	| d |
	d := DamageRegion extent: 100 @ 100.
	d add: (0 @ 0 extent: 100 @ 40).
	self deny: d isFull.
	d add: (0 @ 60 extent: 100 @ 20).
	self assert: d isFull.
	self assert: d rects equals: (Array with: (0 @ 0 extent: 100 @ 100)).
	self assert: d scissors equals: #(#(0 0 100 100))
!
testEmpty
	| d |
	d := DamageRegion extent: 100 @ 100.
	self assert: d isEmpty.
	self assert: d area equals: 0.
	d add: (10 @ 10 extent: 0 @ 5).
	self assert: d isEmpty
! !
