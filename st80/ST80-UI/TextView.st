Object subclass: #TextView
	instanceVariableNames: 'window lines line column start top bindings left y0 right rows columns cw ch'
	classVariableNames: ''
	package: 'ST80-UI'!

TextView comment: 'I am editable text in a window, one String per line, drawn a line at a time (a change redraws only its lines; layout keeps the geometry). The caret is at column (characters before it) of line; the selection runs from start to the caret on that line. Typing replaces the selection; cmd-P prints it (the whole line if nothing is selected): the guest''s Compiler compiles and runs it, the result is inserted after it, selected, and logged on the Transcript with the time it took; cmd-D does it. Workspace variables live in bindings.'!

!TextView class methodsFor: 'instance creation'!
text: aString
	^self new setText: aString
! !

!TextView methodsFor: 'initialization'!
initialize
	self setText: ''
!
setText: aString
	"The caret goes at the end (on a line of its own after a final line break)."
	lines := aString lines asOrderedCollection.
	(aString isEmpty or: [aString last = Character lf]) ifTrue: [lines add: ''].
	line := lines size.
	column := start := (lines at: line) size.
	top := 1.
	bindings := Dictionary new
!
window: aSystemView
	window := aSystemView.
	self layout
!
layout
	"My window's frame changed."
	| r |
	r := window inner.
	cw := Display cell x.
	ch := Display cell y.
	left := r left + 3.
	y0 := r top + 2.
	right := r right.
	rows := r height - 4 // ch.
	columns := r width - 6 // cw
! !

!TextView methodsFor: 'geometry'!
topOf: aLine
	^y0 + (aLine - top * ch)
!
lineAt: aPoint
	^(aPoint y - y0 // ch + top max: 1) min: lines size
!
columnAt: aPoint
	^(aPoint x - left + (cw // 2) // cw max: 0) min: (lines at: (self lineAt: aPoint)) size
! !

!TextView methodsFor: 'displaying'!
display
	top to: top + rows - 1 do: [:i | self displayLine: i]
!
displayLine: i
	| y s n |
	(i < top or: [i >= (top + rows)]) ifTrue: [^self].
	y := self topOf: i.
	s := i > lines size ifTrue: [''] ifFalse: [lines at: i].
	n := s size min: columns.
	Display white: ((left + (n * cw)) @ y corner: right @ (y + ch)).
	(i = line and: [start < column])
		ifTrue: [
			Display show: (s copyFrom: 1 to: (start min: n)) at: left @ y.
			Display showReversed: (s copyFrom: (start min: n) + 1 to: (column min: n)) at: (left + (start * cw)) @ y.
			Display show: (s copyFrom: (column min: n) + 1 to: n) at: (left + (column * cw)) @ y]
		ifFalse: [Display show: (s copyFrom: 1 to: n) at: left @ y].
	(i = line and: [start = column and: [column <= n]]) ifTrue: [
		Display black: ((left + (column * cw)) @ y extent: 1 @ ch)]
!
show: firstLine to: lastLine
	"Lines firstLine..lastLine changed (and the caret): scroll it into view, then draw them, or my window if it is covered."
	| scrolled |
	window isNil ifTrue: [^self].
	scrolled := line < top or: [line >= (top + rows)].
	line < top ifTrue: [top := line].
	line >= (top + rows) ifTrue: [top := line - rows + 1].
	window isCovered ifTrue: [^window redisplay].
	scrolled ifTrue: [^self display].
	firstLine to: lastLine do: [:i | self displayLine: i]
! !

!TextView methodsFor: 'editing'!
replace: aString
	"The selection by aString, which has no line breaks."
	| s |
	s := lines at: line.
	lines at: line put: (s copyFrom: 1 to: start) , aString , (s copyFrom: column + 1 to: s size).
	column := start := start + aString size
!
replaceSelectionWith: aString
	self replace: aString.
	self show: line to: line
!
select: aString
	"Insert aString after the selection and select it."
	start := column.
	self replace: aString.
	start := column - aString size.
	self show: line to: line
!
backspace
	| previous |
	start < column ifTrue: [^self replaceSelectionWith: ''].
	column > 0 ifTrue: [start := column - 1. ^self replaceSelectionWith: ''].
	line = 1 ifTrue: [^self].
	previous := lines at: line - 1.
	lines at: line - 1 put: previous , (lines at: line).
	lines removeIndex: line.
	line := line - 1.
	column := start := previous size.
	self show: line to: lines size + 1
!
newLine
	| s |
	s := lines at: line.
	lines at: line put: (s copyFrom: 1 to: start).
	lines add: (s copyFrom: column + 1 to: s size) beforeIndex: line + 1.
	line := line + 1.
	column := start := 0.
	self show: line - 1 to: lines size
!
moveTo: aLine column: aColumn
	| old |
	old := line.
	line := aLine.
	column := start := aColumn.
	self show: old to: old.
	self show: line to: line
! !

!TextView methodsFor: 'evaluating'!
selection
	"The selection, or the whole line if nothing is selected (then selected)."
	start = column ifTrue: [
		start := 0.
		column := (lines at: line) size].
	^(lines at: line) copyFrom: start + 1 to: column
!
printIt
	| result |
	result := self evaluate: self selection.
	start := column.
	self replace: ' '.
	self select: ((result copyReplaceAll: (String with: Character lf) with: ' ') first: (result size min: 60))
!
doIt
	self evaluate: self selection.
	self show: line to: line
!
evaluate: aString
	"Compile and run aString with the guest's Compiler; answer the printString of its value or of the error. The Transcript logs it."
	| result ms |
	ms := Time millisecondsToRun: [
		result := [(Compiler evaluate: aString for: nil bindings: bindings) printString]
			on: Error
			do: [:e | e return: e class name , ': ' , e messageText]].
	Transcript show: aString , ' --> ' , result , ' (' , ms printString , ' ms)'; cr.
	^result
! !

!TextView methodsFor: 'events'!
mouseDown: aPoint
	self moveTo: (self lineAt: aPoint) column: (self columnAt: aPoint)
!
key: aCode modifiers: anInteger
	| s |
	(anInteger bitAnd: 8) = 0 ifFalse: [
		aCode = $p value ifTrue: [^self printIt].
		aCode = $d value ifTrue: [^self doIt].
		^self].
	aCode = 8 ifTrue: [^self backspace].
	aCode = 13 ifTrue: [^self newLine].
	aCode = 9 ifTrue: [^self replaceSelectionWith: (String new: 4 - (start \\ 4) withAll: $ )].
	aCode = 28 ifTrue: [
		column > 0 ifTrue: [^self moveTo: line column: (start min: column - 1)].
		line > 1 ifTrue: [^self moveTo: line - 1 column: (lines at: line - 1) size].
		^self].
	aCode = 29 ifTrue: [
		s := lines at: line.
		column < s size ifTrue: [^self moveTo: line column: column + 1].
		line < lines size ifTrue: [^self moveTo: line + 1 column: 0].
		^self].
	aCode = 30 ifTrue: [line > 1 ifTrue: [self moveTo: line - 1 column: (column min: (lines at: line - 1) size)]. ^self].
	aCode = 31 ifTrue: [line < lines size ifTrue: [self moveTo: line + 1 column: (column min: (lines at: line + 1) size)]. ^self].
	aCode >= 32 ifTrue: [self replaceSelectionWith: (String with: (Character value: aCode))]
!
step
! !
