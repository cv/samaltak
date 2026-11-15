Widget subclass: #TerminalView
	instanceVariableNames: 'screen parser font boldFont italicFont cellWidth cellHeight scrollOffset anchor point selection selectionSerials selecting rowDrawings colors scaledFonts cursorOn blinkTimer swallowText onSend onResize onTitle drawnTitleSerial lastScrolledTotal exitStatus'
	classVariableNames: 'BoxArms Palette'
	package: 'Tools'!

TerminalView comment: 'I am the screen of a Terminal: I draw a TerminalScreen (JetBrains Mono on white, the 16 ANSI colors tuned to the Blue Book theme, 256 colors and truecolor), its scrollback (wheel; shift-page up/down), a blinking block cursor (the caret blink of the Theme) and a mouse selection (drag, double-click a word, triple-click a line; ⌘C copies, ⌘V pastes — bracketed when the program asked for it). A wide character is drawn centered across its two cells (smaller if its glyph is wider), and selected and copied whole; zero-width characters are drawn over the character they follow and copied with it. Keys become what an xterm sends: arrows (application cursor mode too), home/end, page up/down, delete, backspace (DEL), tab, return (CR), escape, control letters, ⌥ as meta (an ESC prefix; ⌥←/⌥→ move by words); typed text is sent as UTF-8.

My size decides the screen''s rows and columns (onResize: tells the pty). onSend: [:bytes | …] receives what the user types; feed:from:to: interprets what the program wrote (TerminalParser); afterOutput updates the view and the title (onTitle:).

Drawing is retained per row: a row is drawn again only when its line changed, the selection on it changed or it moved (then it is replayed moved). Remote control: role #terminal, name terminal, state rows= cols= cursor=row,col title="…" alt-screen, the shown rows as text (wait for text sees them).'!

!TerminalView methodsFor: 'initialization'!
initialize
	super initialize.
	name := 'terminal'.
	self resetFonts.
	cellHeight := 17.
	screen := TerminalScreen rows: 24 cols: 80.
	parser := TerminalParser on: screen.
	scrollOffset := 0.
	selecting := false.
	rowDrawings := IdentityDictionary new.
	colors := Dictionary new.
	cursorOn := true.
	swallowText := false.
	drawnTitleSerial := 0.
	lastScrolledTotal := 0
! !

!TerminalView methodsFor: 'accessing'!
screen
	^screen
!
parser
	^parser
!
cellExtent
	^cellWidth @ cellHeight
!
padding
	^6 @ 4
!
scrollOffset
	"How many lines the view is scrolled back into the scrollback (0: the screen)."
	^scrollOffset
!
onSend: aBlock
	"aBlock value: aByteArray — what the user typed, for the program."
	onSend := aBlock
!
onResize: aBlock
	"aBlock value: rows value: columns after the screen changed its size."
	onResize := aBlock
!
onTitle: aBlock
	"aBlock value: aString when the program set the title (OSC 0 or 2)."
	onTitle := aBlock
!
exitStatus: anInteger
	"The program ended (shown in my remote state)."
	exitStatus := anInteger
!
gridExtentFor: anExtent
	"The rows @ columns that fit anExtent."
	| p |
	p := self padding.
	^((anExtent y - (2 * p y)) // cellHeight max: 2) @ ((anExtent x - (2 * p x)) // cellWidth max: 10)
!
preferredExtentForRows: r cols: c
	^(c * cellWidth + (2 * self padding x)) ceiling @ (r * cellHeight + (2 * self padding y))
! !

!TerminalView methodsFor: 'output'!
feed: bytes from: start to: stop
	"Interpret what the program wrote (call afterOutput when done with a batch)."
	parser feed: bytes from: start to: stop
!
afterOutput
	"After a batch of output: keep a scrolled-back view on its lines, answer the program's queries, pass on the title, redraw."
	| replies added |
	added := screen scrolledTotal - lastScrolledTotal.
	lastScrolledTotal := screen scrolledTotal.
	scrollOffset > 0 ifTrue: [scrollOffset := scrollOffset + added min: screen scrollback size].
	(selection notNil and: [selecting not and: [self selectionChanged]]) ifTrue: [selection := nil].
	replies := screen takeReplies.
	replies isEmpty ifFalse: [self send: replies].
	screen titleSerial = drawnTitleSerial ifFalse: [
		drawnTitleSerial := screen titleSerial.
		onTitle isNil ifFalse: [onTitle value: screen title]].
	cursorOn := true.
	self invalidate
!
send: aStringOrBytes
	| bytes |
	onSend isNil ifTrue: [^self].
	bytes := aStringOrBytes isString ifTrue: [aStringOrBytes utf8Encoded] ifFalse: [aStringOrBytes].
	bytes isEmpty ifFalse: [onSend value: bytes]
! !

!TerminalView methodsFor: 'drawing'!
resetFonts
	"Take the theme's fonts (again, after the display scale changed)."
	font := self theme font: #code.
	boldFont := self theme font: #codeBold.
	italicFont := self theme font: #codeItalic.
	cellWidth := font advanceOf: $M.
	scaledFonts := Dictionary new.
	rowDrawings := IdentityDictionary new
! !

!TerminalView methodsFor: 'layout'!
layout
	| grid |
	grid := self gridExtentFor: self extent.
	(grid x = screen rows and: [grid y = screen cols]) ifTrue: [^self].
	screen rows: grid x cols: grid y.
	lastScrolledTotal := screen scrolledTotal.
	scrollOffset := scrollOffset min: screen scrollback size.
	self clearSelection.
	onResize isNil ifFalse: [onResize value: grid x value: grid y].
	self invalidate
! !

!TerminalView methodsFor: 'drawing'!
invalidate
	"Rows replay what did not change (drawSelfOn:), so draw only me again."
	self ownDrawingChanged.
	self requestRedraw
!
topLineIndex
	"The absolute index (TerminalScreen>>lineAtIndex:) of the line in my first row."
	^screen scrolledTotal + 1 - scrollOffset
!
drawSelfOn: aCanvas
	| p first drawn width |
	font scale = Font deviceScale ifFalse: [self resetFonts].
	aCanvas fillRect: self localBounds color: self theme paper.
	p := self padding.
	first := self topLineIndex.
	width := screen cols * cellWidth.
	drawn := IdentityDictionary new.
	1 to: screen rows do: [:r | | index line sel cached |
		index := first + r - 1.
		line := screen lineAtIndex: index.
		line isNil ifFalse: [
			sel := self selectionColumnsOn: index.
			cached := rowDrawings at: line ifAbsent: [nil].
			aCanvas translateBy: p x @ (p y + (r - 1 * cellHeight)) during: [
				aCanvas clip: (0 @ 0 extent: width @ cellHeight) during: [
					(cached notNil and: [(cached at: 1) = line serial and: [(cached at: 2) = sel and: [aCanvas replay: (cached at: 3)]]])
						ifFalse: [cached := Array with: line serial with: sel with: (aCanvas record: [self drawLine: line selection: sel on: aCanvas])]]].
			drawn at: line put: cached]].
	rowDrawings := drawn
!
drawLine: aLine selection: sel on: aCanvas
	"One row at 0@0: runs of equal attributes, then the selection."
	| chars attrs n c j a |
	chars := aLine chars.
	attrs := aLine attrs.
	n := chars size min: screen cols.
	c := 1.
	[c <= n] whileTrue: [
		a := attrs at: c.
		j := c.
		[j < n and: [(attrs at: j + 1) = a]] whileTrue: [j := j + 1].
		self drawRun: aLine from: c to: j attribute: a on: aCanvas.
		c := j + 1].
	sel isNil ifFalse: [
		aCanvas
			fillRect: ((sel first - 1 * cellWidth) @ 0 corner: ((sel last min: screen cols) * cellWidth) @ cellHeight)
			color: (self theme color: #textSelection)]
!
drawRun: aLine from: start to: stop attribute: a on: aCanvas
	| chars fg bg x0 x1 runFont last y wide |
	chars := aLine chars.
	fg := TerminalScreen foregroundOf: a.
	bg := TerminalScreen backgroundOf: a.
	(TerminalScreen isInverse: a)
		ifTrue: [
			| t |
			t := (self colorFor: fg default: self theme ink).
			fg := self colorFor: bg default: self theme paper.
			bg := t]
		ifFalse: [
			fg := self colorFor: fg default: self theme ink.
			bg := bg = 0 ifTrue: [nil] ifFalse: [self colorFor: bg default: self theme paper]].
	x0 := start - 1 * cellWidth.
	x1 := stop * cellWidth.
	bg isNil ifFalse: [aCanvas fillRect: (x0 @ 0 corner: x1 @ cellHeight) color: bg].
	(TerminalScreen isHidden: a) ifTrue: [^self].
	(TerminalScreen isDim: a) ifTrue: [fg := fg mixed: 0.45 with: (bg ifNil: [self theme paper])].
	(TerminalScreen isUnderline: a) ifTrue: [aCanvas fillRect: (x0 @ (cellHeight - 2.5) corner: x1 @ (cellHeight - 1.5)) color: fg].
	(TerminalScreen isStrike: a) ifTrue: [aCanvas fillRect: (x0 @ (cellHeight / 2) corner: x1 @ (cellHeight / 2 + 1)) color: fg].
	runFont := (TerminalScreen isBold: a) ifTrue: [boldFont] ifFalse: [(TerminalScreen isItalic: a) ifTrue: [italicFont] ifFalse: [font]].
	aLine marks isNil ifFalse: [
		start to: stop do: [:i | (aLine marksAt: i) ifNotNil: [:m | self drawMarks: m over: i of: aLine font: runFont color: fg on: aCanvas]]].
	last := stop.
	[last >= start and: [(chars at: last) == $ ]] whileTrue: [last := last - 1].
	last < start ifTrue: [^self].
	y := cellHeight - runFont lineHeight / 2.
	wide := false.
	start to: last do: [:i | | v | v := (chars at: i) value. (v > 255 or: [v = 0]) ifTrue: [wide := true]].
	wide ifFalse: [^aCanvas drawString: chars from: start to: last at: x0 @ y font: runFont color: fg].
	start to: last do: [:i | | ch |
		ch := chars at: i.
		(ch == $  or: [ch value = 0]) ifFalse: [
			ch value > 255
				ifTrue: [self drawWide: ch at: i - 1 * cellWidth cells: ((aLine isWideAt: i) ifTrue: [2] ifFalse: [1]) font: runFont color: fg on: aCanvas]
				ifFalse: [aCanvas drawString: chars from: i to: i at: (i - 1 * cellWidth) @ y font: runFont color: fg]]]
!
drawWide: aCharacter at: x cells: w font: aFont color: aColor on: aCanvas
	"A character beyond Latin-1 in its w cells: box drawing and blocks drawn as rectangles, else its glyph (from aFont's fallback faces if need be) centered in them, a wide one smaller if it is wider than its cells."
	| cp f advance space |
	cp := aCharacter value.
	(cp between: 16r2500 and: 16r259F) ifTrue: [
		(self drawBox: cp at: x color: aColor on: aCanvas) ifTrue: [^self]].
	f := aFont.
	advance := f advanceOf: aCharacter.
	space := w * cellWidth.
	(w = 2 and: [advance > space]) ifTrue: [
		f := self font: aFont scaledTo: space / advance.
		advance := f advanceOf: aCharacter].
	aCanvas drawString: (String with: aCharacter)
		at: (x + (space - advance / 2)) @ (cellHeight - f lineHeight / 2) font: f color: aColor
!
drawMarks: aString over: col of: aLine font: aFont color: aColor on: aCanvas
	"Zero-width characters over the character in col: from where its glyph ends (so marks without advance, drawn left of the pen, sit over it); a mark with an advance centered in the cells."
	| w x pen |
	w := (aLine isWideAt: col) ifTrue: [2] ifFalse: [1].
	x := col - 1 * cellWidth.
	pen := x + (w * cellWidth + (aFont advanceOf: (aLine characterAt: col)) / 2).
	aString do: [:mark | | advance |
		(Font isInvisible: mark value) ifFalse: [
			advance := aFont advanceOf: mark.
			aCanvas drawString: (String with: mark)
				at: (advance = 0 ifTrue: [pen] ifFalse: [x + (w * cellWidth - advance / 2)]) @ (cellHeight - aFont lineHeight / 2) font: aFont color: aColor]]
!
font: aFont scaledTo: aFraction
	"aFont at aFraction of its size (in steps of 5 %), kept."
	| percent |
	percent := (aFraction * 20) floor * 5 max: 5.
	^scaledFonts at: aFont -> percent ifAbsentPut: [Font face: aFont face size: aFont size * percent / 100 scale: aFont scale]
!
drawBox: cp at: x color: aColor on: aCanvas
	"Box drawing (U+2500-257F: light, heavy and double arms) and block elements (U+2580-259F); answer false for the ones I do not draw."
	| arms cx cy |
	cp >= 16r2580 ifTrue: [^self drawBlock: cp at: x color: aColor on: aCanvas].
	arms := self class boxArms at: cp ifAbsent: [^false].
	cx := x + (cellWidth / 2).
	cy := cellHeight / 2.
	1 to: 4 do: [:dir | | weight t r |
		weight := arms at: dir.
		weight > 0 ifTrue: [
			t := weight = 2 ifTrue: [1] ifFalse: [0.5].
			r := dir = 1 ifTrue: [x @ (cy - t) corner: (cx + t) @ (cy + t)] ifFalse: [
				dir = 2 ifTrue: [(cx - t) @ (cy - t) corner: (x + cellWidth) @ (cy + t)] ifFalse: [
					dir = 3 ifTrue: [(cx - t) @ 0 corner: (cx + t) @ (cy + t)] ifFalse: [
						(cx - t) @ (cy - t) corner: (cx + t) @ cellHeight]]].
			weight = 3
				ifTrue: [ | d |
					d := dir <= 2 ifTrue: [0 @ 1.5] ifFalse: [1.5 @ 0].
					aCanvas fillRect: (r translateBy: d negated) color: aColor.
					aCanvas fillRect: (r translateBy: d) color: aColor]
				ifFalse: [aCanvas fillRect: r color: aColor]]].
	^true
!
drawBlock: cp at: x color: aColor on: aCanvas
	| w h n |
	w := cellWidth.
	h := cellHeight.
	cp = 16r2580 ifTrue: [aCanvas fillRect: (x @ 0 extent: w @ (h / 2)) color: aColor. ^true].
	(cp between: 16r2581 and: 16r2588) ifTrue: [
		n := cp - 16r2580.
		aCanvas fillRect: (x @ (h - (h * n / 8)) corner: (x + w) @ h) color: aColor.
		^true].
	(cp between: 16r2589 and: 16r258F) ifTrue: [
		n := 16r2590 - cp.
		aCanvas fillRect: (x @ 0 extent: (w * n / 8) @ h) color: aColor.
		^true].
	cp = 16r2590 ifTrue: [aCanvas fillRect: ((x + (w / 2)) @ 0 corner: (x + w) @ h) color: aColor. ^true].
	(cp between: 16r2591 and: 16r2593) ifTrue: [
		aCanvas fillRect: (x @ 0 extent: w @ h) color: (aColor alpha: cp - 16r2590 * 0.25).
		^true].
	cp = 16r2594 ifTrue: [aCanvas fillRect: (x @ 0 extent: w @ (h / 8)) color: aColor. ^true].
	cp = 16r2595 ifTrue: [aCanvas fillRect: ((x + w - (w / 8)) @ 0 corner: (x + w) @ h) color: aColor. ^true].
	^false
!
drawOverlayOn: aCanvas
	"The cursor: a block while I have the keys (blinking), a frame otherwise."
	| p r c w rect line ch cursorFont |
	(scrollOffset = 0 and: [screen isCursorVisible]) ifFalse: [^self].
	p := self padding.
	r := screen row.
	c := screen col.
	line := screen lineAt: r.
	w := (line isWideAt: c) ifTrue: [2] ifFalse: [1].
	rect := (p x + (c - 1 * cellWidth)) @ (p y + (r - 1 * cellHeight)) extent: (w * cellWidth) @ cellHeight.
	self isFocused ifFalse: [^aCanvas strokeRect: rect color: self theme ink width: 1].
	cursorOn ifFalse: [^self].
	aCanvas fillRect: rect color: self theme ink.
	ch := line characterAt: c.
	cursorFont := (TerminalScreen isBold: (line attributeAt: c)) ifTrue: [boldFont] ifFalse: [font].
	aCanvas translateBy: p x @ rect top during: [
		(ch == $  or: [ch value = 0]) ifFalse: [
			ch value > 255
				ifTrue: [self drawWide: ch at: c - 1 * cellWidth cells: w font: cursorFont color: self theme paper on: aCanvas]
				ifFalse: [aCanvas drawString: (String with: ch) at: (c - 1 * cellWidth) @ (cellHeight - font lineHeight / 2) font: cursorFont color: self theme paper]].
		(line marksAt: c) ifNotNil: [:m | self drawMarks: m over: c of: line font: cursorFont color: self theme paper on: aCanvas]]
!
colorFor: code default: aColor
	"The Color of an attribute's color code (0: aColor)."
	code = 0 ifTrue: [^aColor].
	^colors at: code ifAbsent: [colors at: code put: (self class colorOf: code)]
! !

!TerminalView methodsFor: 'cursor blinking'!
restartBlink
	blinkTimer isNil ifFalse: [blinkTimer cancel. blinkTimer := nil].
	cursorOn := true.
	self hasKeyboardFocus ifFalse: [^self].
	blinkTimer := self after: (self theme metric: #caretBlinkMs) do: [self blink]
!
blink
	blinkTimer := nil.
	self hasKeyboardFocus ifFalse: [^self].
	self isFocused
		ifTrue: [cursorOn := cursorOn not. self invalidateOverlay]
		ifFalse: [cursorOn := true].
	blinkTimer := self after: (self theme metric: #caretBlinkMs) do: [self blink]
!
focusGained
	self restartBlink.
	self invalidate
!
focusLost
	blinkTimer isNil ifFalse: [blinkTimer cancel. blinkTimer := nil].
	cursorOn := true.
	selecting := false.
	self invalidate
! !

!TerminalView methodsFor: 'scrolling'!
scrollBy: lines
	"Positive: back into the scrollback."
	| offset |
	offset := (scrollOffset + lines max: 0) min: screen scrollback size.
	offset = scrollOffset ifTrue: [^self].
	scrollOffset := offset.
	self invalidate
!
scrollToBottom
	self scrollBy: scrollOffset negated
! !

!TerminalView methodsFor: 'selection'!
cellAt: aPoint
	"{absolute line index. column} of the cell under aPoint (local)."
	| p r c |
	p := self padding.
	r := ((aPoint y - p y) // cellHeight + 1 max: 1) min: screen rows.
	c := ((aPoint x - p x) // cellWidth + 1 max: 1) min: screen cols.
	^Array with: self topLineIndex + r - 1 with: c
!
selection
	"nil, or {start. end}: {line index. column} cells, inclusive, in reading order."
	^selection
!
clearSelection
	selection isNil ifTrue: [^self].
	selection := nil.
	self invalidate
!
select: startCell to: endCell
	| a b |
	a := startCell.
	b := endCell.
	((a at: 1) > (b at: 1) or: [(a at: 1) = (b at: 1) and: [(a at: 2) > (b at: 2)]]) ifTrue: [a := endCell. b := startCell].
	selection := Array with: a with: b.
	selectionSerials := ((a at: 1) to: ((b at: 1) min: (a at: 1) + 500)) collect: [:i | (screen lineAtIndex: i) ifNotNil: [:line | line serial]].
	self invalidate
!
selectionChanged
	"Whether the program changed (or the scrollback dropped) a selected line."
	| first |
	first := selection first at: 1.
	selectionSerials doWithIndex: [:serial :k |
		((screen lineAtIndex: first + k - 1) ifNotNil: [:line | line serial]) = serial ifFalse: [^true]].
	^false
!
selectionColumnsOn: index
	"The selected columns {first. last} of the line with absolute index, or nil."
	| a b first last line |
	selection isNil ifTrue: [^nil].
	a := selection first.
	b := selection last.
	(index between: (a at: 1) and: (b at: 1)) ifFalse: [^nil].
	first := index = (a at: 1) ifTrue: [a at: 2] ifFalse: [1].
	last := index = (b at: 1) ifTrue: [b at: 2] ifFalse: [screen cols].
	"A wide character is selected whole."
	line := screen lineAtIndex: index.
	line isNil ifFalse: [
		(line isContinuationAt: first) ifTrue: [first := first - 1].
		(line isWideAt: last) ifTrue: [last := last + 1]].
	^Array with: first with: last
!
selectedText
	"The selected text; rows joined with line feeds unless the line wrapped into the next."
	selection isNil ifTrue: [^''].
	^String new: 80 streamContents: [:s |
		(selection first at: 1) to: (selection last at: 1) do: [:index | | line cols |
			line := screen lineAtIndex: index.
			line isNil ifFalse: [
				cols := self selectionColumnsOn: index.
				s nextPutAll: (line stringFrom: cols first to: cols last).
				(index < (selection last at: 1) and: [line isWrapped not or: [cols last < screen cols]])
					ifTrue: [s nextPut: Character lf]]]]
!
wordAt: aCell
	"{start cell. end cell} of the run of non-blank characters (or of blanks) at aCell."
	| line c a b blank |
	line := screen lineAtIndex: (aCell at: 1).
	line isNil ifTrue: [^Array with: aCell with: aCell].
	c := aCell at: 2.
	blank := (line characterAt: c) isWhiteSpace.
	a := c.
	[a > 1 and: [(line characterAt: a - 1) isWhiteSpace = blank]] whileTrue: [a := a - 1].
	b := c.
	[b < screen cols and: [(line characterAt: b + 1) isWhiteSpace = blank]] whileTrue: [b := b + 1].
	^Array with: (Array with: (aCell at: 1) with: a) with: (Array with: (aCell at: 1) with: b)
!
copySelection
	selection isNil ifTrue: [^self].
	self clipboardText: self selectedText
!
paste
	self pasteText: self clipboardText
!
pasteText: aString
	"Send aString as typed, line ends as returns; bracketed (ESC [200~ … ESC [201~) when the program asked for it."
	| text |
	text := aString.
	text isEmpty ifTrue: [^self].
	text := text copyReplaceAll: (String with: Character cr with: Character lf) with: (String with: Character cr).
	text := text collect: [:c | c = Character lf ifTrue: [Character cr] ifFalse: [c]].
	self scrollToBottom.
	screen bracketedPaste
		ifTrue: [self send: (String with: Character escape), '[200~', text, (String with: Character escape), '[201~']
		ifFalse: [self send: text]
! !

!TerminalView methodsFor: 'events'!
wantsKeyboardFocus
	^true
!
cursorAt: aPoint
	^#ibeam
!
mouseDown: anEvent
	| cell |
	anEvent button = 1 ifFalse: [^false].
	cell := self cellAt: anEvent position.
	selecting := true.
	anEvent clickCount >= 3 ifTrue: [
		anchor := #line.
		self select: (Array with: (cell at: 1) with: 1) to: (Array with: (cell at: 1) with: screen cols).
		^true].
	anEvent clickCount = 2 ifTrue: [ | word |
		anchor := #word.
		word := self wordAt: cell.
		self select: word first to: word last.
		^true].
	anEvent modifiers shift & selection notNil
		ifTrue: [anchor := selection first. self select: anchor to: cell]
		ifFalse: [anchor := cell. point := cell. self clearSelection].
	^true
!
mouseMove: anEvent
	| cell |
	selecting ifFalse: [^false].
	(anchor isSymbol or: [anchor isNil]) ifTrue: [^true].
	anEvent position y < 0 ifTrue: [self scrollBy: 1].
	anEvent position y > self height ifTrue: [self scrollBy: -1].
	cell := self cellAt: anEvent position.
	cell = point ifTrue: [^true].
	point := cell.
	cell = anchor
		ifTrue: [self clearSelection]
		ifFalse: [self select: anchor to: cell].
	^true
!
mouseUp: anEvent
	selecting := false.
	^true
!
wheel: anEvent
	| lines |
	lines := anEvent delta y * 3.
	lines := lines > 0 ifTrue: [lines ceiling] ifFalse: [lines floor].
	lines = 0 ifTrue: [^true].
	(screen isAlternateScreen and: [scrollOffset = 0])
		ifTrue: [
			"A full-screen program has no scrollback here: move through it with the cursor keys, as xterm's alternate scroll mode does."
			lines abs timesRepeat: [self send: (self cursorKey: (lines > 0 ifTrue: [$A] ifFalse: [$B]) modifiers: 1)]]
		ifFalse: [self scrollBy: lines].
	^true
!
textInput: anEvent
	| s |
	swallowText ifTrue: [swallowText := false. ^true].
	"Line ends in typed text are returns; other controls come as keys."
	s := (anEvent string collect: [:c | c = Character lf ifTrue: [Character cr] ifFalse: [c]])
		select: [:c | (c value >= 32 and: [c value ~= 127]) or: [c = Character cr or: [c = Character tab]]].
	s isEmpty ifTrue: [^true].
	self typed.
	self send: s.
	^true
!
typed
	"The user typed: show the screen and the cursor."
	scrollOffset = 0 ifFalse: [self scrollToBottom].
	self restartBlink.
	self invalidateOverlay
!
keyDown: anEvent
	| key mods bytes |
	key := anEvent key.
	mods := anEvent modifiers.
	swallowText := false.
	anEvent isModifierKey ifTrue: [^true].
	mods commandKey ifTrue: [^self commandKey: key shift: mods shift].
	(mods shift and: [key == #pageUp or: [key == #pageDown]]) ifTrue: [
		self scrollBy: (key == #pageUp ifTrue: [screen rows - 1] ifFalse: [1 - screen rows]).
		^true].
	bytes := self bytesForKey: key modifiers: mods.
	bytes isNil ifTrue: [^key isCharacter or: [key == #space]].
	"A key that produced bytes (control or meta combinations) must not also type its text."
	key isCharacter | (key == #space) ifTrue: [swallowText := true].
	self typed.
	self send: bytes.
	^true
!
commandKey: key shift: shift
	key = $c ifTrue: [self copySelection. ^true].
	key = $v ifTrue: [self paste. ^true].
	key = $k ifTrue: [screen clearScrollback. scrollOffset := 0. self clearSelection; invalidate. ^true].
	key = $a ifTrue: [
		self select: (Array with: screen firstLineIndex with: 1) to: (Array with: screen scrolledTotal + screen rows with: screen cols).
		^true].
	^false
!
bytesForKey: key modifiers: mods
	"What an xterm sends for key, or nil (printable keys arrive as text)."
	| esc meta ctrl code |
	esc := String with: Character escape.
	meta := mods option.
	ctrl := mods control.
	key isCharacter ifTrue: [
		ctrl ifTrue: [
			code := self controlCodeFor: key.
			code isNil ifTrue: [^nil].
			^(meta ifTrue: [esc] ifFalse: ['']), (String with: (Character value: code))].
		meta ifTrue: [^esc, (String with: (mods shift ifTrue: [key asUppercase] ifFalse: [key]))].
		^nil].
	key == #space ifTrue: [
		ctrl ifTrue: [^(meta ifTrue: [esc] ifFalse: ['']), (String with: (Character value: 0))].
		meta ifTrue: [^esc, ' '].
		^nil].
	(key == #return or: [key == #enter]) ifTrue: [^(meta ifTrue: [esc] ifFalse: ['']), (String with: Character cr)].
	key == #backspace ifTrue: [^(meta ifTrue: [esc] ifFalse: ['']), (String with: (Character value: (ctrl ifTrue: [8] ifFalse: [127])))].
	key == #tab ifTrue: [^mods shift ifTrue: [esc, '[Z'] ifFalse: [String with: Character tab]].
	key == #escape ifTrue: [^esc].
	(meta and: [ctrl not and: [mods shift not]]) ifTrue: [
		key == #left ifTrue: [^esc, 'b'].
		key == #right ifTrue: [^esc, 'f']].
	key == #up ifTrue: [^self cursorKey: $A modifiers: (self modifierParameter: mods)].
	key == #down ifTrue: [^self cursorKey: $B modifiers: (self modifierParameter: mods)].
	key == #right ifTrue: [^self cursorKey: $C modifiers: (self modifierParameter: mods)].
	key == #left ifTrue: [^self cursorKey: $D modifiers: (self modifierParameter: mods)].
	key == #home ifTrue: [^self cursorKey: $H modifiers: (self modifierParameter: mods)].
	key == #end ifTrue: [^self cursorKey: $F modifiers: (self modifierParameter: mods)].
	key == #insert ifTrue: [^self tildeKey: 2 modifiers: (self modifierParameter: mods)].
	key == #delete ifTrue: [^self tildeKey: 3 modifiers: (self modifierParameter: mods)].
	key == #pageUp ifTrue: [^self tildeKey: 5 modifiers: (self modifierParameter: mods)].
	key == #pageDown ifTrue: [^self tildeKey: 6 modifiers: (self modifierParameter: mods)].
	(key isSymbol and: [(key beginsWith: 'f') and: [key size between: 2 and: 3]]) ifTrue: [
		code := Number readFrom: (key allButFirst: 1) ifFail: [nil].
		code isNil ifTrue: [^nil].
		code <= 4 ifTrue: [^esc, 'O', (String with: ('PQRS' at: code))].
		^self tildeKey: (#(15 17 18 19 20 21 23 24) at: code - 4 ifAbsent: [^nil]) modifiers: (self modifierParameter: mods)].
	^nil
!
controlCodeFor: key
	"The C0 control a ctrl-key combination sends, or nil."
	(key between: $a and: $z) ifTrue: [^key value - 96].
	key = $@ | (key = $2) ifTrue: [^0].
	key = $[ | (key = $3) ifTrue: [^27].
	key = $\ | (key = $4) ifTrue: [^28].
	key = $] | (key = $5) ifTrue: [^29].
	key = $^ | (key = $6) ifTrue: [^30].
	key = $_ | (key = $- | (key = $7)) ifTrue: [^31].
	key = $/ ifTrue: [^31].
	key = $8 | (key = $?) ifTrue: [^127].
	^nil
!
modifierParameter: mods
	"xterm's modifier parameter: 1 + shift 1 + alt 2 + ctrl 4."
	^1 + (mods shift ifTrue: [1] ifFalse: [0]) + (mods option ifTrue: [2] ifFalse: [0]) + (mods control ifTrue: [4] ifFalse: [0])
!
cursorKey: aCharacter modifiers: m
	| esc |
	esc := String with: Character escape.
	m > 1 ifTrue: [^esc, '[1;', m printString, (String with: aCharacter)].
	^esc, (screen appCursorKeys ifTrue: ['O'] ifFalse: ['[']), (String with: aCharacter)
!
tildeKey: n modifiers: m
	^(String with: Character escape), '[', n printString, (m > 1 ifTrue: [';', m printString] ifFalse: ['']), '~'
! !

!TerminalView methodsFor: 'context menu'!
contextMenuAt: aPoint
	| menu |
	menu := Menu title: 'Terminal'.
	menu add: 'Copy' key: '⌘C' action: [self copySelection].
	menu add: 'Paste' key: '⌘V' action: [self paste].
	menu add: 'Select all' key: '⌘A' action: [self commandKey: $a shift: false].
	menu add: 'Clear scrollback' key: '⌘K' action: [self commandKey: $k shift: false].
	^menu
! !

!TerminalView methodsFor: 'remote control'!
remoteRole
	^#terminal
!
remoteLabel
	^screen title isEmpty ifTrue: [nil] ifFalse: [screen title]
!
remoteState
	"Read in my window's Process: output changes the screen there."
	^(self inWindowWait: [self remoteStateNow]) ifNil: [#()]
!
remoteStateNow
	| s |
	s := OrderedCollection new.
	s add: 'rows=', screen rows printString; add: 'cols=', screen cols printString.
	s add: 'cursor=', screen row printString, ',', screen col printString.
	screen title isEmpty ifFalse: [s add: 'title=', (self remoteQuote: screen title)].
	screen isAlternateScreen ifTrue: [s add: 'alt-screen'].
	screen isCursorVisible ifFalse: [s add: 'cursor-hidden'].
	scrollOffset > 0 ifTrue: [s add: 'scrolled=', scrollOffset printString].
	selection isNil ifFalse: [s add: 'sel=', (self remoteQuote: self selectedText)].
	exitStatus isNil ifFalse: [s add: 'exited=', exitStatus printString].
	self isFocused ifTrue: [s add: #focused].
	^s asArray
!
shownLines
	"The text of my rows, as shown (scrollback included when scrolled back); read in my window's Process."
	^(self inWindowWait: [self shownLinesNow]) ifNil: [#()]
!
shownLinesNow
	| first |
	first := self topLineIndex.
	^(1 to: screen rows) collect: [:r | (screen lineAtIndex: first + r - 1) ifNil: [''] ifNotNil: [:line | line string]]
!
remoteText
	| shown |
	shown := self shownLines.
	^String new: 2000 streamContents: [:s | shown do: [:each | s nextPutAll: each] separatedBy: [s nextPut: Character lf]]
!
remoteChildren
	| shown last |
	shown := self shownLines.
	last := shown size.
	[last > 0 and: [(shown at: last) isEmpty]] whileTrue: [last := last - 1].
	^(shown first: last) collect: [:each | '| ', each]
! !

!TerminalView class methodsFor: 'box drawing'!
boxArms
	"Code point -> {left. right. up. down}: 0 none, 1 light, 2 heavy, 3 double (dashed lines are drawn solid, rounded corners square)."
	| spec |
	BoxArms isNil ifFalse: [^BoxArms].
	BoxArms := Dictionary new.
	spec := #(16r2500 1100 16r2501 2200 16r2502 11 16r2503 22 16r2504 1100 16r2505 2200 16r2506 11 16r2507 22
		16r2508 1100 16r2509 2200 16r250A 11 16r250B 22
		16r250C 101 16r250D 201 16r250E 102 16r250F 202
		16r2510 1001 16r2511 2001 16r2512 1002 16r2513 2002
		16r2514 110 16r2515 210 16r2516 120 16r2517 220
		16r2518 1010 16r2519 2010 16r251A 1020 16r251B 2020
		16r251C 111 16r251D 211 16r2520 122 16r2523 222
		16r2524 1011 16r2525 2011 16r2528 1022 16r252B 2022
		16r252C 1101 16r252F 2201 16r2530 1102 16r2533 2202
		16r2534 1110 16r2537 2210 16r2538 1120 16r253B 2220
		16r253C 1111 16r253F 2211 16r2542 1122 16r254B 2222
		16r254C 1100 16r254D 2200 16r254E 11 16r254F 22
		16r2550 3300 16r2551 33 16r2552 301 16r2553 103 16r2554 303 16r2555 3001 16r2556 1003 16r2557 3003
		16r2558 310 16r2559 130 16r255A 330 16r255B 3010 16r255C 1030 16r255D 3030
		16r255E 311 16r255F 133 16r2560 333 16r2561 3011 16r2562 1033 16r2563 3033
		16r2564 3301 16r2565 1103 16r2566 3303 16r2567 3310 16r2568 1130 16r2569 3330
		16r256A 3311 16r256B 1133 16r256C 3333
		16r256D 101 16r256E 1001 16r256F 1010 16r2570 110
		16r2574 1000 16r2575 10 16r2576 100 16r2577 1 16r2578 2000 16r2579 20 16r257A 200 16r257B 2
		16r257C 1200 16r257D 12 16r257E 2100 16r257F 21).
	1 to: spec size by: 2 do: [:i | | code |
		code := spec at: i + 1.
		BoxArms at: (spec at: i) put: (Array with: code // 1000 with: code // 100 \\ 10 with: code // 10 \\ 10 with: code \\ 10)].
	^BoxArms
! !

!TerminalView class methodsFor: 'colors'!
palette
	"The 16 ANSI colors, tuned for black on white with ultramarine as blue."
	^Palette ifNil: [Palette := #(16r000000 16rB3261E 16r2E7D32 16r8A6A00 16r1B3A8C 16r8E3B8E 16r1E7A84 16rB8B8B8
		16r6B6B6B 16rD7372C 16r3C9A46 16rB08A00 16r4A63A6 16rB052B0 16r2A9AA8 16rFFFFFF) collect: [:hex | Color hex: hex]]
!
colorOf: code
	"The Color of a TerminalScreen color code (1-256: palette index + 1, else 16r1000000 + RGB)."
	| i r g b levels |
	code > 256 ifTrue: [^Color hex: (code bitAnd: 16rFFFFFF)].
	i := code - 1.
	i < 16 ifTrue: [^self palette at: i + 1].
	i >= 232 ifTrue: [^Color gray: (i - 232 * 10 + 8) / 255.0].
	levels := #(0 95 135 175 215 255).
	i := i - 16.
	r := levels at: i // 36 + 1.
	g := levels at: i // 6 \\ 6 + 1.
	b := levels at: i \\ 6 + 1.
	^Color r: r / 255.0 g: g / 255.0 b: b / 255.0
! !
