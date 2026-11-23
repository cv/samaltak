NvDmaMemory subclass: #NvFakeDmaMemory
	instanceVariableNames: 'buffers next'
	classVariableNames: ''
	package: 'Tests-NV'!

NvFakeDmaMemory comment: 'I am DMA memory for tests: zeroed Machine memory, each buffer at a device address of my own from 16r40000000000 (so a test notices a CPU address given where a device address belongs). A fake GPU reads and writes through me by device address (bytesAt:count:, u32At:, u64At:).'!

!NvFakeDmaMemory methodsFor: 'allocating'!
allocate: bytes
	| n cpu b |
	buffers isNil ifTrue: [buffers := OrderedCollection new. next := 16r40000000000].
	n := bytes + 4095 // 4096 * 4096 max: 4096.
	cpu := Machine allocate: n.
	Machine bytesAt: cpu put: (ByteArray new: n).
	b := NvDmaBuffer cpu: cpu device: next size: n.
	next := next + n + 16r100000.
	buffers add: b.
	^b
!
release
	buffers isNil ifTrue: [^self].
	buffers do: [:b | Machine free: b cpuAddress].
	buffers := nil
! !

!NvFakeDmaMemory methodsFor: 'device access'!
cpuAddressOf: aDeviceAddress
	"The CPU address of aDeviceAddress, or an error if no buffer holds it."
	buffers do: [:b | (aDeviceAddress >= b deviceAddress and: [aDeviceAddress < (b deviceAddress + b size)]) ifTrue: [^b cpuAddress + (aDeviceAddress - b deviceAddress)]].
	^self error: 'the GPU reads device address 16r', (aDeviceAddress printString: 16), ', no DMA buffer'
!
bytesAt: aDeviceAddress count: n
	^Machine bytesAt: (self cpuAddressOf: aDeviceAddress) count: n
!
u32At: aDeviceAddress
	^Machine uint32At: (self cpuAddressOf: aDeviceAddress)
!
u64At: aDeviceAddress
	^Machine uint64At: (self cpuAddressOf: aDeviceAddress)
! !
