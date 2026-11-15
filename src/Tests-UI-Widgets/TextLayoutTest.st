TestCase subclass: #TextLayoutTest
	instanceVariableNames: 'buffer layout'
	classVariableNames: ''
	package: 'Tests-UI-Widgets'!

TextLayoutTest comment: 'I test TextLayout headlessly (the view is a Rectangle): column to x and back, tab stops, soft wrapping, caret and range rectangles, the scroll extent and offset, and rows following buffer edits.'!

!TextLayoutTest methodsFor: 'running'!
setUp
	buffer := TextBuffer string: 'hello world'.
	layout := TextLayout on: buffer in: (0 @ 0 extent: 300 @ 100)
!
lf
	^String with: Character lf
!
advance
	^layout font advanceOf: $m
! !

!TextLayoutTest methodsFor: 'tests'!
testFontFollowsDeviceScale
	| saved |
	saved := Font deviceScale.
	[Font deviceScale: saved * 2.
	 self assert: layout font scale equals: saved * 2.
	 self assert: (Theme current font: #code) scale equals: saved * 2]
		ensure: [Font deviceScale: saved]
!
testColumnToX
	self deny: layout monoAdvance == false.
	self assert: (layout xOf: 0) equals: 0.
	self assert: (layout xOf: 5) equals: 5 * self advance.
	layout font: #ui.
	self assert: layout monoAdvance equals: false.
	self assert: (layout xOf: 3) equals: ('hel' inject: 0 into: [:x :c | x + (layout font advanceOf: c)])
!
testXToColumn
	| x |
	x := layout xOf: 3.
	self assert: (layout positionInRow: 1 atX: x + 0.1) equals: 3.
	self assert: (layout positionInRow: 1 atX: x - (0.4 * self advance)) equals: 3.
	self assert: (layout positionInRow: 1 atX: x + (0.6 * self advance)) equals: 4.
	self assert: (layout positionInRow: 1 atX: 1000) equals: 11.
	self assert: (layout positionAt: (layout textLeft + x) @ (layout padY + 1)) equals: 3.
	self assert: (layout positionAt: 50 @ -5) equals: 0
!
testTabStops
	buffer string: (String with: Character tab), 'ab'.
	self assert: (layout xOf: 1) equals: layout tabStopWidth.
	self assert: (layout xOf: 2) equals: layout tabStopWidth + self advance.
	self assert: (layout nextTabStop: 1) equals: layout tabStopWidth.
	self assert: (layout nextTabStop: layout tabStopWidth) equals: 2 * layout tabStopWidth
!
testWrapping
	| text |
	text := (1 to: 20) inject: '' into: [:s :i | s, 'word '].
	buffer string: text.
	layout := TextLayout on: buffer in: (0 @ 0 extent: 120 @ 1000).
	self assert: layout rowCount > 1.
	2 to: layout rowCount do: [:r |
		self assert: (layout rowStart: r) equals: (layout rowEnd: r - 1).
		self assert: (buffer at: (layout rowStart: r)) equals: $ ].
	self assert: (layout rowOf: (layout rowStart: 2)) equals: 2.
	self assert: (layout xOf: (layout rowStart: 2)) equals: 0.
	layout wrap: false.
	self assert: layout rowCount equals: 1
!
testCaretAndRangeRectangles
	| r rects |
	buffer string: 'ab', self lf, 'cd'.
	r := layout caretRectAt: 0.
	self assert: r left equals: layout textLeft - 0.5.
	self assert: r top equals: layout padY.
	self assert: r height equals: layout lineHeight.
	self assert: (layout caretRectAt: 3) top equals: layout padY + layout lineHeight.
	rects := layout rectsFrom: 0 to: buffer size.
	self assert: rects size equals: 2.
	self assert: rects first width closeTo: 3 * self advance.
	self assert: rects last width closeTo: 2 * self advance.
	self assert: (layout rectsFrom: 1 to: 1) isEmpty
!
testScrollExtent
	| lh padY |
	buffer string: (String new: 49 withAll: Character lf).
	lh := layout lineHeight.
	padY := layout padY.
	self assert: layout contentHeight equals: 50 * lh + (2 * padY).
	self assert: layout maxScrollOffset equals: (layout wholeLines: layout contentHeight - 100).
	self assert: layout scrollTotal >= layout contentHeight.
	self assert: (layout clampedOffset: 1000000) equals: layout maxScrollOffset.
	self assert: (layout clampedOffset: -5) equals: 0.
	self assert: (layout wholeLines: padY) equals: padY.
	self assert: (layout wholeLines: padY + 1) equals: lh + padY.
	self assert: layout visibleRowCount equals: (100 - (2 * padY) / lh) floor.
	layout offset: 3 * lh + padY.
	self assert: (layout rowAtY: padY) equals: 4.
	self assert: (layout caretRectAt: 3) top equals: 0
!
testRowsFollowBufferEdits
	self assert: layout rowCount equals: 1.
	buffer replaceFrom: 5 to: 6 with: self lf.
	self assert: layout rowCount equals: 2.
	self assert: (layout rowStart: 2) equals: 6.
	buffer string: ''.
	self assert: layout rowCount equals: 1
! !
