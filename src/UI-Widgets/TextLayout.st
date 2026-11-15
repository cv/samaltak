Object subclass: #TextLayout
	instanceVariableNames: 'buffer view fontSpec font lineHeight monoAdvance wrap rowStarts rowEnds layoutWidth rowWidth offset gutter'
	classVariableNames: ''
	package: 'UI-Widgets'!

TextLayout comment: 'I lay out a TextBuffer in a view (an object answering width and height, the TextEditor): rows (lines soft-wrapped to the view''s width less the padding and the gutter, and less the scroll bar when the text is taller than the view), each a line high in my font; x of a gap position in its row and the position nearest to an x (tabs to the Theme''s tab stops); the vertical scroll offset; and the rectangles of the caret and of character ranges in view coordinates. Rows are computed lazily, dropped when the width changes; a buffer change lays out again only the lines it touched.

x is the sum of the font''s advances, as Canvas>>drawString: draws (combining marks and joiners advance 0, CJK and emoji from the fallback faces more than a cell). A line of printable ASCII in a monospaced font takes the shortcut count × monoAdvance. Positions at an x and wrap breaks are grapheme cluster boundaries. A row breaks after white space, else next to a wide character (CJK, which has no spaces; not before closing punctuation nor after opening), else before the cluster that does not fit.

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
	(font notNil and: [font scale ~= Font deviceScale and: [fontSpec isNil or: [fontSpec isSymbol]]]) ifTrue: [self font: fontSpec].
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
	"Lay out the lines the edit touched again; the rows after them move."
	| delta k0 k1 first last starts ends |
	rowStarts isNil ifTrue: [^self].
	delta := aString size - (stop - start).
	k0 := buffer lineIndexOf: start.
	k1 := buffer lineIndexOf: start + aString size.
	first := TextBuffer indexIn: rowStarts atOrBefore: (buffer lineStarts at: k0).
	last := TextBuffer indexIn: rowStarts atOrBefore: (buffer lineEndAt: k1) - delta.
	starts := OrderedCollection new.
	ends := OrderedCollection new.
	self rowsOfLines: k0 to: k1 width: rowWidth starts: starts ends: ends.
	rowStarts := (rowStarts copyFrom: 1 to: first - 1) , starts asArray , ((rowStarts copyFrom: last + 1 to: rowStarts size) collect: [:each | each + delta]).
	rowEnds := (rowEnds copyFrom: 1 to: first - 1) , ends asArray , ((rowEnds copyFrom: last + 1 to: rowEnds size) collect: [:each | each + delta]).
	"The scroll bar came or went: all rows change width. Rows narrowed for it say only that the text is taller than the view at their width; at the full width it may not be, unless its lines alone are."
	(rowWidth notNil and: [rowWidth < layoutWidth
			ifTrue: [buffer lineCount * self lineHeight + (2 * self padY) <= view height]
			ifFalse: [self contentHeight > view height]]) ifTrue: [rowStarts := nil]
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
	"The advance of every printable ASCII character if my font has one for all, else false."
	| f a |
	monoAdvance isNil ifFalse: [^monoAdvance].
	f := self font.
	a := f advanceOf: $m.
	^monoAdvance := ((32 to: 126) allSatisfy: [:cp | (f advanceOf: (Character value: cp)) = a]) ifTrue: [a] ifFalse: [false]
!
isMonoLine: lineIndex
	"Whether every character of the line advances monoAdvance (printable ASCII, no tabs, monospaced font)."
	^self monoAdvance ~~ false and: [buffer isPlainLine: lineIndex]
!
xFrom: start to: stop startX: x
	"x (relative to the text left) after the characters start + 1 .. stop (within one line), starting at x."
	stop <= start ifTrue: [^x].
	(self isMonoLine: (buffer lineIndexOf: start)) ifTrue: [^x + ((stop - start) * monoAdvance)].
	^self advanceFrom: start to: stop startX: x
!
advanceFrom: start to: stop startX: x
	"xFrom:to:startX: character by character."
	| tab f result text |
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
	"The cluster boundary in row r nearest to x (relative to the text left)."
	| rs re pen text i j next |
	rs := self rowStart: r.
	re := self rowEnd: r.
	(self isMonoLine: (buffer lineIndexOf: rs)) ifTrue: [^rs + ((x / monoAdvance + 0.5) floor max: 0) min: re].
	text := buffer string.
	pen := 0.
	i := rs.
	[i < re] whileTrue: [
		j := (text graphemeClusterEndAfter: i) min: re.
		next := self advanceFrom: i to: j startX: pen.
		x < (pen + next / 2) ifTrue: [^i].
		pen := next.
		i := j].
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
	| starts ends n |
	n := buffer lineCount.
	starts := OrderedCollection new: n.
	ends := OrderedCollection new: n.
	self rowsOfLines: 1 to: n width: w starts: starts ends: ends.
	rowStarts := starts asArray.
	rowEnds := ends asArray.
	rowWidth := w
!
rowsOfLines: firstLine to: lastLine width: w starts: starts ends: ends
	"Add the rows of the lines firstLine to lastLine, wrapped to w (nil: not wrapped)."
	| lineStarts lineTabs lineOthers ls fast tabW |
	lineStarts := buffer lineStarts.
	lineTabs := buffer lineTabs.
	lineOthers := buffer lineOthers.
	fast := (self font advanceOf: $W) max: (self font advanceOf: $m).
	tabW := self tabStopWidth.
	firstLine to: lastLine do: [:k |
		| le |
		ls := lineStarts at: k.
		le := buffer lineEndAt: k.
		(w isNil or: [(lineOthers at: k) = 0
				ifTrue: [((le - ls - (lineTabs at: k)) * fast) + ((lineTabs at: k) * tabW) <= w]
				ifFalse: [(self advanceFrom: ls to: le startX: 0) <= w]])
			ifTrue: [starts add: ls. ends add: le]
			ifFalse: [self wrapFrom: ls to: le width: w starts: starts ends: ends]]
!
wrapFrom: ls to: le width: w starts: starts ends: ends
	| rs x i j lastBreak c adv tab brk text wide prevWide prevOpen |
	tab := Character tab.
	text := buffer string.
	rs := ls.
	x := 0.
	lastBreak := nil.
	prevWide := prevOpen := false.
	i := ls.
	[i < le] whileTrue: [
		c := text at: i + 1.
		j := (text graphemeClusterEndAfter: i) min: le.
		adv := (self advanceFrom: i to: j startX: x) - x.
		wide := c value >= 16r1100 and: [c displayWidth = 2].
		((wide or: [prevWide]) and: [i > rs and: [prevOpen not and: [(self isClosingPunctuation: c) not]]]) ifTrue: [lastBreak := i].
		(x + adv > w and: [i > rs])
			ifTrue: [
				brk := (lastBreak notNil and: [lastBreak > rs]) ifTrue: [lastBreak] ifFalse: [i].
				starts add: rs.
				ends add: brk.
				rs := brk.
				x := 0.
				lastBreak := nil.
				prevWide := prevOpen := false.
				i := brk]
			ifFalse: [
				x := x + adv.
				i := j.
				prevWide := wide.
				prevOpen := c value < 128 ifTrue: ['([{' includes: c] ifFalse: [self isOpeningPunctuation: c].
				(c == $  or: [c == tab]) ifTrue: [lastBreak := i]]].
	starts add: rs.
	ends add: le
!
isClosingPunctuation: aCharacter
	"No row starts with it (、。」 , . ))."
	^aCharacter value > 32 and: [#(#Pe #Pf #Po) includes: aCharacter generalCategory]
!
isOpeningPunctuation: aCharacter
	"No row ends with it (「（)."
	^#(#Ps #Pi) includes: aCharacter generalCategory
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
