Symbol variableWordSubclass: #WideSymbol
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Collections'!

WideSymbol comment: 'I am a Symbol with at least one character beyond code point 255; 32 bits per character.'!

!WideSymbol methodsFor: 'testing'!
isWideString
	^true
! !
