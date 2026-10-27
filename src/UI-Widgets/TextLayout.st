Object subclass: #TextLayout
	instanceVariableNames: 'buffer view fontSpec font lineHeight monoAdvance wrap rowStarts rowEnds layoutWidth offset gutter'
	classVariableNames: ''
	package: 'UI-Widgets'!

TextLayout comment: 'I lay out a TextBuffer in a view (an object answering width and height, the TextEditor): rows (lines soft-wrapped at white space to the view''s width less the padding and the gutter, and less the scroll bar when the text is taller than the view), each a line high in my font; x of a gap position in its row and the position nearest to an x (tabs to the Theme''s tab stops); the vertical scroll offset; and the rectangles of the caret and of character ranges in view coordinates. Rows are computed lazily and dropped on every buffer change or when the width changes.

	(TextLayout on: (TextBuffer string: ''abc'') in: (0 @ 0 extent: 200 @ 100)) xOf: 2   "the width of ab"'!

!TextLayout methodsFor: 'initialization'!
initialize
	wrap := true.
	offset := 0.
	gutter := 0
!
buffer: aTextBuffer view: aView
	"Lay out aTextBuffer (following its changes) in aView."
	buffer := aTextBuffer.
	view := aView.
	rowStarts := nil.
	aTextBuffer addListener: self
! !

!TextLayout methodsFor: 'accessing'!
theme
	^Theme current
!
font
	| spec |
	font isNil ifFalse: [^font].
	spec := fontSpec ifNil: [#code].
	^font := spec isSymbol ifTrue: [self theme font: spec] ifFalse: [spec]
!
font: aFontOrSymbol
	"A Font, or a Theme font role (default #code)."
	fontSpec := aFontOrSymbol.
	font := nil.
	lineHeight := nil.
	monoAdvance := nil.
	rowStarts := nil
!
wrap
	^wrap
!
wrap: aBoolean
	wrap := aBoolean.
	rowStarts := nil
!
gutter: points
	"Leave points of room left of the text (line numbers)."
	gutter = points ifTrue: [^self].
	gutter := points.
	rowStarts := nil
!
invalidate
	"Forget the rows."
	rowStarts := nil
!
offset
	"The vertical scroll offset in points."
	^offset
!
offset: points
	offset := points
! !

!TextLayout methodsFor: 'buffer changes'!
textReset
	rowStarts := nil
!
textReplacedFrom: start to: stop with: aString
	rowStarts := nil
! !

!TextLayout methodsFor: 'geometry'!
padX
	^self theme metric: #editorPaddingX
!
padY
	^self theme metric: #editorPaddingY
!
lineHeight
	^lineHeight ifNil: [lineHeight := self font lineHeight]
!
textLeft
	^self padX + gutter
!
tabStopWidth
	^(self font advanceOf: $ ) * (self theme metric: #tabWidth)
!
nextTabStop: x
	| w |
	w := self tabStopWidth.
	^((x / w) floor + 1) * w
!
availableTextWidth
	^view width - (2 * self padX) - gutter
!
monoAdvance
	"The advance of every character if my font is monospaced, else false."
	| f a |
	monoAdvance isNil ifFalse: [^monoAdvance].
	f := self font.
	a := f advanceOf: $m.
	^monoAdvance := ((f advanceOf: $i) = a and: [(f advanceOf: $W) = a]) ifTrue: [a] ifFalse: [false]
!
xFrom: start to: stop startX: x
	"x (relative to the text left) after the characters start + 1 .. stop (within one line), starting at x."
	| tab f result mono text |
	stop <= start ifTrue: [^x].
	mono := self monoAdvance.
	(mono ~~ false and: [(buffer tabCountOfLine: (buffer lineIndexOf: start)) = 0]) ifTrue: [^x + ((stop - start) * mono)].
	tab := Character tab.
	f := self font.
	text := buffer string.
	result := x.
	start + 1 to: stop do: [:i |
		| c |
		c := text at: i.
		result := c == tab ifTrue: [self nextTabStop: result] ifFalse: [result + (f advanceOf: c)]].
	^result
!
xOf: aPosition inRow: r
	^self xFrom: (self rowStart: r) to: aPosition startX: 0
!
xOf: aPosition
	^self xOf: aPosition inRow: (self rowOf: aPosition)
!
positionInRow: r atX: x
	"The gap position in row r nearest to x (relative to the text left)."
	| rs re pen tab f text |
	rs := self rowStart: r.
	re := self rowEnd: r.
	tab := Character tab.
	f := self font.
	text := buffer string.
	pen := 0.
	rs + 1 to: re do: [:i |
		| c next |
		c := text at: i.
		next := c == tab ifTrue: [self nextTabStop: pen] ifFalse: [pen + (f advanceOf: c)].
		x < (pen + next / 2) ifTrue: [^i - 1].
		pen := next].
	^re
!
rowAtY: y
	"The row at a view y (clamped)."
	| r |
	r := ((y - self padY + offset) / self lineHeight) floor + 1.
	^(r max: 1) min: self rowCount
!
positionAt: aPoint
	"The gap position nearest to a point in view coordinates."
	| r |
	aPoint y < (self padY - offset) ifTrue: [^0].
	r := self rowAtY: aPoint y.
	^self positionInRow: r atX: aPoint x - self textLeft
!
caretRectAt: aPosition
	"The rectangle (view coordinates) of a caret at aPosition."
	| r x |
	r := self rowOf: aPosition.
	x := self textLeft + (self xOf: aPosition inRow: r).
	^(x - 0.5) @ ((self rowTop: r) - offset) extent: (self theme metric: #caretWidth) @ self lineHeight
!
rectsFrom: start to: stop
	"The rectangles (view coordinates) covering the characters start + 1 .. stop, one per row."
	| rects first last |
	rects := OrderedCollection new.
	stop < start ifTrue: [^rects].
	first := self rowOf: start.
	last := self rowOf: stop.
	first to: last do: [:r | (self rectOfRow: r from: start to: stop) ifNotNil: [:rect | rects add: rect]].
	^rects
!
rectOfRow: r from: start to: stop
	"The part of row r covering the characters start + 1 .. stop (a line feed counts as a space), or nil."
	| rs re a b x0 x1 nl y |
	rs := self rowStart: r.
	re := self rowEnd: r.
	nl := re < buffer size and: [(buffer at: re + 1) == Character lf].
	(start < (re + (nl ifTrue: [1] ifFalse: [0])) and: [stop > rs]) ifFalse: [
		(start = stop and: [start = rs]) ifFalse: [^nil]].
	a := start max: rs.
	b := stop min: re.
	x0 := self xOf: a inRow: r.
	x1 := b <= a ifTrue: [x0] ifFalse: [self xFrom: a to: b startX: x0].
	(nl and: [stop > re]) ifTrue: [x1 := x1 + (self font advanceOf: $ )].
	x1 <= x0 ifTrue: [^nil].
	y := (self rowTop: r) - offset.
	^(self textLeft + x0) @ y corner: (self textLeft + x1) @ (y + self lineHeight)
! !

!TextLayout methodsFor: 'rows'!
ensureRows
	| w |
	w := wrap ifTrue: [self availableTextWidth max: 20] ifFalse: [nil].
	(rowStarts notNil and: [layoutWidth = w]) ifTrue: [^self].
	self computeRowsForWidth: w.
	(w notNil and: [self contentHeight > view height]) ifTrue: [
		self computeRowsForWidth: (w - (self theme metric: #scrollBarWidth) max: 20)].
	layoutWidth := w
!
computeRowsForWidth: w
	| starts ends lineStarts lineTabs ls fast tabW |
	lineStarts := buffer lineStarts.
	lineTabs := buffer lineTabs.
	starts := OrderedCollection new: lineStarts size.
	ends := OrderedCollection new: lineStarts size.
	fast := (self font advanceOf: $W) max: (self font advanceOf: $m).
	tabW := self tabStopWidth.
	1 to: lineStarts size do: [:k |
		| le |
		ls := lineStarts at: k.
		le := buffer lineEndAt: k.
		(w isNil or: [((le - ls - (lineTabs at: k)) * fast) + ((lineTabs at: k) * tabW) <= w])
			ifTrue: [starts add: ls. ends add: le]
			ifFalse: [self wrapFrom: ls to: le width: w starts: starts ends: ends]].
	rowStarts := starts asArray.
	rowEnds := ends asArray
!
wrapFrom: ls to: le width: w starts: starts ends: ends
	| rs x i lastBreak c adv f tab brk text |
	f := self font.
	tab := Character tab.
	text := buffer string.
	rs := ls.
	x := 0.
	lastBreak := nil.
	i := ls.
	[i < le] whileTrue: [
		c := text at: i + 1.
		adv := c == tab ifTrue: [(self nextTabStop: x) - x] ifFalse: [f advanceOf: c].
		(x + adv > w and: [i > rs])
			ifTrue: [
				brk := (lastBreak notNil and: [lastBreak > rs]) ifTrue: [lastBreak] ifFalse: [i].
				starts add: rs.
				ends add: brk.
				rs := brk.
				x := 0.
				lastBreak := nil.
				i := brk]
			ifFalse: [
				x := x + adv.
				i := i + 1.
				(c == $  or: [c == tab]) ifTrue: [lastBreak := i]]].
	starts add: rs.
	ends add: le
!
rowCount
	self ensureRows.
	^rowStarts size
!
rowOf: aPosition
	self ensureRows.
	^TextBuffer indexIn: rowStarts atOrBefore: aPosition
!
rowStart: r
	self ensureRows.
	^rowStarts at: r
!
rowEnd: r
	self ensureRows.
	^rowEnds at: r
!
rowStarts
	"The gap positions where the rows start (valid after ensureRows)."
	^rowStarts
!
rowEnds
	^rowEnds
!
rowTop: r
	"Content y of row r."
	^self padY + ((r - 1) * self lineHeight)
!
contentHeight
	^(rowStarts isNil ifTrue: [buffer lineCount] ifFalse: [rowStarts size]) * self lineHeight + (2 * self padY)
! !

!TextLayout methodsFor: 'scrolling'!
scrollTotal
	self ensureRows.
	^self contentHeight max: self maxScrollOffset + view height
!
maxScrollOffset
	"The largest offset: the last line at the bottom, rounded up so a line starts at the top edge (a little room below the last line rather than a cut line at the top)."
	^self wholeLines: self contentHeight - view height
!
clampedOffset: points
	self ensureRows.
	^(points min: self maxScrollOffset) max: 0
!
clampOffset
	"Keep the offset within the content (after a resize or an edit)."
	offset := (offset min: self contentHeight - view height) max: 0
!
wholeLines: points
	"points rounded up to a scroll offset where a line starts at the top edge (0, or the top of a line after the first), so a scrolled editor shows no cut line there."
	points <= 0 ifTrue: [^0].
	^(((points - self padY) / self lineHeight) ceiling max: 0) * self lineHeight + self padY
!
visibleRowCount
	^(view height - (2 * self padY) / self lineHeight) floor max: 1
! !

!TextLayout class methodsFor: 'instance creation'!
on: aTextBuffer in: aView
	^self new buffer: aTextBuffer view: aView; yourself
! !
