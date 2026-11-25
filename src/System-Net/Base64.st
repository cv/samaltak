Object subclass: #Base64
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Net'!

Base64 comment: 'I decode Base64 (RFC 4648), in the standard or the URL alphabet, with or without padding, e.g. the parts of a JSON Web Token.

	(Base64 decode: ''aGk'') utf8Decoded   "''hi''"'!

!Base64 class methodsFor: 'decoding'!
decode: aString
	"The bytes aString encodes; padding and white space are skipped. Error if it has another character."
	| out bits count v |
	out := WriteStream on: (ByteArray new: aString size * 3 // 4).
	bits := 0.
	count := 0.
	aString do: [:c |
		v := self valueOf: c.
		v isNil ifFalse: [
			bits := (bits bitShift: 6) bitOr: v.
			count := count + 6.
			count >= 8 ifTrue: [
				count := count - 8.
				out nextPut: ((bits bitShift: count negated) bitAnd: 255).
				bits := bits bitAnd: (1 bitShift: count) - 1]]].
	^out contents
!
valueOf: aCharacter
	"The 6 bits aCharacter encodes, nil for padding and white space."
	| v |
	v := aCharacter value.
	(v between: 65 and: 90) ifTrue: [^v - 65].
	(v between: 97 and: 122) ifTrue: [^v - 71].
	(v between: 48 and: 57) ifTrue: [^v + 4].
	(aCharacter = $+ or: [aCharacter = $-]) ifTrue: [^62].
	(aCharacter = $/ or: [aCharacter = $_]) ifTrue: [^63].
	(aCharacter = $= or: [aCharacter isSeparator]) ifTrue: [^nil].
	^self error: 'not Base64: ', aCharacter printString
! !

!Base64 class methodsFor: 'encoding'!
encode: bytes
	"The Base64 String of bytes, a collection of integers 0-255 such as a ByteArray: standard alphabet (+ and /), padded with = to a multiple of 4 characters, no line breaks."
	| out alphabet bits count |
	alphabet := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'.
	out := WriteStream on: (String new: (bytes size + 2 // 3 * 4)).
	bits := 0.
	count := 0.
	bytes do: [:byte |
		bits := (bits bitShift: 8) bitOr: byte.
		count := count + 8.
		[count >= 6] whileTrue: [
			count := count - 6.
			out nextPut: (alphabet at: ((bits bitShift: count negated) bitAnd: 63) + 1)].
		bits := bits bitAnd: (1 bitShift: count) - 1].
	count > 0 ifTrue: [out nextPut: (alphabet at: (bits bitShift: 6 - count) + 1)].
	[out position \\ 4 ~= 0] whileTrue: [out nextPut: $=].
	^out contents
! !
