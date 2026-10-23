ParseNode subclass: #MessageNode
	instanceVariableNames: 'receiver selector arguments'
	classVariableNames: ''
	package: 'Compiler'!

MessageNode comment: 'I am a message send. In a cascade my receiver is the (shared) receiver node of the CascadeNode.'!

!MessageNode class methodsFor: 'instance creation'!
receiver: aNode selector: aSymbol arguments: anArray start: startInteger stop: stopInteger
	^self new setReceiver: aNode selector: aSymbol arguments: anArray; start: startInteger stop: stopInteger
! !

!MessageNode methodsFor: 'accessing'!
receiver
	^receiver
!
selector
	^selector
!
arguments
	^arguments
!
setReceiver: aNode selector: aSymbol arguments: anArray
	receiver := aNode.
	selector := aSymbol.
	arguments := anArray
! !

!MessageNode methodsFor: 'testing'!
isMessage
	^true
! !

!MessageNode methodsFor: 'code generation'!
emitEffect: aCodeGenerator
	aCodeGenerator emitMessage: self forValue: false
!
emitValue: aCodeGenerator
	aCodeGenerator emitMessage: self forValue: true
! !
