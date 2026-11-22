Crc32 subclass: #Crc32c
	instanceVariableNames: ''
	classVariableNames: 'CTable'
	package: 'System-Storage'!

Crc32c comment: 'I compute CRC-32C (Castagnoli, reflected polynomial 16r82F63B78) as Crc32 does CRC-32: update:bytes:from:to: is the raw register update, without the initial and final inversion, as ext4''s metadata checksums use it (Ext4Volume: crc32c(16rFFFFFFFF, superblock)); checksumOf: is the standard CRC (RFC 3720: ''123456789'' gives 16rE3069283).'!

!Crc32c class methodsFor: 'private'!
primUpdate: crc bytes: aByteArray from: start count: n
	<primitive: 'cryptoCrc32c'>
	^nil
!
polynomial
	^16r82F63B78
!
table
	^CTable ifNil: [CTable := self makeTable]
! !
