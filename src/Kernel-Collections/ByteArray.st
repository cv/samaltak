ArrayedCollection variableByteSubclass: #ByteArray
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Collections'!

ByteArray comment: 'I am a fixed-size sequence of bytes (SmallIntegers 0..255). I also read and write little-endian 16/32-bit integers and 32/64-bit floats at 1-based byte offsets, and big-endian integers for TrueType data. Bytecodes of CompiledMethods are ByteArrays.'!

!ByteArray methodsFor: 'comparing'!
compareBytes: aByteArray
	"Answer -1, 0 or 1 comparing my bytes with aByteArray's as unsigned numbers (then the shorter first): 0 if they are equal. A primitive: equal ByteArrays of a page compare in microseconds."
	<primitive: 'stringCompare'>
	| n |
	n := self size min: aByteArray size.
	1 to: n do: [:i | | a b |
		a := self at: i.
		b := aByteArray at: i.
		a = b ifFalse: [^a < b ifTrue: [-1] ifFalse: [1]]].
	^self size < aByteArray size ifTrue: [-1] ifFalse: [self size > aByteArray size ifTrue: [1] ifFalse: [0]]
!
indexOfMismatchAt: start with: anObject at: otherStart size: n
	"The first i in 1 .. n where my byte start + i - 1 differs from anObject's byte otherStart + i - 1, or 0 if none does: two ranges compared in place, 16 bytes at a time (the VM's core_bytes_mismatch; anObject bytes, or a Bitmap's words as the CPU stores them). An error if a range is outside."
	<ffiSite>
	| k |
	k := (self ffiSite: #(call 'vm:core' 'core_bytes_mismatch' (rawBytesWithLength i64 rawBytesWithLength i64 i64) i64))
		tryInvoke5: self with: start with: anObject with: otherStart with: n.
	(k == false or: [k < 0]) ifFalse: [^k].
	^self indexOfMismatchInSmalltalkAt: start with: anObject at: otherStart size: n
!
indexOfMismatchInSmalltalkAt: start with: anObject at: otherStart size: n
	"indexOfMismatchAt:with:at:size: one byte at a time, where the VM's cannot (anObject has pointers; a range is outside: an error)."
	(start >= 1 and: [otherStart >= 1 and: [n >= 0 and: [start + n - 1 <= self size and: [otherStart + n - 1 <= anObject size]]]]) ifFalse: [^self error: 'range outside'].
	1 to: n do: [:i | (self at: start + i - 1) = (anObject at: otherStart + i - 1) ifFalse: [^i]].
	^0
!
lastIndexOfMismatchAt: start with: anObject at: otherStart size: n
	"The last i in 1 .. n where my byte start + i - 1 differs from anObject's byte otherStart + i - 1, or 0 if none does (the VM's core_bytes_last_mismatch; see indexOfMismatchAt:with:at:size:)."
	<ffiSite>
	| k |
	k := (self ffiSite: #(call 'vm:core' 'core_bytes_last_mismatch' (rawBytesWithLength i64 rawBytesWithLength i64 i64) i64))
		tryInvoke5: self with: start with: anObject with: otherStart with: n.
	(k == false or: [k < 0]) ifFalse: [^k].
	^self lastIndexOfMismatchInSmalltalkAt: start with: anObject at: otherStart size: n
!
lastIndexOfMismatchInSmalltalkAt: start with: anObject at: otherStart size: n
	"lastIndexOfMismatchAt:with:at:size: one byte at a time, where the VM's cannot."
	(start >= 1 and: [otherStart >= 1 and: [n >= 0 and: [start + n - 1 <= self size and: [otherStart + n - 1 <= anObject size]]]]) ifFalse: [^self error: 'range outside'].
	n to: 1 by: -1 do: [:i | (self at: start + i - 1) = (anObject at: otherStart + i - 1) ifFalse: [^i]].
	^0
! !

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
!
replaceFrom: start to: stop withRawBytesOf: anObject startingAt: byteIndex
	"My bytes start to stop := the memory of anObject, bytes or words (a Bitmap's as the CPU stores them: little-endian on every CPU the VM runs on), from its byte byteIndex (the VM's core_raw_bytes_replace); answer me, or nil if the VM cannot (an older VM, anObject has pointers, a range is outside)."
	<ffiSite>
	^((self ffiSite: #(call 'vm:core' 'core_raw_bytes_replace' (writableRawBytesWithLength i64 i64 rawBytesWithLength i64) i64))
		tryInvoke5: self with: start with: stop with: anObject with: byteIndex) = 0
			ifTrue: [self]
			ifFalse: [nil]
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
decodeWith: anEncoding
	"Answer the String these bytes encode in anEncoding, named as in Pharo (case and punctuation ignored): #utf8 or 'UTF-8' (utf8Decoded), #latin1 or 'ISO-8859-1'. Other encodings are an error."
	| name |
	name := String encodingNameOf: anEncoding.
	name = 'utf8' ifTrue: [^self utf8Decoded].
	(name = 'latin1' or: [name = 'iso88591']) ifTrue: [^self asString].
	^self error: 'Unknown encoding: ', anEncoding printString
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
