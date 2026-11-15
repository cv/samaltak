ArrayedCollection variableByteSubclass: #ByteArray
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Collections'!

ByteArray comment: 'I am a fixed-size sequence of bytes (SmallIntegers 0..255). I also read and write little-endian 16/32-bit integers and 32/64-bit floats at 1-based byte offsets, and big-endian integers for TrueType data. Bytecodes of CompiledMethods are ByteArrays.'!

!ByteArray methodsFor: 'accessing'!
uint16At: byteOffset
	<primitive: 'bytesUint16At'>
	^(self at: byteOffset) + ((self at: byteOffset + 1) bitShift: 8)
!
int16At: byteOffset
	<primitive: 'bytesInt16At'>
	| v |
	v := self uint16At: byteOffset.
	^v >= 16r8000 ifTrue: [v - 16r10000] ifFalse: [v]
!
uint32At: byteOffset
	<primitive: 'bytesUint32At'>
	^(self uint16At: byteOffset) + ((self uint16At: byteOffset + 2) bitShift: 16)
!
uint32At: byteOffset put: anInteger
	<primitive: 'bytesUint32AtPut'>
	0 to: 3 do: [:i | self at: byteOffset + i put: ((anInteger bitShift: i * -8) bitAnd: 255)].
	^anInteger
!
float32At: byteOffset
	<primitive: 'bytesFloat32At'>
	^self primitiveFailed
!
float32At: byteOffset put: aFloat
	<primitive: 'bytesFloat32AtPut'>
	^self primitiveFailed
!
float64At: byteOffset
	<primitive: 'bytesFloat64At'>
	^self primitiveFailed
!
float64At: byteOffset put: aFloat
	<primitive: 'bytesFloat64AtPut'>
	^self primitiveFailed
!
uint16BigEndianAt: byteOffset
	<primitive: 'bytesUint16BigEndianAt'>
	^((self at: byteOffset) bitShift: 8) + (self at: byteOffset + 1)
!
int16BigEndianAt: byteOffset
	<primitive: 'bytesInt16BigEndianAt'>
	| v |
	v := self uint16BigEndianAt: byteOffset.
	^v >= 16r8000 ifTrue: [v - 16r10000] ifFalse: [v]
!
uint32BigEndianAt: byteOffset
	<primitive: 'bytesUint32BigEndianAt'>
	^((self uint16BigEndianAt: byteOffset) bitShift: 16) + (self uint16BigEndianAt: byteOffset + 2)
!
uint16At: byteOffset put: anInteger
	self at: byteOffset put: (anInteger bitAnd: 255).
	self at: byteOffset + 1 put: ((anInteger bitShift: -8) bitAnd: 255).
	^anInteger
! !

!ByteArray methodsFor: 'converting'!
asString
	"Answer a ByteString with the bytes as Latin-1 characters."
	| s |
	s := ByteString new: self size.
	s replaceFrom: 1 to: self size with: self startingAt: 1.
	^s
!
asByteArray
	^self
!
utf8Decoded
	"Answer the String these UTF-8 bytes encode, a ByteString if all its code points are below 256. Each maximal ill-formed subpart becomes one U+FFFD (see utf8LengthAt:to:); nothing is signaled."
	| stream i n |
	(self allSatisfy: [:b | b < 16r80]) ifTrue: [^self asString].
	stream := WriteStream on: (String new: self size).
	i := 1.
	[i <= self size] whileTrue: [
		(self at: i) < 16r80
			ifTrue: [
				stream nextPut: (Character value: (self at: i)).
				i := i + 1]
			ifFalse: [
				n := self utf8LengthAt: i to: self size.
				stream nextPut: (self utf8CharacterAt: i length: n).
				i := i + n abs]].
	^stream contents
!
utf8LengthAt: start to: stop
	"Answer the length of the well-formed UTF-8 sequence that begins at start and ends by stop, or, negated, that of the maximal ill-formed subpart there (Unicode 3.9, as WHATWG): an overlong form, a surrogate, a code point above 10FFFF, a stray continuation byte or a truncated sequence, each byte up to the one that cannot continue it."
	| b n lo hi k c |
	b := self at: start.
	b < 16r80 ifTrue: [^1].
	b < 16rC2 ifTrue: [^-1].
	b < 16rE0
		ifTrue: [n := 2. lo := 16r80. hi := 16rBF]
		ifFalse: [
			b < 16rF0
				ifTrue: [
					n := 3.
					lo := b = 16rE0 ifTrue: [16rA0] ifFalse: [16r80].
					hi := b = 16rED ifTrue: [16r9F] ifFalse: [16rBF]]
				ifFalse: [
					b > 16rF4 ifTrue: [^-1].
					n := 4.
					lo := b = 16rF0 ifTrue: [16r90] ifFalse: [16r80].
					hi := b = 16rF4 ifTrue: [16r8F] ifFalse: [16rBF]]].
	k := 1.
	[k < n] whileTrue: [
		start + k > stop ifTrue: [^k negated].
		c := self at: start + k.
		(c < lo or: [c > hi]) ifTrue: [^k negated].
		lo := 16r80.
		hi := 16rBF.
		k := k + 1].
	^n
!
utf8CharacterAt: start length: n
	"The Character of the sequence utf8LengthAt:to: measured: U+FFFD for an ill-formed one (n negative)."
	| cp |
	n < 0 ifTrue: [^Character value: 16rFFFD].
	cp := (self at: start) bitAnd: (#(16r7F 16r1F 16r0F 16r07) at: n).
	start + 1 to: start + n - 1 do: [:i | cp := (cp bitShift: 6) + ((self at: i) bitAnd: 16r3F)].
	^Character value: cp
!
hex
	"Answer the bytes as a hexadecimal String."
	^String new: self size * 2 streamContents: [:s |
		self do: [:b |
			s nextPut: (Character digitValue: b // 16); nextPut: (Character digitValue: b \\ 16)]]
! !

!ByteArray methodsFor: 'comparing'!
hash
	| h |
	h := 2166136261.
	self do: [:b | h := ((h bitXor: b) * 16777619) bitAnd: 16rFFFFFFFF].
	^h bitAnd: 16r3FFFFFFF
! !

!ByteArray methodsFor: 'testing'!
isLiteral
	^self class == ByteArray
! !

!ByteArray methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: '#['.
	self do: [:b | aStream print: b] separatedBy: [aStream space].
	aStream nextPut: $]
!
storeOn: aStream
	self printOn: aStream
! !
