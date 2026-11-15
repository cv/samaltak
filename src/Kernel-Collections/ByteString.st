String variableByteSubclass: #ByteString
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Collections'!

ByteString comment: 'I am a String of code points 0..255, one byte each (Latin-1). Storing a wider Character into me turns me into a WideString (becomeForward:), so references to me see the new characters.'!

!ByteString methodsFor: 'accessing'!
primAt: index failedToPut: aCharacter
	"Widen to a WideString if aCharacter does not fit into a byte."
	(aCharacter isCharacter
		and: [aCharacter value > 255
		and: [self isReadOnlyObject not
		and: [index isInteger and: [index between: 1 and: self size]]]])
			ifTrue: [
				self becomeForward: self asWideString.
				^self at: index put: aCharacter].
	^super primAt: index failedToPut: aCharacter
! !

!ByteString methodsFor: 'testing'!
isByteString
	^true
!
isOctetString
	^true
!
hasWideCharacterFrom: start to: stop
	^false
! !

!ByteString methodsFor: 'converting'!
asByteString
	^self
!
asOctetString
	^self
!
asByteArray
	| bytes |
	bytes := ByteArray new: self size.
	bytes replaceFrom: 1 to: self size with: self startingAt: 1.
	^bytes
! !
