ToolPane subclass: #TextView
	instanceVariableNames: 'editor'
	classVariableNames: ''
	package: 'Tools'!

TextView comment: 'I show a text read-only, monospaced and unhighlighted: e.g. a method''s machine code (the System Browser''s method menu).

	TextView openOn: (Integer >> #factorial) machineCode title: ''Machine code: Integer>>factorial'' near: nil'!

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
	| view |
	view := self new.
	view editor text: aString.
	^view openIn: (Tools placeNear: aWindowOrNil extent: 760 @ 520) title: aTitle
! !
