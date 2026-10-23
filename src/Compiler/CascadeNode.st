ParseNode subclass: #CascadeNode
	instanceVariableNames: 'receiver messages'
	classVariableNames: ''
	package: 'Compiler'!

CascadeNode comment: 'I am a cascade. Each of my messages is a MessageNode whose receiver is my receiver node (identical).'!

!CascadeNode class methodsFor: 'instance creation'!
receiver: aNode messages: anArray start: startInteger stop: stopInteger
	^self new setReceiver: aNode messages: anArray; start: startInteger stop: stopInteger
! !

!CascadeNode methodsFor: 'accessing'!
receiver
	^receiver
!
messages
	^messages
!
setReceiver: aNode messages: anArray
	receiver := aNode.
	messages := anArray
! !

!CascadeNode methodsFor: 'testing'!
isCascade
	^true
! !

!CascadeNode methodsFor: 'code generation'!
emitEffect: aCodeGenerator
	aCodeGenerator emitCascade: self forValue: false
!
emitValue: aCodeGenerator
	aCodeGenerator emitCascade: self forValue: true
! !
