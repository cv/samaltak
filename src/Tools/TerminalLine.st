Object subclass: #TerminalLine
	instanceVariableNames: 'chars attrs wrapped serial'
	classVariableNames: ''
	package: 'Tools'!

TerminalLine comment: 'I am one row of a TerminalScreen (or of its scrollback): a character and a packed attribute per column (TerminalScreen attribute encoding), whether the text continues on the next row (wrapped by autowrap, so copying joins the rows), and a serial number that grows with every change, so a TerminalView redraws only the rows that changed.'!

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
string
	"My text without trailing blanks."
	| last |
	last := chars size.
	[last > 0 and: [(chars at: last) == $ ]] whileTrue: [last := last - 1].
	^(String new: last) replaceFrom: 1 to: last with: chars startingAt: 1; yourself
!
stringFrom: start to: stop
	"Columns start..stop (clipped to my width), trailing blanks removed."
	| last first |
	first := start max: 1.
	last := stop min: chars size.
	[last >= first and: [(chars at: last) == $ ]] whileTrue: [last := last - 1].
	last < first ifTrue: [^''].
	^(String new: last - first + 1) replaceFrom: 1 to: last - first + 1 with: chars startingAt: first; yourself
! !

!TerminalLine methodsFor: 'editing'!
clearWith: blankAttr
	chars atAllPut: $ .
	attrs atAllPut: blankAttr.
	wrapped := false.
	serial := serial + 1
!
eraseFrom: start to: stop attribute: blankAttr
	| last |
	last := stop min: chars size.
	start to: last do: [:c | chars at: c put: $ . attrs at: c put: blankAttr].
	serial := serial + 1
!
insertBlanks: n at: col attribute: blankAttr
	"Shift columns col.. right by n (dropping what passes the right edge); blank the gap."
	| width |
	width := chars size.
	width to: col + n by: -1 do: [:c |
		chars at: c put: (chars at: c - n).
		attrs at: c put: (attrs at: c - n)].
	col to: (col + n - 1 min: width) do: [:c | chars at: c put: $ . attrs at: c put: blankAttr].
	serial := serial + 1
!
deleteChars: n at: col attribute: blankAttr
	"Shift columns col+n.. left by n; blank the columns freed at the right edge."
	| width |
	width := chars size.
	col to: width - n do: [:c |
		chars at: c put: (chars at: c + n).
		attrs at: c put: (attrs at: c + n)].
	(width - n + 1 max: col) to: width do: [:c | chars at: c put: $ . attrs at: c put: blankAttr].
	serial := serial + 1
!
width: anInteger attribute: blankAttr
	"Truncate or extend me to anInteger columns."
	| oldChars oldAttrs n |
	anInteger = chars size ifTrue: [^self].
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
