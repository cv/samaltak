Symbol variableByteSubclass: #ByteSymbol
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Collections'!

ByteSymbol comment: 'I am a Symbol whose characters all fit in a byte.'!

!ByteSymbol methodsFor: 'testing'!
isByteString
	^true
!
isOctetString
	^true
!
hasWideCharacterFrom: start to: stop
	^false
! !
