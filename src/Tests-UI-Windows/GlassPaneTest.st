TestCase subclass: #GlassPaneTest
	instanceVariableNames: 'pane'
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

GlassPaneTest comment: 'Tests GlassPane: colors premultiplied for the window''s own pixels, and the rectangles a fill, a frame and a pill become, on a hidden pane.'!

!GlassPaneTest methodsFor: 'running'!
tearDown
	pane isNil ifFalse: [pane close].
	super tearDown
! !

!GlassPaneTest methodsFor: 'tests'!
testColorsArePremultiplied
	self assert: (GlassPane rgbaOf: (Color r: 1 g: 0 b: 0 a: 0.5)) equals: 16r80000080.
	self assert: (GlassPane rgbaOf: (Color r: 0 g: 0 b: 1 a: 1)) equals: 16r0000FFFF.
	self assert: (GlassPane rgbaOf: Color transparent) equals: 0
!
testShapes
	"Rectangles in pixels (x y w h rgba): a fill, a frame of four that do not overlap, a pill row by row with rounded ends."
	| s rows |
	pane := GlassPane extent: 200 @ 100 title: 'Glass' desktop: true hidden: true.
	s := pane scale.
	pane show: [:p | p fillRect: (10 @ 10 extent: 30 @ 20) color: Color black].
	self assert: pane shown equals: {(10 * s) rounded. (10 * s) rounded. (30 * s) rounded. (20 * s) rounded. 16r000000FF}.
	pane show: [:p | p strokeRect: (0 @ 0 extent: 50 @ 40) color: Color black width: 1].
	self assert: pane shown size equals: 4 * 5.
	self assert: ((1 to: 4) inject: 0 into: [:sum :i | sum + ((pane shown at: i - 1 * 5 + 3) * (pane shown at: i - 1 * 5 + 4))])
		equals: ((50 * s) rounded * (40 * s) rounded) - ((48 * s) rounded * (38 * s) rounded).
	pane show: [:p | p fillPill: (0 @ 0 extent: 100 @ 6) color: Color black].
	rows := (1 to: pane shown size by: 5) collect: [:i | pane shown copyFrom: i to: i + 4].
	self assert: rows size equals: (6 * s) rounded.
	"the middle rows are the widest, the outer ones inset"
	self assert: (rows first at: 3) < (rows at: rows size // 2 + 1) third.
	self assert: (rows at: rows size // 2 + 1) third equals: (100 * s) rounded.
	pane clear.
	self assert: pane shown isEmpty
! !
