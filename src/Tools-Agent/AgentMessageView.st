AgentItemView subclass: #AgentMessageView
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tools-Agent'!

AgentMessageView comment: 'I show a message of an AgentConversation as wrapped plain text: the user''s (You, a rule above: a new turn), the agent''s (growing while it streams) or an error (in ultramarine).'!

!AgentMessageView methodsFor: 'layout'!
font
	^self theme font: #ui
!
lines
	^self wrap: item text font: self font width: self contentWidth
!
top
	^item kind == #user ifTrue: [9] ifFalse: [3]
!
computeHeightFor: aWidth
	^self top + ((self wrap: item text font: self font width: aWidth - self gutterWidth - self margin) size * self font lineHeight) + 5
! !

!AgentMessageView methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| font y color who |
	font := self font.
	item kind == #user ifTrue: [aCanvas fillRect: (0 @ 0 extent: self width @ 1) color: self theme rule].
	who := Dictionary new at: #user put: #('You' #uiBold #ink); at: #assistant put: #('Agent' #uiItalic #ink3); at: #error put: #('Error' #uiBold #ultramarine); yourself.
	who := who at: item kind.
	aCanvas drawString: who first in: (0 @ self top extent: (self gutterWidth - 12) @ font lineHeight)
		font: (self theme font: (who at: 2)) color: (self theme color: who last) align: #right.
	color := item kind == #error ifTrue: [self theme ultramarine] ifFalse: [self theme ink].
	y := self top.
	self lines do: [:line |
		aCanvas drawString: line at: self gutterWidth @ y font: font color: color.
		y := y + font lineHeight]
! !
