Object subclass: #TerminalLine
	instanceVariableNames: 'chars attrs wrapped serial marks'
	classVariableNames: ''
	package: 'Tools'!

TerminalLine comment: 'I am one row of a TerminalScreen (or of its scrollback): a character and a packed attribute per column (TerminalScreen attribute encoding), whether the text continues on the next row (wrapped by autowrap, so copying joins the rows), and a serial number that grows with every change, so a TerminalView redraws only the rows that changed.

A wide character (display width 2) takes two columns: the character, then a continuation cell holding NUL (which a program cannot print). Writing or erasing either half blanks the other. marks: nil, or column -> the characters that follow the one in that column in its grapheme cluster without a cell of their own (zero-width ones: combining marks, joiners, variation selectors; and those an emoji sequence joins: modifiers, the second regional indicator, the pictographs after a ZWJ); they are copied with it.'!

!TerminalLine methodsFor: 'initialization'!
setWidth: anInteger attribute: blankAttr
	chars := WideString new: anInteger withAll: $ .
	attrs := Array new: anInteger withAll: blankAttr.
	wrapped := false.
	serial := 0
! !

!TerminalLine methodsFor: 'accessing'!
chars
	^chars
!
attrs
	^attrs
!
size
	^chars size
!
serial
	^serial
!
changed
	serial := serial + 1
!
isWrapped
	^wrapped
!
wrapped: aBoolean
	wrapped := aBoolean
!
characterAt: col
	col > chars size ifTrue: [^$ ].
	^chars at: col
!
attributeAt: col
	col > attrs size ifTrue: [^0].
	^attrs at: col
!
isContinuationAt: col
	"Whether col is the right half of a wide character (which is in col - 1)."
	^col > 1 and: [col <= chars size and: [(chars at: col) value = 0]]
!
isWideAt: col
	"Whether col holds a wide character (its right half in col + 1)."
	^col >= 1 and: [col < chars size and: [(chars at: col + 1) value = 0]]
!
marks
	^marks
!
marksAt: col
	"The zero-width characters drawn over col, or nil."
	marks isNil ifTrue: [^nil].
	^marks at: col ifAbsent: [nil]
!
clusterAt: col
	"The character in col with its marks: a grapheme cluster."
	| m |
	m := self marksAt: col.
	m isNil ifTrue: [^String with: (self characterAt: col)].
	^(String with: (self characterAt: col)), m
!
string
	"My text without trailing blanks."
	^self stringFrom: 1 to: chars size
!
stringFrom: start to: stop
	"Columns start..stop (clipped to my width; a wide character half in them whole), trailing blanks removed; marks follow their characters."
	| last first |
	first := start max: 1.
	(self isContinuationAt: first) ifTrue: [first := first - 1].
	last := stop min: chars size.
	[last >= first and: [(chars at: last) == $  and: [(self marksAt: last) isNil]]] whileTrue: [last := last - 1].
	last < first ifTrue: [^''].
	^String new: last - first + 1 streamContents: [:s |
		first to: last do: [:c | | ch |
			ch := chars at: c.
			ch value = 0 ifFalse: [s nextPut: ch].
			marks isNil ifFalse: [(marks at: c ifAbsent: [nil]) ifNotNil: [:m | s nextPutAll: m]]]]
! !

!TerminalLine methodsFor: 'editing'!
put: aCharacter at: col width: w attribute: a
	"Write aCharacter into col, a wide one (w = 2) into col and col + 1."
	(marks notNil or: [(chars at: col) value = 0 or: [col + w <= chars size and: [(chars at: col + w) value = 0]]])
		ifTrue: [self overwriteFrom: col to: col + w - 1].
	chars at: col put: aCharacter.
	attrs at: col put: a.
	w = 2 ifTrue: [
		chars at: col + 1 put: (Character value: 0).
		attrs at: col + 1 put: a].
	serial := serial + 1
!
addMark: aCharacter at: col
	"A zero-width character after the one in col (at most 16 per column)."
	| m |
	marks isNil ifTrue: [marks := Dictionary new].
	m := marks at: col ifAbsent: [''].
	m size < 16 ifTrue: [marks at: col put: m, (String with: aCharacter)].
	serial := serial + 1
!
overwriteFrom: start to: stop
	"Before columns start..stop are written: blank the halves of wide characters cut at either end, drop the marks."
	self splitAt: start; splitAt: stop + 1.
	marks isNil ifFalse: [self removeMarksFrom: start to: stop]
!
splitAt: col
	"If a wide character straddles the boundary before col, blank both its halves."
	(self isContinuationAt: col) ifFalse: [^self].
	chars at: col - 1 put: $ .
	chars at: col put: $ .
	marks isNil ifFalse: [self removeMarksFrom: col - 1 to: col]
!
removeMarksFrom: start to: stop
	(marks keys select: [:c | c between: start and: stop]) do: [:c | marks removeKey: c].
	marks isEmpty ifTrue: [marks := nil]
!
shiftMarksAt: col by: delta
	"Columns col.. moved by delta (insert: +n, delete: -n): their marks move along; those deleted or moved off the line go."
	| old |
	old := marks.
	marks := nil.
	old keysAndValuesDo: [:c :m | | to |
		to := c < col ifTrue: [c] ifFalse: [(c - col) < delta negated ifTrue: [0] ifFalse: [c + delta]].
		(to between: 1 and: chars size) ifTrue: [
			marks isNil ifTrue: [marks := Dictionary new].
			marks at: to put: m]]
!
clearWith: blankAttr
	chars atAllPut: $ .
	attrs atAllPut: blankAttr.
	wrapped := false.
	marks := nil.
	serial := serial + 1
!
eraseFrom: start to: stop attribute: blankAttr
	| last |
	last := stop min: chars size.
	self overwriteFrom: start to: last.
	start to: last do: [:c | chars at: c put: $ . attrs at: c put: blankAttr].
	serial := serial + 1
!
insertBlanks: n at: col attribute: blankAttr
	"Shift columns col.. right by n (dropping what passes the right edge); blank the gap."
	| width |
	width := chars size.
	self splitAt: col; splitAt: (width - n + 1 max: col).
	width to: col + n by: -1 do: [:c |
		chars at: c put: (chars at: c - n).
		attrs at: c put: (attrs at: c - n)].
	col to: (col + n - 1 min: width) do: [:c | chars at: c put: $ . attrs at: c put: blankAttr].
	marks isNil ifFalse: [self shiftMarksAt: col by: n].
	serial := serial + 1
!
deleteChars: n at: col attribute: blankAttr
	"Shift columns col+n.. left by n; blank the columns freed at the right edge."
	| width |
	width := chars size.
	self splitAt: col; splitAt: col + n.
	col to: width - n do: [:c |
		chars at: c put: (chars at: c + n).
		attrs at: c put: (attrs at: c + n)].
	(width - n + 1 max: col) to: width do: [:c | chars at: c put: $ . attrs at: c put: blankAttr].
	marks isNil ifFalse: [self shiftMarksAt: col by: n negated].
	serial := serial + 1
!
width: anInteger attribute: blankAttr
	"Truncate or extend me to anInteger columns."
	| oldChars oldAttrs n |
	anInteger = chars size ifTrue: [^self].
	self splitAt: anInteger + 1.
	marks isNil ifFalse: [self removeMarksFrom: anInteger + 1 to: chars size].
	oldChars := chars.
	oldAttrs := attrs.
	n := oldChars size min: anInteger.
	chars := WideString new: anInteger withAll: $ .
	attrs := Array new: anInteger withAll: blankAttr.
	chars replaceFrom: 1 to: n with: oldChars startingAt: 1.
	attrs replaceFrom: 1 to: n with: oldAttrs startingAt: 1.
	serial := serial + 1
! !

!TerminalLine methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a TerminalLine('; print: self string; nextPut: $)
! !

!TerminalLine class methodsFor: 'instance creation'!
width: anInteger attribute: blankAttr
	^self new setWidth: anInteger attribute: blankAttr
! !
