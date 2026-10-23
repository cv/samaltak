String variableWordSubclass: #WideString
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Collections'!

WideString comment: 'I am a String that can hold any Unicode code point, 32 bits per Character.'!

!WideString methodsFor: 'testing'!
isWideString
	^true
! !

!WideString methodsFor: 'converting'!
asWideString
	^self
! !
