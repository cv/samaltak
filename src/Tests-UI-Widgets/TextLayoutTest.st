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
!
testEditsLayOutOnlyTheirLines
	"Rows after edits are the rows laid out from scratch, the scroll bar coming and going included."
	| fresh line many |
	line := 'word word word word word word 日本語の文 word', self lf.
	many := String new: 20 streamContents: [:s | 10 timesRepeat: [s nextPut: $a; nextPut: Character lf]].
	buffer string: line, line, 'short', self lf, line.
	layout := TextLayout on: buffer in: (0 @ 0 extent: 160 @ 200).
	layout rowCount.
	{#(3 3 'x'). #(40 41 ''). #(10 10 'é漢字'). {0. 0. 'new', self lf}. #(50 70 ''). {5. 5. many}. #(0 30 '')} do: [:e |
			buffer replaceFrom: ((e at: 1) min: buffer size) to: ((e at: 2) min: buffer size) with: (e at: 3).
			fresh := TextLayout on: (TextBuffer string: buffer string) in: (0 @ 0 extent: 160 @ 200).
			fresh rowCount.
			layout ensureRows.
			self assert: layout rowStarts equals: fresh rowStarts.
			self assert: layout rowEnds equals: fresh rowEnds]
!
testRandomEditsMatchAFreshLayout
	"Hundreds of seeded random edits (inserts, deletes and replacements of line feeds, tabs, CJK, combining marks, emoji and long words, at the ends and across lines), wrapped at a narrow width with the text growing taller than the view and shrinking back, and not wrapped: after each, the rows are those of a layout from scratch."
	| view |
	view := 0 @ 0 extent: 130 @ 160.
	{true. false} do: [:wrapping |
		| rng tall flips |
		rng := Random seed: 4711.
		buffer string: 'hello world'.
		layout := TextLayout on: buffer in: view.
		layout wrap: wrapping.
		layout rowCount.
		tall := false.
		flips := 0.
		400 timesRepeat: [
			"one to three edits between layouts, as between frames"
			(rng nextInt: 3) timesRepeat: [self randomEditWith: rng].
			self assertRowsAreFreshIn: view wrap: wrapping.
			(layout contentHeight > view height) = tall ifFalse: [
				tall := tall not.
				flips := flips + 1]].
		self assert: flips >= 10]
!
testPositionsFollowTheFontsAdvances
	"On a row of CJK, a combining mark and emoji, x of a position is what Font>>widthOf: measures (as Canvas draws); the position at an x is the nearest cluster boundary, never inside é (e + U+0301) or 👍🏽."
	| text f boundaries hits |
	text := 'a日本e', (String with: (Character value: 16r301)), 'x', (String with: (Character value: 16r1F44D) with: (Character value: 16r1F3FD)), 'z'.
	buffer string: text.
	f := layout font.
	self deny: (layout isMonoLine: 1).
	self assert: (layout xOf: 4) equals: (layout xOf: 5).
	boundaries := (0 to: text size) select: [:i | text isGraphemeClusterBoundaryAt: i].
	self assert: boundaries asArray equals: #(0 1 2 3 5 6 8 9).
	boundaries do: [:i |
		self assert: ((layout xOf: i) - (f widthOf: (text first: i))) abs < 0.001.
		self assert: (layout positionInRow: 1 atX: (f widthOf: (text first: i)) + 0.01) equals: i].
	hits := ((0 to: ((f widthOf: text) + 10) * 4) collect: [:x | layout positionInRow: 1 atX: x / 4]) asSet.
	self assert: hits asSortedCollection asArray equals: boundaries asArray.
	self assert: ((layout rectsFrom: 1 to: 3) first width - (f widthOf: '日本')) abs < 0.001.
	buffer string: 'hello'.
	self assert: (layout isMonoLine: 1)
!
testWrapsCJKBetweenIdeographsAndClusters
	"A line without spaces breaks between ideographs (not before 、), and between clusters (flags) where nothing else breaks."
	| text flag w |
	text := String new: 60 streamContents: [:s | 1 to: 30 do: [:i | s nextPut: (Character value: 16r6F22). i \\ 4 = 0 ifTrue: [s nextPut: (Character value: 16r3001)]]].
	buffer string: text.
	layout := TextLayout on: buffer in: (0 @ 0 extent: 150 @ 1000).
	w := layout availableTextWidth.
	self assert: layout rowCount > 3.
	1 to: layout rowCount do: [:r |
		self assert: (layout xOf: (layout rowEnd: r) inRow: r) <= w.
		r > 1 ifTrue: [
			self assert: (layout rowStart: r) equals: (layout rowEnd: r - 1).
			self deny: (text at: (layout rowStart: r) + 1) value = 16r3001]].
	flag := String with: (Character value: 16r1F1E9) with: (Character value: 16r1F1EA).
	text := String new: 80 streamContents: [:s | 20 timesRepeat: [s nextPutAll: flag]].
	buffer string: 'x', text.
	self assert: layout rowCount > 1.
	2 to: layout rowCount do: [:r | self assert: (layout rowStart: r) odd]
!
testWrapsColorEmojiWhole
	"A line of family emoji (ZWJ sequences of 7 characters, one color glyph each) breaks only between them; x is what the font measures, one em each."
	| family f w |
	family := String withAll: (#(16r1F468 16r200D 16r1F469 16r200D 16r1F467 16r200D 16r1F466) collect: [:cp | Character value: cp]).
	buffer string: 'x', (String new: 140 streamContents: [:s | 20 timesRepeat: [s nextPutAll: family]]).
	layout := TextLayout on: buffer in: (0 @ 0 extent: 150 @ 1000).
	f := layout font.
	w := layout availableTextWidth.
	self assert: layout rowCount > 1.
	2 to: layout rowCount do: [:r | self assert: (layout rowStart: r) - 1 \\ 7 equals: 0].
	1 to: layout rowCount do: [:r | self assert: (layout xOf: (layout rowEnd: r) inRow: r) <= w].
	self assert: (layout xOf: 8) closeTo: (f widthOf: 'x') + f size.
	self assert: (layout positionInRow: 1 atX: (layout xOf: 1) + (f size * 0.4)) equals: 1.
	self assert: (layout positionInRow: 1 atX: (layout xOf: 1) + (f size * 0.6)) equals: 8.
	"a row exactly 5 em wide holds 5 of them"
	buffer string: (String new: 70 streamContents: [:s | 10 timesRepeat: [s nextPutAll: family]]).
	layout := TextLayout on: buffer in: (0 @ 0 extent: 5 * f size + (2 * layout padX) + 0.01 @ 1000).
	self assert: layout rowCount equals: 2.
	self assert: (layout rowStart: 2) equals: 35.
	self assert: (layout xOf: 35 inRow: 1) closeTo: 5 * f size
! !

!TextLayoutTest methodsFor: 'support'!
randomPieceWith: rng
	"A short string: ASCII, a long word, white space, line feeds, CJK and its punctuation, combining marks, emoji (a ZWJ family among them), a flag, or several lines."
	| c pieces |
	c := [:cp | String with: (Character value: cp)].
	pieces := {
		'x'.
		'word '.
		'abcdefghijklmnopqrstuvwxyz'.
		String with: Character tab.
		self lf.
		self lf , self lf.
		(c value: 16r6F22) , (c value: 16r5B57) , (c value: 16r7DE8) , (c value: 16r8F2F).
		(c value: 16r3001) , (c value: 16r300C) , (c value: 16r6E2C) , (c value: 16r300D).
		'e' , (c value: 16r301) , (c value: 16r308).
		(c value: 16rD55C) , (c value: 16rAE00) , ' '.
		(c value: 16r1F600) , (c value: 16r1F44D) , (c value: 16r1F3FD) , (String withAll: (#(16r1F468 16r200D 16r1F469 16r200D 16r1F467 16r200D 16r1F466) collect: [:cp | Character value: cp])).
		(c value: 16r1F1E9) , (c value: 16r1F1EA).
		'one ' , (c value: 16r65E5) , self lf , 'two' , (String with: Character tab) , 'three' , self lf.
		'word word word word word word word word'}.
	^pieces at: (rng nextInt: pieces size)
!
randomEditWith: rng
	"Insert, delete or replace at a random place (often at either end); only delete once the text is long, so it grows and shrinks."
	| size kind a b |
	size := buffer size.
	kind := size = 0 ifTrue: [1] ifFalse: [size > 400 ifTrue: [2] ifFalse: [#(1 1 2 3) at: (rng nextInt: 4)]].
	a := #(0 0 1 1 1 1 1 2) at: (rng nextInt: 8).
	a := a = 0 ifTrue: [0] ifFalse: [a = 2 ifTrue: [size] ifFalse: [(rng nextInt: size + 1) - 1]].
	kind = 1 ifTrue: [^buffer replaceFrom: a to: a with: (self randomPieceWith: rng)].
	a = size ifTrue: [a := (rng nextInt: size) - 1].
	b := (rng nextInt: 4) = 1
		ifTrue: [a + (rng nextInt: 120) min: size]
		ifFalse: [a + (rng nextInt: 3) min: size].
	kind = 2 ifTrue: [^buffer replaceFrom: a to: b with: ''].
	buffer replaceFrom: a to: b with: (self randomPieceWith: rng)
!
assertRowsAreFreshIn: aRectangle wrap: aBoolean
	"The layout's rows are those of a layout from scratch of the buffer's text."
	| fresh |
	fresh := TextLayout on: (TextBuffer string: buffer string) in: aRectangle.
	fresh wrap: aBoolean.
	fresh ensureRows.
	layout ensureRows.
	self assert: layout rowStarts equals: fresh rowStarts.
	self assert: layout rowEnds equals: fresh rowEnds
! !
