ToolPane subclass: #ConfirmDialog
	instanceVariableNames: 'answerBlock done'
	classVariableNames: ''
	package: 'Tools'!

ConfirmDialog comment: 'I ask whether to do something that cannot be undone: a title, the details (what, where, how much: the installer''s disk, partition and size), Cancel and a button naming the action. Escape or closing the window is Cancel. confirm:details:action: waits for the answer (from any Process but my window''s); title:details:action:then: answers at once and calls the block with true or false later, in my window''s Process.

	(ConfirmDialog confirm: ''Write the image store'' details: ''Disk ... partition 3 ...'' action: ''Write'') ifTrue: [...]'!

!ConfirmDialog class methodsFor: 'opening'!
title: aTitle details: aString action: aLabel then: aBlock
	| dialog |
	dialog := self new setTitle: aTitle details: aString action: aLabel then: aBlock.
	dialog openIn: (Tools placeAt: nil extent: 600 @ 280) title: aTitle.
	^dialog
!
confirm: aTitle details: aString action: aLabel
	"Ask and wait: true only if the action's button was clicked."
	| sem answer |
	sem := Semaphore new.
	answer := false.
	self title: aTitle details: aString action: aLabel then: [:ok | answer := ok. sem signal].
	sem wait.
	^answer
!
wrap: aString width: columns
	"aString's lines with their words wrapped at columns characters."
	^String streamContents: [:s |
		aString lines do: [:line | | n |
			n := 0.
			line substrings do: [:word |
				(n > 0 and: [n + 1 + word size > columns]) ifTrue: [s nextPut: Character lf. n := 0].
				n > 0 ifTrue: [s space. n := n + 1].
				s nextPutAll: word.
				n := n + word size].
			s nextPut: Character lf]]
! !

!ConfirmDialog methodsFor: 'initialization'!
setTitle: aTitle details: aString action: aLabel then: aBlock
	| details buttons |
	answerBlock := aBlock.
	done := false.
	details := ToolTextEditor new name: 'details'; title: 'details'; text: (self class wrap: aString width: 72); yourself.
	details readOnly: true; highlighting: false.
	buttons := Row with: (Array
		with: (Widget new flex: 1)
		with: ((Button label: 'Cancel' action: [self answer: false]) beDefault; sizeToContent; yourself)
		with: ((Button label: aLabel action: [self answer: true]) sizeToContent; yourself)).
	buttons spacing: 6; padding: (12 @ 5 corner: 12 @ 6); fixed: 33.
	self separators: true.
	self addAll: (Array
		with: ((Label text: aTitle font: #uiBold) padding: (12 @ 0 corner: 12 @ 0); fixed: 28; yourself)
		with: details
		with: buttons)
! !

!ConfirmDialog methodsFor: 'actions'!
answer: aBoolean
	done ifTrue: [^self].
	done := true.
	[answerBlock value: aBoolean] ensure: [self window ifNotNil: [:w | w close]]
!
windowClosed
	done ifFalse: [
		done := true.
		answerBlock value: false]
!
minimumWindowExtent
	^360 @ 180
! !

!ConfirmDialog methodsFor: 'events'!
keyDown: anEvent
	anEvent key == #escape ifTrue: [self answer: false. ^true].
	^super keyDown: anEvent
! !
