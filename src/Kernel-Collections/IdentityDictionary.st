Dictionary subclass: #IdentityDictionary
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Collections'!

IdentityDictionary comment: 'I am a Dictionary that compares keys by identity (==, identityHash).'!

!IdentityDictionary methodsFor: 'private'!
scanFor: key
	| index size element |
	size := array size.
	index := key identityHash \\ size + 1.
	[(element := array at: index) isNil or: [element key == key]]
		whileFalse: [index := index \\ size + 1].
	^index
! !
