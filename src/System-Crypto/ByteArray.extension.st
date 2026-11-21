!ByteArray methodsFor: 'cryptography'!
constantTimeEquals: aByteArray
	"Are the receiver and aByteArray the same bytes? The time taken depends on their sizes only, not on where they differ (comparing MACs and tags)."
	| d |
	self size = aByteArray size ifFalse: [^false].
	d := 0.
	1 to: self size do: [:i | d := d bitOr: ((self at: i) bitXor: (aByteArray at: i))].
	^d = 0
! !

!ByteArray class methodsFor: 'cryptography'!
fromHex: aString
	"The bytes of hexadecimal digits (either case; spaces and line breaks between them are ignored)."
	| digits bytes hi lo |
	digits := aString reject: [:c | c isSeparator].
	digits size odd ifTrue: [^self error: 'odd number of hexadecimal digits'].
	bytes := self new: digits size // 2.
	1 to: bytes size do: [:i |
		hi := (digits at: 2 * i - 1) asUppercase digitValue.
		lo := (digits at: 2 * i) asUppercase digitValue.
		((hi between: 0 and: 15) and: [lo between: 0 and: 15]) ifFalse: [^self error: 'not a hexadecimal digit'].
		bytes at: i put: hi * 16 + lo].
	^bytes
! !
