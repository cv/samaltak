Object subclass: #TerminalScreen
	instanceVariableNames: 'rows cols lines mainLines row col pendingWrap attr top bottom autowrap originMode insertMode newlineMode cursorVisible appCursorKeys bracketedPaste mouseTracking saved savedMain tabStops scrollback maxScrollback scrolledTotal title titleSerial replies charsets activeCharset lastChar serial'
	classVariableNames: 'BgShift Bold Dim FgMask Hidden Inverse Italic LineDrawing Strike Underline Widths'
	package: 'Tools'!

TerminalScreen comment: 'I am the screen of a terminal emulator (VT100/xterm): rows × columns of TerminalLines, the cursor, the scroll region, the modes, a second (alternate) screen for full-screen programs, and a bounded scrollback of the lines scrolled off the top of the main screen. A TerminalParser turns a program''s output into my operations; a TerminalView draws me.

A character takes the cells of its display width (Unicode displayWidthOf:, as wcwidth, which programs assume): a wide one two (TerminalLine), a zero-width one none (it joins the character before the cursor).

Cursor positions are 1-based (row, col). pendingWrap: the last character went into the last column; the next one wraps first (xterm''s delayed autowrap).

Attributes are one SmallInteger per cell: the foreground in bits 0-24, the background in bits 25-49 (0 default, 1-256 palette index + 1, 16r1000000 + 16rRRGGBB truecolor), then the flags Bold Dim Italic Underline Inverse Hidden Strike. Erasing fills with the current background (xterm''s background color erase).

Answers to the program (device status reports, device attributes) collect in replies, which my owner sends back to it (takeReplies). title is set by OSC 0/2; titleSerial grows when it changes. serial grows with every change.'!

!TerminalScreen methodsFor: 'initialization'!
setRows: r cols: c
	rows := r.
	cols := c.
	maxScrollback := 5000.
	scrollback := OrderedCollection new.
	scrolledTotal := 0.
	title := ''.
	titleSerial := 0.
	serial := 0.
	replies := WriteStream on: (String new: 16).
	self reset
!
reset
	"RIS: the initial state (the scrollback stays)."
	attr := 0.
	lines := (1 to: rows) collect: [:i | TerminalLine width: cols attribute: 0].
	mainLines := nil.
	row := 1.
	col := 1.
	pendingWrap := false.
	top := 1.
	bottom := rows.
	autowrap := true.
	originMode := false.
	insertMode := false.
	newlineMode := false.
	cursorVisible := true.
	appCursorKeys := false.
	bracketedPaste := false.
	mouseTracking := 0.
	saved := nil.
	savedMain := nil.
	charsets := Array with: #ascii with: #ascii.
	activeCharset := 1.
	lastChar := nil.
	self resetTabStops.
	self touchAll
!
resetTabStops
	tabStops := (1 to: cols) collect: [:c | c \\ 8 = 1 and: [c > 1]]
! !

!TerminalScreen methodsFor: 'accessing'!
rows
	^rows
!
cols
	^cols
!
lines
	"The screen's rows (TerminalLines), top to bottom."
	^lines
!
lineAt: r
	^lines at: r
!
row
	^row
!
col
	"The cursor column (1..cols)."
	^col
!
attribute
	^attr
!
attribute: anInteger
	attr := anInteger
!
title
	^title
!
title: aString
	title = aString ifTrue: [^self].
	title := aString.
	titleSerial := titleSerial + 1
!
titleSerial
	^titleSerial
!
serial
	^serial
!
scrollTop
	^top
!
scrollBottom
	^bottom
!
isCursorVisible
	^cursorVisible
!
isAlternateScreen
	^mainLines notNil
!
appCursorKeys
	^appCursorKeys
!
bracketedPaste
	^bracketedPaste
!
mouseTracking
	"The xterm mouse mode the program asked for (0 none, 1000, 1002, 1003); I only record it."
	^mouseTracking
!
autowrap
	^autowrap
!
insertMode
	^insertMode
!
pendingWrap
	^pendingWrap
!
tabStops
	^tabStops
! !

!TerminalScreen methodsFor: 'scrollback'!
scrollback
	"Lines scrolled off the top of the main screen, oldest first (at most maxScrollback)."
	^scrollback
!
maxScrollback
	^maxScrollback
!
maxScrollback: anInteger
	maxScrollback := anInteger.
	[scrollback size > maxScrollback] whileTrue: [scrollback removeFirst]
!
scrolledTotal
	"How many lines ever went into the scrollback: the absolute index of screen row r is scrolledTotal + r."
	^scrolledTotal
!
firstLineIndex
	"The absolute index of the oldest line kept."
	^scrolledTotal - scrollback size + 1
!
lineAtIndex: anInteger
	"The line with absolute index anInteger (scrollback or screen), or nil."
	| i |
	i := anInteger - scrolledTotal.
	i >= 1 ifTrue: [^i <= rows ifTrue: [lines at: i] ifFalse: [nil]].
	i := scrollback size + i.
	^i >= 1 ifTrue: [scrollback at: i] ifFalse: [nil]
!
clearScrollback
	scrollback := OrderedCollection new.
	self touchAll
! !

!TerminalScreen methodsFor: 'replies'!
reply: aString
	replies nextPutAll: aString
!
takeReplies
	"Answer what I must send to the program, and forget it."
	| s |
	replies position = 0 ifTrue: [^''].
	s := replies contents.
	replies := WriteStream on: (String new: 16).
	^s
! !

!TerminalScreen methodsFor: 'text'!
text
	"The screen's text, one line per row, trailing blanks removed."
	^String new: rows * (cols + 1) streamContents: [:s |
		lines do: [:line | s nextPutAll: line string] separatedBy: [s nextPut: Character lf]]
!
textOfRow: r
	^(lines at: r) string
! !

!TerminalScreen methodsFor: 'printing characters'!
putBytes: bytes from: start to: stop
	"Print the printable ASCII bytes start..stop (32..126) at the cursor."
	| i n line chars attrs a c |
	activeCharset == 1
		ifTrue: [(charsets at: 1) == #ascii ifFalse: [^start to: stop do: [:k | self putCharacter: (Character value: (bytes at: k))]]]
		ifFalse: [(charsets at: 2) == #ascii ifFalse: [^start to: stop do: [:k | self putCharacter: (Character value: (bytes at: k))]]].
	insertMode ifTrue: [^start to: stop do: [:k | self putCharacter: (Character value: (bytes at: k))]].
	i := start.
	a := attr.
	[i <= stop] whileTrue: [
		pendingWrap ifTrue: [self wrap].
		line := lines at: row.
		chars := line chars.
		attrs := line attrs.
		n := stop - i + 1 min: cols - col + 1.
		c := col.
		line overwriteFrom: c to: c + n - 1.
		i to: i + n - 1 do: [:k |
			chars at: c put: (Character value: (bytes at: k)).
			attrs at: c put: a.
			c := c + 1].
		line changed.
		i := i + n.
		c > cols
			ifTrue: [col := cols. pendingWrap := autowrap]
			ifFalse: [col := c]].
	lastChar := Character value: (bytes at: stop).
	serial := serial + 1
!
putCharacter: aCharacter
	"Print one character at the cursor (charset mapping, insert mode, delayed autowrap). A wide character takes two cells: at the last column it wraps first (or, without autowrap, goes into the last two); a zero-width one joins the character before the cursor."
	| ch line w |
	ch := aCharacter.
	(ch value < 128 and: [(charsets at: activeCharset) == #lineDrawing]) ifTrue: [ch := self lineDrawing: ch].
	w := ch value < 16r300 ifTrue: [1] ifFalse: [self class widthOf: ch value].
	w = 0 ifTrue: [^self putMark: ch].
	w > cols ifTrue: [^self].
	pendingWrap ifTrue: [self wrap].
	col + w - 1 > cols ifTrue: [autowrap ifTrue: [self wrap] ifFalse: [col := cols - w + 1]].
	line := lines at: row.
	insertMode ifTrue: [line insertBlanks: w at: col attribute: attr].
	line put: ch at: col width: w attribute: attr.
	col + w <= cols
		ifTrue: [col := col + w]
		ifFalse: [col := cols. pendingWrap := autowrap].
	lastChar := ch.
	serial := serial + 1
!
putMark: aCharacter
	"A zero-width character (combining mark, joiner, variation selector): it goes with the character before the cursor."
	| c line |
	c := pendingWrap ifTrue: [col] ifFalse: [col - 1].
	c < 1 ifTrue: [^self].
	line := lines at: row.
	(line isContinuationAt: c) ifTrue: [c := c - 1].
	line addMark: aCharacter at: c.
	serial := serial + 1
!
repeatLastCharacter: n
	"REP"
	lastChar isNil ifTrue: [^self].
	(n min: rows * cols) timesRepeat: [self putCharacter: lastChar]
!
wrap
	pendingWrap := false.
	(lines at: row) wrapped: true.
	col := 1.
	self index
!
lineDrawing: aCharacter
	"DEC special graphics (ESC ( 0)."
	| i |
	i := '`abcdefghijklmnopqrstuvwxyz{|}~' indexOf: aCharacter.
	i = 0 ifTrue: [^aCharacter].
	^Character value: (#(16r25C6 16r2592 16r2409 16r240C 16r240D 16r240A 16rB0 16rB1 16r2424 16r240B 16r2518 16r2510 16r250C 16r2514 16r253C 16r23BA 16r23BB 16r2500 16r23BC 16r23BD 16r251C 16r2524 16r2534 16r252C 16r2502 16r2264 16r2265 16r3C0 16r2260 16rA3 16rB7) at: i)
!
designate: aSymbol charset: index
	"ESC ( 0 / ESC ( B (index 1, G0), ESC ) … (index 2, G1)."
	charsets at: index put: aSymbol
!
shiftTo: index
	"SI (G0) / SO (G1)."
	activeCharset := index
! !

!TerminalScreen methodsFor: 'control characters'!
carriageReturn
	col := 1.
	pendingWrap := false
!
lineFeed
	"LF, VT, FF: down one row, scrolling at the bottom of the scroll region (and to column 1 in newline mode)."
	newlineMode ifTrue: [col := 1].
	pendingWrap := false.
	self index
!
index
	"IND: down one row, scrolling the region at its bottom."
	row = bottom
		ifTrue: [self scrollUp: 1]
		ifFalse: [row < rows ifTrue: [row := row + 1]].
	serial := serial + 1
!
reverseIndex
	"RI: up one row, scrolling the region down at its top."
	pendingWrap := false.
	row = top
		ifTrue: [self scrollDown: 1]
		ifFalse: [row > 1 ifTrue: [row := row - 1]].
	serial := serial + 1
!
nextLine
	"NEL"
	self carriageReturn; index
!
backspace
	pendingWrap := false.
	col > 1 ifTrue: [col := col - 1]
!
tab
	self tabForward: 1
!
tabForward: n
	n timesRepeat: [
		[col < cols and: [(tabStops at: (col := col + 1)) not]] whileTrue].
	pendingWrap := false
!
tabBackward: n
	n timesRepeat: [
		[col > 1 and: [(tabStops at: (col := col - 1)) not]] whileTrue].
	pendingWrap := false
!
setTabStop
	"HTS"
	tabStops at: col put: true
!
clearTabStop: mode
	"TBC: 0 at the cursor, 3 all."
	mode = 0 ifTrue: [tabStops at: col put: false].
	mode = 3 ifTrue: [tabStops atAllPut: false]
! !

!TerminalScreen methodsFor: 'cursor'!
moveTo: r col: c
	"CUP (1-based, relative to the scroll region in origin mode)."
	originMode
		ifTrue: [row := (r + top - 1 max: top) min: bottom]
		ifFalse: [row := (r max: 1) min: rows].
	col := (c max: 1) min: cols.
	pendingWrap := false.
	serial := serial + 1
!
moveToRow: r
	"VPA"
	self moveTo: r col: col
!
moveToCol: c
	"CHA, HPA"
	col := (c max: 1) min: cols.
	pendingWrap := false.
	serial := serial + 1
!
cursorUp: n
	"CUU: stops at the top margin when inside the region."
	row := row - (n max: 1) max: (row >= top ifTrue: [top] ifFalse: [1]).
	pendingWrap := false.
	serial := serial + 1
!
cursorDown: n
	row := row + (n max: 1) min: (row <= bottom ifTrue: [bottom] ifFalse: [rows]).
	pendingWrap := false.
	serial := serial + 1
!
cursorForward: n
	col := col + (n max: 1) min: cols.
	pendingWrap := false.
	serial := serial + 1
!
cursorBackward: n
	col := col - (n max: 1) max: 1.
	pendingWrap := false.
	serial := serial + 1
!
saveCursor
	"DECSC"
	saved := {row. col. attr. originMode. charsets copy. activeCharset. pendingWrap}
!
restoreCursor
	"DECRC"
	saved isNil ifTrue: [row := 1. col := 1. attr := 0. originMode := false. pendingWrap := false. ^self].
	row := (saved at: 1) min: rows.
	col := (saved at: 2) min: cols.
	attr := saved at: 3.
	originMode := saved at: 4.
	charsets := (saved at: 5) copy.
	activeCharset := saved at: 6.
	pendingWrap := saved at: 7.
	serial := serial + 1
! !

!TerminalScreen methodsFor: 'erasing'!
blank
	"The attribute of erased cells: the current background."
	^attr bitAnd: FgMask << BgShift
!
eraseInLine: mode
	"EL: 0 cursor to end, 1 start to cursor, 2 whole line."
	| line |
	line := lines at: row.
	mode = 0 ifTrue: [line eraseFrom: col to: cols attribute: self blank. line wrapped: false].
	mode = 1 ifTrue: [line eraseFrom: 1 to: col attribute: self blank].
	mode = 2 ifTrue: [line eraseFrom: 1 to: cols attribute: self blank. line wrapped: false].
	pendingWrap := false.
	serial := serial + 1
!
eraseInDisplay: mode
	"ED: 0 cursor to end, 1 start to cursor, 2 everything, 3 the scrollback."
	| b |
	b := self blank.
	mode = 0 ifTrue: [
		self eraseInLine: 0.
		row + 1 to: rows do: [:r | (lines at: r) clearWith: b]].
	mode = 1 ifTrue: [
		1 to: row - 1 do: [:r | (lines at: r) clearWith: b].
		self eraseInLine: 1].
	mode = 2 ifTrue: [lines do: [:line | line clearWith: b]].
	mode = 3 ifTrue: [self clearScrollback].
	pendingWrap := false.
	serial := serial + 1
!
eraseChars: n
	"ECH"
	(lines at: row) eraseFrom: col to: col + (n max: 1) - 1 attribute: self blank.
	pendingWrap := false.
	serial := serial + 1
!
insertChars: n
	"ICH"
	(lines at: row) insertBlanks: ((n max: 1) min: cols - col + 1) at: col attribute: self blank.
	pendingWrap := false.
	serial := serial + 1
!
deleteChars: n
	"DCH"
	(lines at: row) deleteChars: ((n max: 1) min: cols - col + 1) at: col attribute: self blank.
	pendingWrap := false.
	serial := serial + 1
!
fillWithE
	"DECALN: the screen alignment test."
	lines do: [:line | line clearWith: 0. line chars atAllPut: $E].
	top := 1.
	bottom := rows.
	self moveTo: 1 col: 1
! !

!TerminalScreen methodsFor: 'scrolling'!
setScrollRegionTop: t bottom: b
	"DECSTBM; the cursor goes home."
	| tt bb |
	tt := t max: 1.
	bb := (b = 0 ifTrue: [rows] ifFalse: [b]) min: rows.
	tt < bb ifFalse: [^self].
	top := tt.
	bottom := bb.
	self moveTo: 1 col: 1
!
scrollUp: n
	"SU and scrolling at the bottom: the region's lines move up n; lines leaving the top of the main screen go to the scrollback."
	self scrollUp: n keep: (top = 1 and: [mainLines isNil])
!
scrollUp: n keep: toScrollback
	| count b gone |
	count := (n max: 1) min: bottom - top + 1.
	b := self blank.
	gone := Array new: count.
	1 to: count do: [:k | gone at: k put: (lines at: top + k - 1)].
	lines replaceFrom: top to: bottom - count with: lines startingAt: top + count.
	1 to: count do: [:k | | line |
		line := gone at: k.
		toScrollback
			ifTrue: [line := self pushToScrollback: line]
			ifFalse: [line clearWith: b].
		line size = cols ifFalse: [line width: cols attribute: b].
		lines at: bottom - count + k put: line].
	serial := serial + 1
!
pushToScrollback: aLine
	"Keep aLine in the scrollback; answer a blank line to reuse (the oldest one when the scrollback is full)."
	| old |
	scrolledTotal := scrolledTotal + 1.
	maxScrollback = 0 ifTrue: [aLine clearWith: self blank. ^aLine].
	scrollback addLast: aLine.
	scrollback size > maxScrollback ifFalse: [^TerminalLine width: cols attribute: self blank].
	old := scrollback removeFirst.
	old clearWith: self blank.
	^old
!
scrollDown: n
	"SD and reverse index at the top: the region's lines move down n."
	| count b gone |
	count := (n max: 1) min: bottom - top + 1.
	b := self blank.
	gone := Array new: count.
	1 to: count do: [:k | gone at: k put: (lines at: bottom - count + k)].
	bottom to: top + count by: -1 do: [:r | lines at: r put: (lines at: r - count)].
	1 to: count do: [:k | | line |
		line := gone at: k.
		line clearWith: b.
		line size = cols ifFalse: [line width: cols attribute: b].
		lines at: top + k - 1 put: line].
	serial := serial + 1
!
insertLines: n
	"IL: inside the region, push the lines from the cursor's down."
	| t |
	(row between: top and: bottom) ifFalse: [^self].
	t := top.
	top := row.
	[self scrollDown: n] ensure: [top := t].
	col := 1.
	pendingWrap := false
!
deleteLines: n
	"DL"
	| t |
	(row between: top and: bottom) ifFalse: [^self].
	t := top.
	top := row.
	[self scrollUp: n keep: false] ensure: [top := t].
	col := 1.
	pendingWrap := false
! !

!TerminalScreen methodsFor: 'modes'!
setMode: anInteger private: isPrivate to: aBoolean
	"SM/RM and DECSET/DECRST."
	isPrivate ifFalse: [
		anInteger = 4 ifTrue: [insertMode := aBoolean].
		anInteger = 20 ifTrue: [newlineMode := aBoolean].
		^self].
	anInteger = 1 ifTrue: [^appCursorKeys := aBoolean].
	anInteger = 6 ifTrue: [originMode := aBoolean. ^self moveTo: 1 col: 1].
	anInteger = 7 ifTrue: [^autowrap := aBoolean].
	anInteger = 25 ifTrue: [cursorVisible := aBoolean. ^serial := serial + 1].
	(anInteger = 47 or: [anInteger = 1047]) ifTrue: [^self alternateScreen: aBoolean saveCursor: false].
	anInteger = 1049 ifTrue: [^self alternateScreen: aBoolean saveCursor: true].
	anInteger = 1048 ifTrue: [^aBoolean ifTrue: [self saveCursor] ifFalse: [self restoreCursor]].
	anInteger = 2004 ifTrue: [^bracketedPaste := aBoolean].
	(#(9 1000 1002 1003) includes: anInteger) ifTrue: [^mouseTracking := aBoolean ifTrue: [anInteger] ifFalse: [0]]
!
alternateScreen: aBoolean saveCursor: save
	"Enter (a fresh, blank) or leave the alternate screen; leaving shows the main screen as it was."
	aBoolean = self isAlternateScreen ifTrue: [^self].
	aBoolean
		ifTrue: [
			save ifTrue: [self saveCursor. savedMain := saved].
			mainLines := lines.
			lines := (1 to: rows) collect: [:i | TerminalLine width: cols attribute: self blank]]
		ifFalse: [
			lines := mainLines.
			mainLines := nil.
			lines do: [:line | line changed].
			save ifTrue: [saved := savedMain. self restoreCursor]].
	pendingWrap := false.
	self touchAll
! !

!TerminalScreen methodsFor: 'attributes'!
selectGraphicRendition: params count: n
	"SGR: params is an Array of Integers (nil = default), the first n used; colons and semicolons alike."
	| i p |
	n = 0 ifTrue: [^attr := 0].
	i := 1.
	[i <= n] whileTrue: [
		p := (params at: i) ifNil: [0].
		p = 0 ifTrue: [attr := 0].
		p = 1 ifTrue: [attr := attr bitOr: Bold].
		p = 2 ifTrue: [attr := attr bitOr: Dim].
		p = 3 ifTrue: [attr := attr bitOr: Italic].
		p = 4 ifTrue: [attr := attr bitOr: Underline].
		p = 7 ifTrue: [attr := attr bitOr: Inverse].
		p = 8 ifTrue: [attr := attr bitOr: Hidden].
		p = 9 ifTrue: [attr := attr bitOr: Strike].
		p = 21 ifTrue: [attr := attr bitOr: Underline].
		p = 22 ifTrue: [attr := attr bitAnd: (Bold bitOr: Dim) bitInvert].
		p = 23 ifTrue: [attr := attr bitAnd: Italic bitInvert].
		p = 24 ifTrue: [attr := attr bitAnd: Underline bitInvert].
		p = 27 ifTrue: [attr := attr bitAnd: Inverse bitInvert].
		p = 28 ifTrue: [attr := attr bitAnd: Hidden bitInvert].
		p = 29 ifTrue: [attr := attr bitAnd: Strike bitInvert].
		(p between: 30 and: 37) ifTrue: [self foreground: p - 30 + 1].
		p = 39 ifTrue: [self foreground: 0].
		(p between: 40 and: 47) ifTrue: [self background: p - 40 + 1].
		p = 49 ifTrue: [self background: 0].
		(p between: 90 and: 97) ifTrue: [self foreground: p - 90 + 9].
		(p between: 100 and: 107) ifTrue: [self background: p - 100 + 9].
		(p = 38 or: [p = 48]) ifTrue: [ | color |
			color := nil.
			((params at: i + 1 ifAbsent: [nil]) = 5 and: [i + 2 <= n]) ifTrue: [
				color := ((params at: i + 2) ifNil: [0]) \\ 256 + 1.
				i := i + 2].
			((params at: i + 1 ifAbsent: [nil]) = 2 and: [i + 4 <= n]) ifTrue: [
				color := 16r1000000
					+ ((((params at: i + 2) ifNil: [0]) bitAnd: 255) bitShift: 16)
					+ ((((params at: i + 3) ifNil: [0]) bitAnd: 255) bitShift: 8)
					+ (((params at: i + 4) ifNil: [0]) bitAnd: 255).
				i := i + 4].
			color isNil ifFalse: [p = 38 ifTrue: [self foreground: color] ifFalse: [self background: color]]].
		i := i + 1]
!
foreground: code
	attr := (attr bitAnd: FgMask bitInvert) bitOr: code
!
background: code
	attr := (attr bitAnd: (FgMask << BgShift) bitInvert) bitOr: code << BgShift
! !

!TerminalScreen methodsFor: 'reports'!
reportStatus: n
	"DSR: 5 status, 6 cursor position."
	n = 5 ifTrue: [self reply: (String with: Character escape), '[0n'].
	n = 6 ifTrue: [self reply: (String with: Character escape), '[', (originMode ifTrue: [row - top + 1] ifFalse: [row]) printString, ';', col printString, 'R']
!
reportAttributes: secondary
	"DA: a VT220-ish terminal."
	self reply: (String with: Character escape), (secondary ifTrue: ['[>0;10;0c'] ifFalse: ['[?62;22c'])
! !

!TerminalScreen methodsFor: 'resizing'!
rows: r cols: c
	"Resize to r × c: lines are cut or extended at the right; when rows go, lines above the cursor go to the scrollback (main screen) so the cursor's line stays."
	| newRows newCols excess |
	newRows := r max: 1.
	newCols := c max: 1.
	(newRows = rows and: [newCols = cols]) ifTrue: [^self].
	newCols = cols ifFalse: [
		lines do: [:line | line width: newCols attribute: 0].
		mainLines isNil ifFalse: [mainLines do: [:line | line width: newCols attribute: 0]].
		cols := newCols.
		self resetTabStops].
	newRows < rows ifTrue: [
		excess := row - newRows max: 0.
		excess > 0 ifTrue: [
			1 to: excess do: [:k | self isAlternateScreen ifFalse: [scrollback addLast: (lines at: k). scrolledTotal := scrolledTotal + 1]].
			[scrollback size > maxScrollback] whileTrue: [scrollback removeFirst].
			lines := lines copyFrom: excess + 1 to: lines size.
			mainLines isNil ifFalse: [mainLines := mainLines copyFrom: (excess + 1 min: mainLines size) to: mainLines size].
			row := row - excess].
		lines := lines copyFrom: 1 to: newRows.
		mainLines isNil ifFalse: [mainLines := mainLines copyFrom: 1 to: (newRows min: mainLines size)]].
	lines size < newRows ifTrue: [lines := lines , ((lines size + 1 to: newRows) collect: [:i | TerminalLine width: newCols attribute: 0])].
	(mainLines notNil and: [mainLines size < newRows]) ifTrue: [
		mainLines := mainLines , ((mainLines size + 1 to: newRows) collect: [:i | TerminalLine width: newCols attribute: 0])].
	rows := newRows.
	top := 1.
	bottom := rows.
	row := row min: rows.
	col := col min: cols.
	pendingWrap := false.
	self touchAll
! !

!TerminalScreen methodsFor: 'changes'!
touchAll
	"Everything shown changed (all lines are drawn anew)."
	serial := serial + 1.
	lines do: [:line | line changed]
! !

!TerminalScreen class methodsFor: 'instance creation'!
rows: r cols: c
	^self new setRows: r cols: c
! !

!TerminalScreen class methodsFor: 'attributes'!
initialize
	FgMask := 16r1FFFFFF.
	BgShift := 25.
	Bold := 1 << 50.
	Dim := 1 << 51.
	Italic := 1 << 52.
	Underline := 1 << 53.
	Inverse := 1 << 54.
	Hidden := 1 << 55.
	Strike := 1 << 56.
	Widths := ByteArray new: 16r10000 withAll: 3
!
widthOf: codePoint
	"Unicode displayWidthOf: codePoint, kept for the BMP (Widths: 3 = not looked up yet)."
	| w |
	codePoint > 16rFFFF ifTrue: [^Unicode displayWidthOf: codePoint].
	w := Widths at: codePoint + 1.
	w < 3 ifTrue: [^w].
	^Widths at: codePoint + 1 put: (Unicode displayWidthOf: codePoint)
!
foregroundOf: anAttribute
	^anAttribute bitAnd: FgMask
!
backgroundOf: anAttribute
	^(anAttribute bitShift: BgShift negated) bitAnd: FgMask
!
isBold: anAttribute
	^(anAttribute bitAnd: Bold) ~= 0
!
isDim: anAttribute
	^(anAttribute bitAnd: Dim) ~= 0
!
isItalic: anAttribute
	^(anAttribute bitAnd: Italic) ~= 0
!
isUnderline: anAttribute
	^(anAttribute bitAnd: Underline) ~= 0
!
isInverse: anAttribute
	^(anAttribute bitAnd: Inverse) ~= 0
!
isHidden: anAttribute
	^(anAttribute bitAnd: Hidden) ~= 0
!
isStrike: anAttribute
	^(anAttribute bitAnd: Strike) ~= 0
! !
