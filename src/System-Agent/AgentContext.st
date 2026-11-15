Object subclass: #AgentContext
	instanceVariableNames: 'receiver bindings frame label selection'
	classVariableNames: ''
	package: 'System-Agent'!

AgentContext comment: 'I am what the tool that opened an AgentConversation bound, and how its code-mode cells compile against it: receiver (self, default nil), bindings (variables, Symbol -> Association as in a Workspace, so a Workspace passes its own and assignments are shared; variables a cell declares are added to them), optionally frame (a suspended Context: cells run in it, with its receiver as self and its temporaries as variables), label (a window title) and selection (the text the user had selected, or nil).

	AgentContext new receiver: anObject; bindings: aWorkspace bindings; label: ''Workspace''; yourself'!

!AgentContext methodsFor: 'initialization'!
initialize
	bindings := Dictionary new.
	label := 'Agent'
! !

!AgentContext methodsFor: 'accessing'!
receiver
	^frame isNil ifTrue: [receiver] ifFalse: [frame receiver]
!
receiver: anObject
	receiver := anObject
!
bindings
	^bindings
!
bindings: aDictionary
	bindings := aDictionary
!
frame
	^frame
!
frame: aContext
	frame := aContext
!
label
	^label
!
label: aString
	label := aString
!
selection
	^selection
!
selection: aStringOrNil
	selection := aStringOrNil
! !

!AgentContext methodsFor: 'evaluating'!
evaluate: aString bindings: aDictionary
	"Compile and run aString against me with aDictionary's variables (Symbol -> Association) too, mine winning; answer its value. A syntax error signals SyntaxError."
	| all value |
	all := Dictionary new.
	aDictionary keysAndValuesDo: [:name :assoc | all at: name put: assoc].
	bindings keysAndValuesDo: [:name :assoc | all at: name put: assoc].
	value := frame isNil
		ifTrue: [Compiler evaluate: aString for: receiver bindings: all]
		ifFalse: [frame evaluateInFrame: aString bindings: all].
	all keysAndValuesDo: [:name :assoc |
		((aDictionary includesKey: name) or: [bindings includesKey: name]) ifFalse: [bindings at: name put: assoc]].
	^value
! !

!AgentContext methodsFor: 'describing'!
describe
	"A few lines on what is bound, for the model and the user."
	| names |
	^String new: 200 streamContents: [:s |
		frame notNil ifTrue: [
			s nextPutAll: 'Frame: '; print: frame; nextPutAll: ' (cells run in this suspended frame)'; nextPut: Character lf].
		(frame notNil or: [receiver notNil]) ifTrue: [
			s nextPutAll: 'self: '; nextPutAll: (self printStringOf: self receiver); nextPutAll: ' ('; nextPutAll: self receiver class name; nextPut: $); nextPut: Character lf].
		names := bindings keys asSortedCollection asArray.
		frame notNil ifTrue: [names := (frame tempSlots collect: [:slot | slot first]), names].
		names notEmpty ifTrue: [
			s nextPutAll: 'Variables:'.
			names do: [:each | s space; nextPutAll: each].
			s nextPut: Character lf].
		selection notNil ifTrue: [
			s nextPutAll: 'Selected text:'; nextPut: Character lf; nextPutAll: selection; nextPut: Character lf].
		s position = 0 ifTrue: [s nextPutAll: 'Nothing is bound: self is nil.'; nextPut: Character lf]]
!
printStringOf: anObject
	^[anObject printStringLimitedTo: 200] on: Error do: [:e |
		e return: 'a ', anObject class name, ' (printString failed)']
! !
