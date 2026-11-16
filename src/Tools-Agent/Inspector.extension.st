!Inspector methodsFor: '*Tools-Agent'!
agentContext
	"The selected field is the receiver when the fields list has focus."
	| field |
	field := fields selection.
	^super agentContext
		receiver: ((field notNil and: [self window keyboardFocus == fields])
			ifTrue: [self valueOf: field]
			ifFalse: [object]);
		bind: #field to: (field ifNotNil: [self valueOf: field]);
		yourself
! !
