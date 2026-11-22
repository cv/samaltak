Object subclass: #NvPushBuffer
	instanceVariableNames: 'words'
	classVariableNames: ''
	package: 'System-NV'!

NvPushBuffer comment: 'I build a pushbuffer: the 32-bit words a GPU channel fetches, methods (register writes) of the classes bound to its subchannels. A method header (header:count:subchannel:method:) says how many data words follow and where they go; incrementing methods write consecutive registers. Subchannel 0 is the channel''s own class (semaphores, NvChannel), 1 the compute class (NvCompute).

	(NvPushBuffer new) method: 16r5C subchannel: 0 data: #(1 2 3 4 5); words

bytes are my words little-endian, to copy into GPU-visible memory; the class side encodes GPFIFO entries, which point a channel at a pushbuffer.'!

!NvPushBuffer methodsFor: 'initialization'!
initialize
	words := OrderedCollection new
! !

!NvPushBuffer methodsFor: 'building'!
method: method subchannel: subchannel data: values
	"An incrementing method: values to the registers from method on (byte offsets in the class)."
	words add: (self class header: 2 count: values size subchannel: subchannel method: method).
	values do: [:v | words add: (v bitAnd: 16rFFFFFFFF)]
!
method: method subchannel: subchannel value: anInteger
	self method: method subchannel: subchannel data: (Array with: anInteger)
!
method: method subchannel: subchannel address: gpuAddress
	"Two incrementing registers that take a 64-bit address high word first (the _A/_B method pairs)."
	self method: method subchannel: subchannel data: (Array with: (gpuAddress bitShift: -32) with: (gpuAddress bitAnd: 16rFFFFFFFF))
!
semaphoreRelease: gpuAddress payload: value
	"The channel writes value (64 bits) to gpuAddress once the work before it is done (host methods SEM_ADDR_LO..
	SEM_EXECUTE: release, wait for idle, 64-bit payload), then raises a non-stall interrupt."
	self method: 16r5C subchannel: 0 data: (Array
		with: (gpuAddress bitAnd: 16rFFFFFFFF) with: (gpuAddress bitShift: -32)
		with: (value bitAnd: 16rFFFFFFFF) with: (value bitShift: -32)
		with: ((1 bitOr: (1 bitShift: 20)) bitOr: (1 bitShift: 24))).
	self method: 16r20 subchannel: 0 value: 0
!
semaphoreAcquire: gpuAddress atLeast: value
	"The channel waits until the 64-bit value at gpuAddress is at least value (circular compare)."
	self method: 16r5C subchannel: 0 data: (Array
		with: (gpuAddress bitAnd: 16rFFFFFFFF) with: (gpuAddress bitShift: -32)
		with: (value bitAnd: 16rFFFFFFFF) with: (value bitShift: -32)
		with: (3 bitOr: (1 bitShift: 24)))
!
reset
	words := OrderedCollection new
! !

!NvPushBuffer methodsFor: 'accessing'!
words
	^words asArray
!
size
	"In words."
	^words size
!
isEmpty
	^words isEmpty
!
bytes
	| b |
	b := ByteArray new: words size * 4.
	words doWithIndex: [:w :i | b uint32At: i * 4 - 3 put: w].
	^b
! !

!NvPushBuffer class methodsFor: 'encoding'!
header: type count: count subchannel: subchannel method: method
	"A method header: type 2 increments the register per data word, 1 (non-incrementing) and 4 (immediate) too exist."
	^(((type bitShift: 28) bitOr: (count bitShift: 16)) bitOr: (subchannel bitShift: 13)) bitOr: (method bitShift: -2)
!
gpfifoEntry: gpuAddress words: count
	"The 64-bit GPFIFO entry for a pushbuffer of count words at gpuAddress (4-byte aligned)."
	^(gpuAddress bitOr: (count bitShift: 42)) bitOr: (1 bitShift: 41)
! !
