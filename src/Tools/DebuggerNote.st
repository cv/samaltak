Label subclass: #DebuggerNote
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tools'!

DebuggerNote comment: 'I am a muted italic remark in a button bar (other Processes keep running), right-aligned and cut with … when the bar is too narrow.'!

!DebuggerNote methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| s f w |
	s := self text.
	f := self font.
	w := self innerBounds width.
	(f widthOf: s) > w ifTrue: [
		[s size > 1 and: [(f widthOf: s, '…') > w]] whileTrue: [s := s first: s size - 1].
		s := s size > 1 ifTrue: [s, '…'] ifFalse: ['']].
	aCanvas drawString: s in: self innerBounds font: f color: self color align: self align
! !
