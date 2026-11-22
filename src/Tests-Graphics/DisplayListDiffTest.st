GraphicsTestCase subclass: #DisplayListDiffTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Graphics'!

DisplayListDiffTest comment: 'Tests DisplayListDiff: equal drawings damage nothing (also drawn into a reused buffer), a moved or recolored quad damages its old and new bounds, appended text only the new glyphs, a Form changed in place the quads that show it, a Surface always unless stableSurfaces; and that rendering only the damage (Renderer within:) gives the pixels of rendering whole.'!

!DisplayListDiffTest methodsFor: 'support'!
listWith: aBlock
	^self listWith: aBlock buffer: nil
!
listWith: aBlock buffer: aByteArrayOrNil
	| c |
	"Drawn once before: glyphs new to the atlas (or an atlas started again, full) would land elsewhere the first time."
	aBlock value: (Canvas extent: 200 @ 100 scale: 2).
	c := aByteArrayOrNil isNil
		ifTrue: [Canvas extent: 200 @ 100 scale: 2]
		ifFalse: [Canvas extent: 200 @ 100 scale: 2 buffer: aByteArrayOrNil].
	c fillRect: (0 @ 0 extent: 200 @ 100) color: Color white.
	aBlock value: c.
	^c displayList
!
damageFrom: a to: b
	| d |
	d := DisplayListDiff region: (DamageRegion extent: 400 @ 200).
	d diff: a stamps: (DisplayListDiff stampsOf: a) to: b stamps: (DisplayListDiff stampsOf: b).
	^d region
!
drawAllKindsOn: c form: aForm
	c line: 0 @ 0 to: 100 @ 90 color: Color black width: 1.
	(self text: 'hello') value: c.
	c pattern: #halftone in: (100 @ 0 extent: 20 @ 20).
	c pattern: #stripes in: (120 @ 0 extent: 20 @ 20).
	c image: aForm in: (150 @ 0 extent: 8 @ 8).
	c clip: (0 @ 0 extent: 50 @ 50) during: [c fillRect: (40 @ 40 extent: 20 @ 20) color: Color ultramarine]
!
text: aString
	^[:c |
		c fillRect: (10 @ 10 extent: 20 @ 20) color: Color black.
		c drawString: aString at: 5 @ 50 font: Font ui color: Color black.
		c fillRect: (150 @ 70 extent: 20 @ 20) color: Color ultramarine]
! !

!DisplayListDiffTest methodsFor: 'tests'!
testSameDrawingNoDamage
	self assert: (self damageFrom: (self listWith: (self text: 'hello')) to: (self listWith: (self text: 'hello'))) isEmpty
!
testReusedBufferNoDamage
	"Drawn into a buffer full of another drawing's bytes: the same bytes all the same."
	| buffer a b form |
	buffer := ByteArray new: 65536.
	form := Form width: 4 height: 4.
	a := self listWith: [:c | self drawAllKindsOn: c form: form] buffer: buffer.
	buffer := ByteArray new: 65536 withAll: 255.
	b := self listWith: [:c | self drawAllKindsOn: c form: form] buffer: buffer.
	self assert: (self damageFrom: a to: b) isEmpty
!
testMovedQuad
	| r |
	r := self damageFrom: (self listWith: [:c | c fillRect: (10 @ 10 extent: 20 @ 20) color: Color black])
		to: (self listWith: [:c | c fillRect: (100 @ 10 extent: 20 @ 20) color: Color black]).
	self assert: r rects asSet equals: (Set with: (20 @ 20 corner: 60 @ 60) with: (200 @ 20 corner: 240 @ 60))
!
testRecoloredQuad
	| r |
	r := self damageFrom: (self listWith: [:c | c fillRect: (10 @ 10 extent: 20 @ 20) color: Color black])
		to: (self listWith: [:c | c fillRect: (10 @ 10 extent: 20 @ 20) color: Color ultramarine]).
	self assert: r rects equals: (Array with: (20 @ 20 corner: 60 @ 60))
!
testAppendedTextDamagesTheNewGlyphOnly
	| r |
	r := self damageFrom: (self listWith: (self text: 'hello')) to: (self listWith: (self text: 'hello?')).
	self deny: r isEmpty.
	self assert: r rects size equals: 1.
	"Right of 'hello', on its line."
	self assert: r rects first left >= ((5 + (Font ui widthOf: 'hello')) * 2 - 2).
	self assert: r rects first top >= 90.
	self assert: r rects first bottom <= 140
!
testChangedFormDamagesItsQuads
	| form a b r |
	form := Form width: 8 height: 8.
	a := self listWith: [:c | c image: form in: (40 @ 40 extent: 8 @ 8)].
	r := DisplayListDiff region: (DamageRegion extent: 400 @ 200).
	b := a.
	r diff: a stamps: (DisplayListDiff stampsOf: a) to: b stamps: (DisplayListDiff stampsOf: b).
	self assert: r region isEmpty.
	form changed.
	r diff: a stamps: #(nil nil) to: b stamps: (DisplayListDiff stampsOf: b).
	self assert: r region rects equals: (Array with: (80 @ 80 extent: 16 @ 16))
!
testSurfaceQuadsUnlessStable
	| surface a b d |
	surface := Surface width: 8 height: 8 scale: 1.
	[a := self listWith: [:c | c image: surface from: (0 @ 0 extent: 8 @ 8) in: (40 @ 40 extent: 8 @ 8)].
	 b := self listWith: [:c | c image: surface from: (0 @ 0 extent: 8 @ 8) in: (40 @ 40 extent: 8 @ 8)].
	 self assert: (self damageFrom: a to: b) rects equals: (Array with: (80 @ 80 extent: 16 @ 16)).
	 d := DisplayListDiff region: (DamageRegion extent: 400 @ 200).
	 d stableSurfaces: true.
	 d diff: a stamps: (DisplayListDiff stampsOf: a) to: b stamps: (DisplayListDiff stampsOf: b).
	 self assert: d region isEmpty]
		ensure: [surface release]
!
testRenderWithinDamageIsRenderingWhole
	"Render a, then b only where it differs: the pixels of rendering b whole."
	| a b damage partial whole renderer |
	a := self listWith: [:c | (self text: 'hello') value: c. c line: 0 @ 95 to: 200 @ 96 color: Color black width: 1. c fillRect: (60 @ 60 extent: 30 @ 10) color: (Color black alpha: 0.5)].
	b := self listWith: [:c | (self text: 'hellp world') value: c. c line: 0 @ 95 to: 200 @ 96 color: Color black width: 1. c fillRect: (62 @ 61 extent: 30 @ 10) color: (Color black alpha: 0.5)].
	damage := self damageFrom: a to: b.
	self deny: damage isEmpty.
	self deny: damage isFull.
	renderer := Renderer default.
	partial := Surface width: 400 height: 200 scale: 2.
	whole := Surface width: 400 height: 200 scale: 2.
	[| cmd |
	 renderer render: a on: partial clear: Color paper.
	 cmd := renderer device commandBuffer.
	 renderer fill: damage scissors color: Color paper into: partial texture commandBuffer: cmd.
	 renderer render: b into: partial texture clear: nil commandBuffer: cmd within: damage scissors.
	 cmd submit.
	 renderer render: b on: whole clear: Color paper.
	 self assert: partial readbackBytes = whole readbackBytes]
		ensure: [partial release. whole release]
! !
