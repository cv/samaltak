TestCase subclass: #NvVfioTest
	instanceVariableNames: 'fake device'
	classVariableNames: ''
	package: 'Tests-NV'!

NvVfioTest comment: 'Tests that the GB10 code written for the firmware''s PciDevice runs unchanged over VfioPciDevice (the hosted loop of docs/nv-gsp.md 6.1 and 13), against VfioFake holding this Spark''s configuration space and the registers of an unbooted GB10B (NvFakePciFunction spark) in its mmap''d BAR0: NvProbe reports the same lines, NvBar0 writes land in the mapping and only those of its write list, NvPciDmaMemory hands out buffers whose device addresses are the IOVAs VFIO maps, and NvGspBoot''s dry run reads the registers, maps all its DMA memory and writes nothing to BAR0. Verified only against the fake: the real kernel''s answers wait for a dedicated Spark.'!

!NvVfioTest methodsFor: 'running'!
setUp
	| bar |
	fake := VfioFake group: 20 device: '000f:01:00.0'.
	fake config: NvFakePciFunction sparkConfigurationSpace.
	fake bar: 0 size: 16r4000000 mappable: true.
	bar := fake barMemory: 0.
	NvFakePciFunction unbootedRegisters keysAndValuesDo: [:offset :value | Machine uint32At: bar + offset put: value].
	device := VfioPciDevice open: '000f:01:00.0' group: 20 os: fake
!
tearDown
	device release.
	fake release
!
register: offset
	^Machine uint32At: (fake barMemory: 0) + offset
! !

!NvVfioTest methodsFor: 'tests'!
testProbeSeesWhatItSeesOnUefi
	self assert: (NvProbe isNvidiaGpu: device).
	self assert: (NvProbe on: device) lines asArray equals: (NvProbe on: NvFakePciFunction spark) lines asArray.
	self assert: (fake calls noneSatisfy: [:c | c first = #write]).
	self assert: (fake trace select: [:l | l beginsWith: 'mmap']) equals: #('mmap bar 0')
!
testBar0OverTheMapping
	| bar |
	bar := NvBar0 on: device.
	self assert: (bar read32: (NvGspBoot register: #pmcBoot42)) equals: 16r1ABA1000.
	bar write32: (NvGspBoot register: #gspQueueHead) value: 0.
	bar write32: (NvGspBoot register: #sec2QueueTail) value: 864.
	self assert: (self register: (NvGspBoot register: #sec2QueueTail)) equals: 864.
	self should: [bar write32: 16r840100 value: 1] raise: Error.
	self assert: (self register: 16r840100) equals: 0
!
testDmaMemoryIsMappedForTheDevice
	| memory b |
	memory := NvPciDmaMemory on: device.
	b := memory allocate: 5000.
	self assert: b size equals: 8192.
	self assert: b deviceAddress equals: 16r100000000.
	self assert: (fake dma first first: 3) equals: {b cpuAddress. 16r100000000. 8192}.
	b u64At: 8 put: 16r1234.
	self assert: (Machine uint64At: b cpuAddress + 8) equals: 16r1234
!
testGspBootDryRunOverVfio
	| firmware bar boot log before |
	firmware := NvGspBootTest firmware.
	before := Machine bytesAt: (fake barMemory: 0) + 16r840000 count: 16r1000.
	bar := NvBar0 on: device dryRun: true.
	boot := NvGspBoot registers: bar memory: (NvPciDmaMemory on: device) firmware: firmware.
	log := boot sysmemHeapSize: 1048576; dryRun.
	self assert: (log first beginsWith: 'prepared').
	self assert: (log anySatisfy: [:l | l includesSubstring: 'GSP held by SEC2']).
	self assert: (log last includesSubstring: 'TAIL 864').
	self assert: bar writes size equals: 220.
	self assert: (Machine bytesAt: (fake barMemory: 0) + 16r840000 count: 16r1000) equals: before.
	self assert: fake dma size equals: boot buffers size.
	boot buffers do: [:b |
		self assert: (fake dma anySatisfy: [:m | (m at: 1) = b cpuAddress and: [(m at: 2) = b deviceAddress and: [(m at: 3) = b size]]])].
	self assert: (boot message u64At: 8 + 4) equals: (boot buffers at: #fmc) deviceAddress.
	self assert: ((boot buffers values collect: [:b | b deviceAddress]) allSatisfy: [:a | a >= 16r100000000 and: [a < (1 bitShift: 40)]])
! !
