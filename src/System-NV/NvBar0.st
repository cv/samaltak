Object subclass: #NvBar0
	instanceVariableNames: 'device dryRun writes'
	classVariableNames: ''
	package: 'System-NV'!

NvBar0 comment: 'I am a GPU''s registers (BAR0 of its PCI function, read and written through the firmware''s PCI I/O: PciDevice mem32At:bar: and mem32At:bar:put:) for NvGspBoot, with two guards. Only the registers of the write list may be written (the boot''s own: SEC2''s EMEM channel and queue 0, the GSP''s FALCON_OS and its queue doorbell; docs/nv-gsp.md 2.3); any other write signals an error before it happens. And dryRun: true records the writes (writes, in order) without making them, so a boot can be followed up to the chain of trust without changing anything.'!

!NvBar0 class methodsFor: 'instance creation'!
on: aPciDevice
	^self on: aPciDevice dryRun: false
!
on: aPciDevice dryRun: aBoolean
	^self new setDevice: aPciDevice dryRun: aBoolean
! !

!NvBar0 class methodsFor: 'registers'!
writeList
	"BAR0 offsets the boot writes, by name (NvGspBoot registers)."
	^#(#sec2Ememc #sec2Ememd #sec2QueueTail #sec2QueueHead #gspFalconOs #gspQueueHead) collect: [:each | NvGspBoot register: each]
! !

!NvBar0 methodsFor: 'initialization'!
setDevice: aPciDevice dryRun: aBoolean
	device := aPciDevice.
	dryRun := aBoolean.
	writes := OrderedCollection new
! !

!NvBar0 methodsFor: 'accessing'!
isDryRun
	^dryRun
!
writes
	"offset -> value of each write, in order (made or, in a dry run, not)."
	^writes
!
read32: offset
	^(device mem32At: offset bar: 0) ifNil: [self error: 'BAR0 read at 16r', (offset printString: 16), ' failed']
!
write32: offset value: aValue
	(self class writeList includes: offset) ifFalse: [^self error: 'BAR0 write at 16r', (offset printString: 16), ' refused: not on the boot''s write list'].
	writes add: offset -> aValue.
	dryRun ifTrue: [^aValue].
	(device mem32At: offset bar: 0 put: aValue) ifFalse: [^self error: 'BAR0 write at 16r', (offset printString: 16), ' failed'].
	^aValue
! !
