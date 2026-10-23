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
	"Answer the String these UTF-8 bytes encode."
	| stream i b n cp |
	stream := WriteStream on: (String new: self size).
	i := 1.
	[i <= self size] whileTrue: [
		b := self at: i.
		b < 16r80
			ifTrue: [cp := b. n := 0]
			ifFalse: [
				b < 16rE0
					ifTrue: [cp := b bitAnd: 16r1F. n := 1]
					ifFalse: [
						b < 16rF0
							ifTrue: [cp := b bitAnd: 16r0F. n := 2]
							ifFalse: [cp := b bitAnd: 16r07. n := 3]]].
		1 to: n do: [:k |
			i + k <= self size ifTrue: [cp := (cp bitShift: 6) + ((self at: i + k) bitAnd: 16r3F)]].
		stream nextPut: (Character value: cp).
		i := i + n + 1].
	^stream contents
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
