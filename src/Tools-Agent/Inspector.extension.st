!Inspector methodsFor: '*Tools-Agent'!
agentContext
	"The inspected object as self, the selected field's value as field."
	^super agentContext
		receiver: object;
		bind: #field to: (fields selection ifNotNil: [:f | self valueOf: f]);
		yourself
! !
