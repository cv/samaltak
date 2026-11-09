ToolPane subclass: #TextView
	instanceVariableNames: 'editor'
	classVariableNames: ''
	package: 'Tools'!

TextView comment: 'I show a text read-only and monospaced, unhighlighted or, given a scanner (TextHighlighter scanner:), highlighted: e.g. a method''s machine code with MachineCodeScanner (the System Browser''s method menu).

	TextView openOn: (Integer >> #factorial) machineCode title: ''Machine code: Integer>>factorial'' near: nil scanner: MachineCodeScanner'!

!TextView methodsFor: 'initialization'!
initialize
	super initialize.
	editor := ToolTextEditor new name: 'text'; title: 'text'; readOnly: true; highlighting: false; yourself.
	self add: editor
! !

!TextView methodsFor: 'accessing'!
editor
	^editor
!
text
	^editor text
! !

!TextView class methodsFor: 'opening'!
openOn: aString title: aTitle near: aWindowOrNil
	^self openOn: aString title: aTitle near: aWindowOrNil scanner: nil
!
openOn: aString title: aTitle near: aWindowOrNil scanner: aScannerOrNil
	| view |
	view := self new.
	aScannerOrNil isNil ifFalse: [view editor scanner: aScannerOrNil; highlighting: true].
	view editor text: aString.
	^view openIn: (Tools placeNear: aWindowOrNil extent: 760 @ 520) title: aTitle
! !
