TextView subclass: #TranscriptView
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'ST80-UI'!

TranscriptView comment: 'I am Transcript, the System Transcript''s text: show: appends to my last line, cr starts a new one, scrolling up a line (a copy on the screen) when the window is full. Each line also goes to the VM''s standard output (the VM Simulator''s output pane).'!

!TranscriptView methodsFor: 'stream'!
show: aString
	| parts |
	parts := aString lines.
	parts isEmpty ifTrue: [^self].
	self append: parts first.
	parts allButFirstDo: [:each | self cr; append: each]
!
nextPutAll: aString
	self show: aString
!
nextPut: aCharacter
	self show: (String with: aCharacter)
!
print: anObject
	self show: anObject printString
!
display: anObject
	self show: anObject displayString
!
tab
	self show: (String with: Character tab)
!
space
	self show: ' '
!
cr
	| previous |
	self stdout: lines last , (String with: Character lf).
	previous := lines size.
	lines add: ''.
	line := lines size.
	column := start := 0.
	(window isNil or: [line < (top + rows) or: [window isCovered]]) ifTrue: [^self show: previous to: line].
	top := top + 1.
	Display copy: (left @ (self topOf: top + 1) corner: right @ (self topOf: top + rows)) to: left @ (self topOf: top).
	self show: previous to: line
!
flush
! !

!TranscriptView methodsFor: 'private'!
append: aString
	lines at: lines size put: lines last , aString.
	line := lines size.
	column := start := lines last size.
	self show: line to: line
!
stdout: aString
	<primitive: 'stdoutWrite'>
! !
