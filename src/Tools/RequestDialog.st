ToolPane subclass: #RequestDialog
	instanceVariableNames: 'editor answerBlock done'
	classVariableNames: ''
	package: 'Tools'!

RequestDialog comment: 'I ask for a line of text in a small window: a prompt, a code editor holding the initial answer (selected), Cancel and OK. Return accepts, Escape cancels. The answer block runs in my window''s Process, which ends right after it.

	Tools request: ''Log expression'' initialAnswer: ''a printString'' then: [:answer | ...]'!

!RequestDialog methodsFor: 'initialization'!
setPrompt: aString initialAnswer: answerString then: aBlock
	| buttons |
	answerBlock := aBlock.
	done := false.
	editor := ToolTextEditor new name: 'answer'; title: 'answer'; text: answerString; yourself.
	editor selectAll.
	editor onKey: [:evt |
		(evt key == #return or: [evt key == #enter])
			ifTrue: [self accept. true]
			ifFalse: [evt key == #escape ifTrue: [self cancel. true] ifFalse: [false]]].
	buttons := Row with: (Array
		with: (Widget new flex: 1)
		with: ((Button label: 'Cancel' action: [self cancel]) sizeToContent; yourself)
		with: ((Button label: 'OK' action: [self accept]) beDefault; sizeToContent; yourself)).
	buttons spacing: 6; padding: (12 @ 5 corner: 12 @ 6); fixed: 33.
	self separators: true.
	self addAll: (Array
		with: ((Label text: aString font: #uiBold) padding: (12 @ 0 corner: 12 @ 0); fixed: 28; yourself)
		with: editor
		with: buttons)
!
editor
	^editor
! !

!RequestDialog methodsFor: 'actions'!
accept
	| answer |
	done ifTrue: [^self].
	done := true.
	answer := editor text.
	"Closing ends my window's Process, so answer first."
	[answerBlock value: answer] ensure: [self window close]
!
cancel
	done := true.
	self window close
!
minimumWindowExtent
	^260 @ 140
! !

!RequestDialog methodsFor: 'events'!
keyDown: anEvent
	anEvent key == #escape ifTrue: [self cancel. ^true].
	^super keyDown: anEvent
! !

!RequestDialog class methodsFor: 'opening'!
prompt: aString initialAnswer: answerString then: aBlock
	"Open the dialog; aBlock receives the answer String unless cancelled. Answer the dialog."
	| dialog window |
	dialog := self new setPrompt: aString initialAnswer: answerString then: aBlock.
	window := dialog openIn: (Tools placeAt: nil extent: 420 @ 150) title: aString.
	window do: [dialog editor focus. dialog editor selectAll].
	^dialog
! !
