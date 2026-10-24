Object subclass: #SimulatedMemory
	instanceVariableNames: 'segments recent nextAddress objectsByAddress addressesByObject nextObjectAddress cStrings stackBase stackTop stackLimit'
	classVariableNames: ''
	package: 'VM-Lowtalk'!

SimulatedMemory comment: 'I am the address space of a simulated VM: separate segments (what malloc, mmap, static data and locals give the VM), each paged 64-bit words, at addresses that stay SmallIntegers. Accesses outside any segment are simulation errors, so are stores of values that do not fit their type.

Objects that the simulated VM only handles by address (host-side library objects, function pointers, Smalltalk strings used as C string literals) get fake addresses: addressOf: and objectAt:.'!

Error subclass: #SimulationError
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Lowtalk'!

SimulationError comment: 'The simulated VM did something its C translation would not survive: a bad address, a value that does not fit its type.'!

Object subclass: #SimulatedSegment
	instanceVariableNames: 'base limit pages'
	classVariableNames: ''
	package: 'VM-Lowtalk'!

SimulatedSegment comment: 'A mapped range of a SimulatedMemory: 64 KB pages (ByteArrays), allocated when first written (untouched memory reads as zero), so mmap can reserve gigabytes.'!

!SimulatedSegment class methodsFor: 'instance creation'!
base: anAddress size: aSize
	^self new setBase: anAddress size: aSize
! !

!SimulatedSegment methodsFor: 'private'!
setBase: anAddress size: aSize
	base := anAddress.
	limit := anAddress + aSize.
	pages := Array new: aSize + 65535 // 65536
!
pageAt: anOffset
	"The page holding byte offset anOffset, allocated."
	| index page |
	index := anOffset // 65536 + 1.
	page := pages at: index.
	page isNil ifTrue: [page := pages at: index put: (ByteArray new: 65536)].
	^page
! !

!SimulatedSegment methodsFor: 'accessing'!
base
	^base
!
limit
	^limit
!
size
	^limit - base
!
includes: anAddress
	^anAddress >= base and: [anAddress < limit]
!
wordAt: anOffset
	"The 64-bit word at byte offset anOffset (a multiple of 8) from my base."
	| page o |
	page := pages at: anOffset // 65536 + 1.
	page isNil ifTrue: [^0].
	o := anOffset \\ 65536 + 1.
	^(page uint32At: o) + ((page uint32At: o + 4) bitShift: 32)
!
wordAt: anOffset put: anInteger
	| page o |
	page := pages at: anOffset // 65536 + 1.
	(page isNil and: [anInteger = 0]) ifTrue: [^0].
	page := self pageAt: anOffset.
	o := anOffset \\ 65536 + 1.
	page uint32At: o put: (anInteger bitAnd: 16rFFFFFFFF).
	page uint32At: o + 4 put: (anInteger bitShift: -32).
	^anInteger
!
byteAt: anOffset
	| page |
	page := pages at: anOffset // 65536 + 1.
	page isNil ifTrue: [^0].
	^page at: anOffset \\ 65536 + 1
!
byteAt: anOffset put: aByte
	(self pageAt: anOffset) at: anOffset \\ 65536 + 1 put: aByte.
	^aByte
!
bytesAt: anOffset count: n into: aByteArray startingAt: start
	"Copy n bytes from offset anOffset into aByteArray, page by page."
	| o done chunk page |
	o := anOffset.
	done := 0.
	[done < n] whileTrue: [
		chunk := (65536 - (o \\ 65536)) min: n - done.
		page := pages at: o // 65536 + 1.
		page isNil
			ifTrue: [start + done to: start + done + chunk - 1 do: [:i | aByteArray at: i put: 0]]
			ifFalse: [aByteArray replaceFrom: start + done to: start + done + chunk - 1 with: page startingAt: o \\ 65536 + 1].
		o := o + chunk.
		done := done + chunk]
!
bytesAt: anOffset put: aByteArray from: start count: n
	| o done chunk |
	o := anOffset.
	done := 0.
	[done < n] whileTrue: [
		chunk := (65536 - (o \\ 65536)) min: n - done.
		(self pageAt: o) replaceFrom: o \\ 65536 + 1 to: o \\ 65536 + chunk with: aByteArray startingAt: start + done.
		o := o + chunk.
		done := done + chunk]
!
zeroFrom: anOffset size: aSize
	"Discard whole pages in the range (mmap MAP_FIXED over it), zero the rest."
	| o end |
	o := anOffset.
	end := anOffset + aSize min: self size.
	[o < end] whileTrue: [
		((o \\ 65536) = 0 and: [o + 65536 <= end])
			ifTrue: [pages at: o // 65536 + 1 put: nil. o := o + 65536]
			ifFalse: [
				(pages at: o // 65536 + 1) notNil ifTrue: [self byteAt: o put: 0].
				o := o + 1]]
! !

!SimulatedMemory methodsFor: 'initialization'!
initialize
	segments := OrderedCollection new.
	recent := Array new: 64.
	nextAddress := 16r100000.
	objectsByAddress := Dictionary new.
	addressesByObject := IdentityDictionary new.
	nextObjectAddress := 16r7F0000000000.
	cStrings := IdentityDictionary new
! !

!SimulatedMemory methodsFor: 'allocation'!
allocate: aSize
	"Answer the address of aSize zeroed bytes (64 KB aligned, followed by an unmapped gap)."
	| segment |
	segment := SimulatedSegment base: nextAddress size: (aSize max: 1).
	nextAddress := nextAddress + (aSize max: 1) + 16r1FFFF // 16r10000 * 16r10000.
	segments add: segment.
	^segment base
!
zero: anAddress size: aSize
	"Zero a range inside one segment (mmap MAP_FIXED over mapped memory)."
	| s |
	s := self segmentAt: anAddress.
	s zeroFrom: anAddress - s base size: aSize
!
free: anAddress
	"Unmap the segment starting at anAddress (addresses are never reused)."
	anAddress = 0 ifTrue: [^self].
	segments removeAllSuchThat: [:s | s base = anAddress].
	recent := Array new: 64
!
reallocate: anAddress size: aSize
	| new old |
	new := self allocate: aSize.
	anAddress = 0 ifTrue: [^new].
	old := self segmentAt: anAddress.
	self copy: (old size min: aSize) from: anAddress to: new.
	self free: anAddress.
	^new
!
segmentAt: anAddress
	"Binary search (segments are sorted by address), cached per 64 KB of address space (segments never share one)."
	| i lo hi mid s |
	i := (anAddress bitShift: -16) \\ 64 + 1.
	s := recent at: i.
	(s notNil and: [anAddress >= s base and: [anAddress < s limit]]) ifTrue: [^s].
	lo := 1.
	hi := segments size.
	[lo <= hi] whileTrue: [
		mid := lo + hi // 2.
		s := segments at: mid.
		anAddress < s base
			ifTrue: [hi := mid - 1]
			ifFalse: [
				anAddress < s limit ifTrue: [^recent at: i put: s].
				lo := mid + 1]].
	^self simulationError: 'bad address 16r' , (anAddress printStringBase: 16)
!
allocateLocal: aSize
	"Zeroed storage for a local of a simulated function (self local:): a 4 MB ring, so short-lived locals cost no segment."
	| size a |
	size := aSize + 15 // 16 * 16 max: 16.
	stackBase isNil ifTrue: [
		stackBase := stackTop := self allocate: 4 * 1024 * 1024.
		stackLimit := stackBase + (4 * 1024 * 1024)].
	stackTop + size > stackLimit ifTrue: [stackTop := stackBase].
	a := stackTop.
	stackTop := stackTop + size.
	self zero: a size: size.
	^a
!
sizeOfSegmentAt: anAddress
	^(self segmentAt: anAddress) limit - anAddress
! !

!SimulatedMemory methodsFor: 'words'!
uint64At: anAddress
	| s |
	(anAddress bitAnd: 7) = 0 ifFalse: [^self unsignedAt: anAddress size: 8].
	s := self segmentAt: anAddress.
	^s wordAt: anAddress - s base
!
uint64At: anAddress put: anInteger
	| s |
	(anInteger isInteger and: [anInteger >= 0 and: [anInteger <= 16rFFFFFFFFFFFFFFFF]]) ifFalse: [
		^self simulationError: anInteger printString , ' does not fit uint64_t'].
	(anAddress bitAnd: 7) = 0 ifFalse: [^self unsignedAt: anAddress size: 8 put: anInteger].
	s := self segmentAt: anAddress.
	(anAddress + 8 > s limit) ifTrue: [^self simulationError: 'store past the end of a segment'].
	^s wordAt: anAddress - s base put: anInteger
!
unsignedAt: anAddress size: n
	"Answer the n-byte unsigned little-endian integer at anAddress."
	| s offset v |
	s := self segmentAt: anAddress.
	anAddress + n > s limit ifTrue: [^self simulationError: 'load past the end of a segment'].
	offset := anAddress - s base.
	n = 1 ifTrue: [^s byteAt: offset].
	(n = 8 and: [(offset bitAnd: 7) = 0]) ifTrue: [^s wordAt: offset].
	v := 0.
	n - 1 to: 0 by: -1 do: [:i | v := (v bitShift: 8) + (s byteAt: offset + i)].
	^v
!
unsignedAt: anAddress size: n put: anInteger
	| s offset |
	s := self segmentAt: anAddress.
	anAddress + n > s limit ifTrue: [^self simulationError: 'store past the end of a segment'].
	offset := anAddress - s base.
	n = 1 ifTrue: [^s byteAt: offset put: anInteger].
	(n = 8 and: [(offset bitAnd: 7) = 0]) ifTrue: [^s wordAt: offset put: anInteger].
	0 to: n - 1 do: [:i | s byteAt: offset + i put: ((anInteger bitShift: i * -8) bitAnd: 255)].
	^anInteger
! !

!SimulatedMemory methodsFor: 'typed access'!
uint8At: a
	^self unsignedAt: a size: 1
!
uint8At: a put: v
	^self checked: v bits: 8 signed: false do: [self unsignedAt: a size: 1 put: v]
!
uint16At: a
	^self unsignedAt: a size: 2
!
uint16At: a put: v
	^self checked: v bits: 16 signed: false do: [self unsignedAt: a size: 2 put: v]
!
uint32At: a
	^self unsignedAt: a size: 4
!
uint32At: a put: v
	^self checked: v bits: 32 signed: false do: [self unsignedAt: a size: 4 put: v]
!
int8At: a
	^self signed: (self unsignedAt: a size: 1) bits: 8
!
int8At: a put: v
	^self checked: v bits: 8 signed: true do: [self unsignedAt: a size: 1 put: (v bitAnd: 16rFF)]
!
int16At: a
	^self signed: (self unsignedAt: a size: 2) bits: 16
!
int16At: a put: v
	^self checked: v bits: 16 signed: true do: [self unsignedAt: a size: 2 put: (v bitAnd: 16rFFFF)]
!
int32At: a
	^self signed: (self unsignedAt: a size: 4) bits: 32
!
int32At: a put: v
	^self checked: v bits: 32 signed: true do: [self unsignedAt: a size: 4 put: (v bitAnd: 16rFFFFFFFF)]
!
int64At: a
	^self signed: (self uint64At: a) bits: 64
!
int64At: a put: v
	^self checked: v bits: 64 signed: true do: [self uint64At: a put: (v bitAnd: 16rFFFFFFFFFFFFFFFF)]
!
float64At: a
	^Float fromIEEEBits: (self uint64At: a)
!
float64At: a put: aFloat
	^self uint64At: a put: aFloat asFloat asIEEEBits
!
float32At: a
	| b |
	b := ByteArray new: 4.
	b uint32At: 1 put: (self uint32At: a).
	^b float32At: 1
!
float32At: a put: aFloat
	| b |
	b := ByteArray new: 4.
	b float32At: 1 put: aFloat asFloat.
	^self uint32At: a put: (b uint32At: 1)
!
signed: anInteger bits: n
	^anInteger >= (1 bitShift: n - 1) ifTrue: [anInteger - (1 bitShift: n)] ifFalse: [anInteger]
!
checked: v bits: n signed: aBoolean do: aBlock
	| min max |
	min := aBoolean ifTrue: [(1 bitShift: n - 1) negated] ifFalse: [0].
	max := aBoolean ifTrue: [(1 bitShift: n - 1) - 1] ifFalse: [(1 bitShift: n) - 1].
	(v isInteger and: [v >= min and: [v <= max]]) ifFalse: [
		^self simulationError: v printString , ' does not fit ' , (aBoolean ifTrue: ['int'] ifFalse: ['uint']) , n printString , '_t'].
	^aBlock value
! !

!SimulatedMemory methodsFor: 'blocks'!
copy: n from: src to: dst
	"memmove (the bytes are read first, so overlapping ranges work)."
	n = 0 ifTrue: [^self].
	self bytesAt: dst put: (self bytesAt: src count: n)
!
fill: dst with: aByte count: n
	n = 0 ifTrue: [^self].
	self bytesAt: dst put: (ByteArray new: n withAll: aByte)
!
compare: a with: b count: n
	"memcmp"
	| x y |
	0 to: n - 1 do: [:i |
		x := self uint8At: a + i.
		y := self uint8At: b + i.
		x = y ifFalse: [^x - y]].
	^0
! !

!SimulatedMemory methodsFor: 'strings'!
bytesAt: anAddress count: n
	| b s |
	b := ByteArray new: n.
	n = 0 ifTrue: [^b].
	s := self segmentAt: anAddress.
	anAddress + n > s limit ifTrue: [^self simulationError: 'load past the end of a segment'].
	s bytesAt: anAddress - s base count: n into: b startingAt: 1.
	^b
!
bytesAt: anAddress put: aByteArray
	| s |
	aByteArray isEmpty ifTrue: [^aByteArray].
	s := self segmentAt: anAddress.
	anAddress + aByteArray size > s limit ifTrue: [^self simulationError: 'store past the end of a segment'].
	s bytesAt: anAddress - s base put: aByteArray from: 1 count: aByteArray size.
	^aByteArray
!
cStringLengthAt: anAddress
	| n |
	n := 0.
	[(self uint8At: anAddress + n) = 0] whileFalse: [n := n + 1].
	^n
!
stringAt: aPointerOrString
	"Answer the NUL-terminated UTF-8 string at an address (or aPointerOrString itself if it is a String literal)."
	| a |
	aPointerOrString isString ifTrue: [^aPointerOrString].
	a := self addressOf: aPointerOrString.
	^(self bytesAt: a count: (self cStringLengthAt: a)) utf8Decoded
!
newCString: aString
	"Answer the address of a fresh NUL-terminated UTF-8 copy of aString."
	| bytes a |
	bytes := aString utf8Encoded.
	a := self allocate: bytes size + 1.
	self bytesAt: a put: bytes.
	^a
!
cStringFor: aString
	"Answer the address of aString as a C string literal (made once per literal)."
	^cStrings at: aString ifAbsent: [cStrings at: aString put: (self newCString: aString)]
! !

!SimulatedMemory methodsFor: 'pointers'!
pointerTo: aCType at: anAddress
	"Answer a value pointing at anAddress, typed as a pointer to aCType."
	aCType isStruct ifTrue: [^aCType load: self at: anAddress].
	aCType isFunction ifTrue: [^anAddress = 0 ifTrue: [FunctionPointer null] ifFalse: [self objectAt: anAddress]].
	^CPointer memory: self address: anAddress type: aCType
!
addressOf: aValue
	"Answer the address a pointer value stands for."
	aValue isInteger ifTrue: [^aValue].
	aValue isString ifTrue: [^self cStringFor: aValue].
	(aValue respondsTo: #simulatedAddressIn:) ifTrue: [^aValue simulatedAddressIn: self].
	^self registerObject: aValue
!
registerObject: anObject
	"Answer a fake address for an object the VM only handles by pointer."
	^addressesByObject at: anObject ifAbsent: [
		| a |
		a := nextObjectAddress.
		nextObjectAddress := nextObjectAddress + 16.
		objectsByAddress at: a put: anObject.
		addressesByObject at: anObject put: a]
!
objectAt: anAddress
	^objectsByAddress at: anAddress ifAbsent: [self simulationError: 'no object at 16r' , (anAddress printStringBase: 16)]
!
objectAt: anAddress ifAbsent: aBlock
	^objectsByAddress at: anAddress ifAbsent: aBlock
!
forgetObject: anObject
	| a |
	a := addressesByObject removeKey: anObject ifAbsent: [^self].
	objectsByAddress removeKey: a
! !

!SimulatedMemory methodsFor: 'errors'!
simulationError: aString
	^SimulationError signal: aString
! !
