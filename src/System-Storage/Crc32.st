Object subclass: #Crc32
	instanceVariableNames: ''
	classVariableNames: 'Table'
	package: 'System-Storage'!

Crc32 comment: 'I compute CRC-32 (zlib''s, PNG''s and Ethernet''s: reflected polynomial 16rEDB88320) on my class side; my subclass Crc32c is CRC-32C. update:bytes:from:to: is the raw register update, without the initial and final inversion; checksumOf: (and checksumOf:from:to:) the standard CRC (''123456789'' gives 16rCBF43926). The VM''s primitive does the update (CryptoPrimitives: the CPU''s CRC instructions, else C eight bytes at a time); tableUpdate:bytes:from:to: is the same a byte at a time in Smalltalk, the fallback and the reference.'!

!Crc32 class methodsFor: 'computing'!
update: crc bytes: aByteArray from: start to: stop
	"Answer the CRC register crc after the bytes start..stop of aByteArray, without inversions."
	^(self primUpdate: crc bytes: aByteArray from: start count: stop - start + 1)
		ifNil: [self tableUpdate: crc bytes: aByteArray from: start to: stop]
!
checksumOf: aByteArray
	"Answer the standard CRC of aByteArray."
	^self checksumOf: aByteArray from: 1 to: aByteArray size
!
checksumOf: aByteArray from: start to: stop
	^(self update: 16rFFFFFFFF bytes: aByteArray from: start to: stop) bitXor: 16rFFFFFFFF
!
tableUpdate: crc bytes: aByteArray from: start to: stop
	"update:bytes:from:to: in Smalltalk, a byte at a time."
	| c table |
	table := self table.
	c := crc.
	start to: stop do: [:i |
		c := (table at: ((c bitXor: (aByteArray at: i)) bitAnd: 255) + 1) bitXor: (c bitShift: -8)].
	^c
! !

!Crc32 class methodsFor: 'private'!
primUpdate: crc bytes: aByteArray from: start count: n
	<primitive: 'cryptoCrc32'>
	^nil
!
polynomial
	^16rEDB88320
!
table
	^Table ifNil: [Table := self makeTable]
!
makeTable
	| p |
	p := self polynomial.
	^(0 to: 255) asArray collect: [:n | | c |
		c := n.
		8 timesRepeat: [c := (c bitAnd: 1) = 1 ifTrue: [(c bitShift: -1) bitXor: p] ifFalse: [c bitShift: -1]].
		c]
! !
