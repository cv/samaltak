Object subclass: #Crc32c
	instanceVariableNames: ''
	classVariableNames: 'Table'
	package: 'System-Storage'!

Crc32c comment: 'I compute CRC-32C (Castagnoli, reflected polynomial 16r82F63B78), table-driven, on my class side. update:bytes:from:to: is the raw register update, without the initial and final inversion, as ext4''s metadata checksums use it (Ext4Volume: crc32c(16rFFFFFFFF, superblock)); checksumOf: is the standard CRC (RFC 3720: ''123456789'' gives 16rE3069283).'!

!Crc32c class methodsFor: 'computing'!
update: crc bytes: aByteArray from: start to: stop
	"Answer the CRC register crc after the bytes start..stop of aByteArray, without inversions."
	| c table |
	table := self table.
	c := crc.
	start to: stop do: [:i |
		c := (table at: ((c bitXor: (aByteArray at: i)) bitAnd: 255) + 1) bitXor: (c bitShift: -8)].
	^c
!
checksumOf: aByteArray
	"Answer the standard CRC-32C of aByteArray."
	^(self update: 16rFFFFFFFF bytes: aByteArray from: 1 to: aByteArray size) bitXor: 16rFFFFFFFF
! !

!Crc32c class methodsFor: 'private'!
table
	Table isNil ifTrue: [
		Table := (0 to: 255) collect: [:n | | c |
			c := n.
			8 timesRepeat: [c := (c bitAnd: 1) = 1 ifTrue: [(c bitShift: -1) bitXor: 16r82F63B78] ifFalse: [c bitShift: -1]].
			c]].
	^Table
! !
