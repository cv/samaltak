Object subclass: #NvMemory
	instanceVariableNames: 'device handle size gpuAddress cpuAddress'
	classVariableNames: ''
	package: 'System-NV'!

NvMemory comment: 'I am memory an NvDevice allocated for the GPU and the CPU both: system memory (NV01_MEMORY_SYSTEM; the GB10 has no other), mapped into the device''s GPU VA space at gpuAddress and into this process at cpuAddress. Offsets are 0-based bytes.

	m := gpu allocate: 4096.
	m uint32At: 0 put: 7; uint32At: 0.             "7"
	m bytesAt: 16 put: #[1 2 3]; bytesAt: 16 count: 3
	m gpuAddress                                     "what a kernel parameter or a QMD names"

The GPU does not cache me (and the CPU maps me as RM maps system memory), so what one side writes the other sees after the GPU''s semaphore release (NvChannel) or the CPU''s barrier. free returns me to RM (the device frees what is left when it closes).'!

!NvMemory methodsFor: 'initialization'!
device: anNvDevice size: n
	device := anNvDevice.
	size := (n + 16rFFF) // 16r1000 * 16r1000.
	handle := device alloc: NvRm classMemorySystem parent: device device
		params: (NvRm memoryParams: size owner: device root type: NvRm typeNotifier alignment: 16r1000).
	[cpuAddress := device mapToCpu: handle size: size file: '/dev/nvidiactl'.
	gpuAddress := device mapToGpu: handle size: size]
		ifCurtailed: [self free]
! !

!NvMemory methodsFor: 'accessing'!
handle
	^handle
!
size
	^size
!
gpuAddress
	^gpuAddress
!
cpuAddress
	^cpuAddress
!
isFreed
	^handle isNil
! !

!NvMemory methodsFor: 'reading and writing'!
check: offset size: n
	(offset >= 0 and: [offset + n <= size]) ifFalse: [^self error: 'offset ', offset printString, ' outside ', size printString, ' bytes'].
	handle isNil ifTrue: [^self error: 'freed GPU memory']
!
uint32At: offset
	self check: offset size: 4.
	^Machine uint32At: cpuAddress + offset
!
uint32At: offset put: anInteger
	self check: offset size: 4.
	^Machine uint32At: cpuAddress + offset put: anInteger
!
uint64At: offset
	self check: offset size: 8.
	^Machine uint64At: cpuAddress + offset
!
uint64At: offset put: anInteger
	self check: offset size: 8.
	^Machine uint64At: cpuAddress + offset put: anInteger
!
bytesAt: offset count: n
	self check: offset size: n.
	^Machine bytesAt: cpuAddress + offset count: n
!
bytesAt: offset put: aByteArray
	self check: offset size: aByteArray size.
	Machine bytesAt: cpuAddress + offset put: aByteArray
!
fill: n bytes: aByteArray from: offset
	"Copy aByteArray (a pattern) over n bytes from offset, repeating it."
	| at |
	self check: offset size: n.
	at := 0.
	[at < n] whileTrue: [| k |
		k := aByteArray size min: n - at.
		Machine copy: k from: aByteArray at: 0 to: cpuAddress + offset + at at: 0.
		at := at + k]
! !

!NvMemory methodsFor: 'freeing'!
free
	"Unmap me and return me to RM. Safe to call twice."
	handle isNil ifTrue: [^self].
	[cpuAddress notNil ifTrue: [PosixDevice munmap: cpuAddress length: size. cpuAddress := nil].
	gpuAddress notNil ifTrue: [device unmapFromGpu: handle address: gpuAddress. gpuAddress := nil].
	device free: handle parent: device device]
		ensure: [handle := nil. device forget: self]
! !
