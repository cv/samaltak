Object subclass: #ParseNode
	instanceVariableNames: 'start stop'
	classVariableNames: ''
	package: 'Compiler'!

ParseNode comment: 'I am the abstract superclass of the compiler''s syntax tree. start and stop are 1-based inclusive indices into the source.'!

!ParseNode methodsFor: 'accessing'!
start
	^start
!
stop
	^stop
!
start: startInteger stop: stopInteger
	start := startInteger.
	stop := stopInteger
! !

!ParseNode methodsFor: 'testing'!
isAssignment
	^false
!
isBlock
	^false
!
isCascade
	^false
!
isLiteral
	^false
!
isMessage
	^false
!
isReturn
	^false
!
isSelf
	^false
!
isSuper
	^false
!
isVariable
	^false
! !

!ParseNode methodsFor: 'code generation'!
emitEffect: aCodeGenerator
	self emitValue: aCodeGenerator.
	aCodeGenerator encoder pop
!
emitValue: aCodeGenerator
	self subclassResponsibility
! !

!ParseNode methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: self class name; nextPut: $(; print: start; nextPut: $-; print: stop; nextPut: $)
! !
