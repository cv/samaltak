TestCase subclass: #VfioPciDeviceTest
	instanceVariableNames: 'fake device'
	classVariableNames: ''
	package: 'Tests-Devices'!

VfioPciDeviceTest comment: 'Tests VfioPciDevice against VfioFake (Linux''s VFIO without a kernel): the exact ioctl sequence of opening (container, group, IOMMU, device, configuration region) with each structure''s bytes as linux/vfio.h lays it out, configuration space through the configuration region, BARs through their mmap (and through pread and pwrite where the kernel does not let map), DMA memory (anonymous mmap, VFIO_IOMMU_MAP_DMA at IOVAs past the reserved regions, unmapping), reset, release in reverse order, and the refusals with what they say; and, on a Linux host, what the real /dev/vfio/vfio offers, read only (testHostAvailability: no group is opened, nothing is bound). The fake runs everywhere, UEFI included.'!

!VfioPciDeviceTest methodsFor: 'running'!
setUp
	fake := VfioFake group: 20 device: '000f:01:00.0'.
	fake config: self configSpace.
	fake bar: 0 size: 1048576 mappable: true
!
tearDown
	device isNil ifFalse: [device release].
	fake release
!
configSpace
	"10de:2e12, memory decoding on, a 64-bit BAR0 at 16r24000000."
	| c |
	c := ByteArray new: 4096.
	c uint16At: 1 put: 16r10DE; uint16At: 3 put: 16r2E12; uint16At: 5 put: 16r0406; uint32At: 17 put: 16r2400000C; uint32At: 21 put: 0.
	^c
!
open
	device := VfioPciDevice open: '000f:01:00.0' group: 20 os: fake.
	^device
!
u32: bytes at: offset
	^bytes uint32At: offset + 1
!
u64: bytes at: offset
	^(bytes uint32At: offset + 1) + ((bytes uint32At: offset + 5) bitShift: 32)
! !

!VfioPciDeviceTest methodsFor: 'tests'!
testOpenSequence
	| status info region |
	self open.
	self assert: fake trace equals: #('open /dev/vfio/vfio' 'container VFIO_GET_API_VERSION' 'container VFIO_CHECK_EXTENSION' 'open /dev/vfio/20'
		'group VFIO_GROUP_GET_STATUS' 'group VFIO_GROUP_SET_CONTAINER' 'container VFIO_SET_IOMMU' 'group VFIO_GROUP_GET_DEVICE_FD'
		'device VFIO_DEVICE_GET_INFO' 'device VFIO_DEVICE_GET_REGION_INFO').
	self assert: (fake ioctls: 'VFIO_GET_API_VERSION') equals: #(0).
	self assert: (fake ioctls: 'VFIO_CHECK_EXTENSION') equals: #(3).
	self assert: (fake ioctls: 'VFIO_SET_IOMMU') equals: #(3).
	self assert: device iommuType equals: 3.
	self assert: (fake openFds at: (fake ioctls: 'VFIO_GROUP_SET_CONTAINER') first) equals: 'container'.
	self assert: (fake ioctls: 'VFIO_GROUP_GET_DEVICE_FD') equals: #('000f:01:00.0').
	status := (fake ioctls: 'VFIO_GROUP_GET_STATUS') first.
	self assert: status equals: #[8 0 0 0 0 0 0 0].
	info := (fake ioctls: 'VFIO_DEVICE_GET_INFO') first.
	self assert: info size equals: 24.
	self assert: (self u32: info at: 0) equals: 24.
	region := (fake ioctls: 'VFIO_DEVICE_GET_REGION_INFO') first.
	self assert: region size equals: 32.
	self assert: (self u32: region at: 0) equals: 32.
	self assert: (self u32: region at: 8) equals: 7.
	self assert: (region copyFrom: 13 to: 32) equals: (ByteArray new: 20).
	self assert: (device deviceInfo at: 'num_regions') equals: 9.
	self assert: device location equals: '000f:01:00.0'.
	self assert: fake openFds size equals: 3
!
testType1WithoutV2
	fake fault: #noType1v2.
	self open.
	self assert: (fake ioctls: 'VFIO_CHECK_EXTENSION') equals: #(3 1).
	self assert: (fake ioctls: 'VFIO_SET_IOMMU') equals: #(1)
!
testConfigurationSpace
	self open.
	self assert: device vendor equals: 16r10DE.
	self assert: device deviceId equals: 16r2E12.
	self assert: (device barAddress: 0) equals: 16r24000000.
	self assert: (fake calls detect: [:c | c first = #read]) equals: {#read. 7. 0. 2}.
	self assert: device enable.
	self assert: (fake calls select: [:c | c first = #write]) asArray equals: {{#write. 7. 4. 2}}.
	self assert: (fake config uint16At: 5) equals: 16r0406.
	fake config uint16At: 5 put: 0.
	device enable.
	self assert: (fake config uint16At: 5) equals: 6
!
testBarThroughItsMapping
	| bar |
	self open.
	bar := fake barMemory: 0.
	Machine uint32At: bar + 16r100 put: 16r1AB000A1.
	self assert: (device mem32At: 16r100 bar: 0) equals: 16r1AB000A1.
	self assert: (device mem32At: 16r200 bar: 0 put: 16rCAFE).
	self assert: (Machine uint32At: bar + 16r200) equals: 16rCAFE.
	self assert: (device mem32At: 16r200 bar: 0) equals: 16rCAFE.
	self assert: (fake trace select: [:l | l beginsWith: 'mmap']) equals: #('mmap bar 0').
	self assert: (fake calls detect: [:c | c first = #mmap]) last equals: 1048576.
	self assert: (device mem32At: 1048576 bar: 0) isNil.
	self deny: (device mem32At: 1048574 bar: 0 put: 1).
	self assert: (device mem32At: 0 bar: 1) isNil.
	self assert: (device barResource: 0) equals: #(16r24000000 1048576).
	self assert: (device barResource: 1) isNil
!
testBarThroughReadAndWrite
	fake := VfioFake group: 20 device: '000f:01:00.0'.
	fake config: self configSpace; bar: 0 size: 65536 mappable: false.
	self open.
	Machine uint32At: (fake barMemory: 0) + 8 put: 16r12345678.
	self assert: (device mem32At: 8 bar: 0) equals: 16r12345678.
	self assert: (device mem32At: 12 bar: 0 put: 7).
	self assert: (Machine uint32At: (fake barMemory: 0) + 12) equals: 7.
	self assert: (fake trace select: [:l | l beginsWith: 'mmap']) isEmpty.
	self assert: (fake calls select: [:c | c first = #read and: [(c at: 2) = 0]]) asArray equals: {{#read. 0. 8. 4}}
!
testDmaMemory
	| a b map unmap |
	self open.
	a := device allocate: 5000.
	b := device allocate: 4096.
	self assert: (device deviceAddress: a) equals: 16r100000000.
	self assert: (device deviceAddress: a + 4097) equals: 16r100001001.
	self assert: (device deviceAddress: b) equals: 16r100002000.
	Machine uint32At: a + 8188 put: 9.
	self assert: (fake trace select: [:l | l beginsWith: 'mmap']) equals: #('mmap anonymous 8192' 'mmap anonymous 4096').
	map := (fake ioctls: 'VFIO_IOMMU_MAP_DMA') first.
	self assert: map size equals: 32.
	self assert: (self u32: map at: 0) equals: 32.
	self assert: (self u32: map at: 4) equals: 3.
	self assert: (self u64: map at: 8) equals: a.
	self assert: (self u64: map at: 16) equals: 16r100000000.
	self assert: (self u64: map at: 24) equals: 8192.
	self assert: fake dma size equals: 2.
	device free: a.
	unmap := (fake ioctls: 'VFIO_IOMMU_UNMAP_DMA') first.
	self assert: unmap size equals: 24.
	self assert: (self u32: unmap at: 0) equals: 24.
	self assert: (self u32: unmap at: 4) equals: 0.
	self assert: (self u64: unmap at: 8) equals: 16r100000000.
	self assert: (self u64: unmap at: 16) equals: 8192.
	self assert: fake dma size equals: 1.
	self assert: (fake trace copyFrom: fake trace size - 1 to: fake trace size) equals: #('container VFIO_IOMMU_UNMAP_DMA' 'munmap anonymous 8192')
!
testIovasPastReservedRegions
	| a b |
	fake reserved: (VfioPciDevice parseReservedRegions: '0x0000000008000000 0x00000000080fffff msi
0x00000000a1600000 0x00000000b97fffff direct
0x0000000100001000 0x00000001ffffffff direct
').
	self open.
	self assert: device reservedRegions size equals: 3.
	self assert: (device reservedRegions at: 2) equals: #(16rA1600000 16rB97FFFFF 'direct').
	a := device allocate: 4096.
	b := device allocate: 4096.
	self assert: (device deviceAddress: a) equals: 16r100000000.
	self assert: (device deviceAddress: b) equals: 16r200000000.
	device iovaBase: 16rA0000000.
	self assert: (device deviceAddress: (device allocate: 4096)) equals: 16r200001000
!
testReleaseInReverseOrder
	| n |
	self open.
	device allocate: 4096; allocate: 8192.
	device mem32At: 0 bar: 0.
	n := fake trace size.
	device release.
	device := nil.
	self assert: (fake trace allButFirst: n) equals: #('container VFIO_IOMMU_UNMAP_DMA' 'munmap anonymous 8192' 'container VFIO_IOMMU_UNMAP_DMA' 'munmap anonymous 4096'
		'munmap bar 0' 'close device' 'close group' 'close container').
	self assert: ((fake ioctls: 'VFIO_IOMMU_UNMAP_DMA') collect: [:u | self u64: u at: 8]) equals: #(16r100001000 16r100000000).
	self assert: fake openFds isEmpty.
	self assert: fake dma isEmpty
!
testReset
	self open.
	device reset.
	self assert: fake resets equals: 1.
	self assert: (fake ioctls: 'VFIO_DEVICE_RESET') equals: #(0)
!
testRefusals
	"Each refusal says why, and closes what was opened."
	#(#(#notViable 'not viable') #(#setContainer '1:1 IOMMU mapping') #(#noType1 'no Type1') #(#noReset 'has no reset')) do: [:case | | f e |
		f := VfioFake group: 20 device: '000f:01:00.0'.
		f config: self configSpace; fault: case first.
		e := [| d | d := VfioPciDevice open: '000f:01:00.0' group: 20 os: f. d reset. d release. nil] on: Error do: [:x | x return: x messageText].
		self assert: (e notNil and: [e includesSubstring: case last]) description: case first, ': ', e printString.
		case first = #noReset ifFalse: [self assert: f openFds isEmpty description: case first].
		f release].
	self should: [VfioPciDevice open: '000f:01:00.0' group: 21 os: fake] raise: Error.
	self assert: fake openFds isEmpty
!
testHostAvailability
	"Read only: the container's API version and IOMMU types; no group opened, nothing bound."
	| lines |
	lines := VfioPciDevice availability.
	self assert: lines notEmpty.
	(PosixDevice isAvailable and: [File exists: '/dev/vfio/vfio']) ifFalse: [^self assert: (lines first includesSubstring: 'no ')].
	(lines first includesSubstring: 'cannot open') ifTrue: [^self].
	self assert: (lines first includesSubstring: 'API version 0').
	self assert: (lines anySatisfy: [:l | l includesSubstring: 'VFIO_TYPE1v2_IOMMU']).
	self assert: lines last equals: 'vfio: no group opened, no device touched'
!
testAvailabilityOnTheFake
	| lines |
	lines := VfioPciDevice availabilityOn: fake.
	self assert: lines asArray equals: #('vfio: /dev/vfio/vfio API version 0 (VFIO_API_VERSION 0)' 'vfio: VFIO_TYPE1_IOMMU yes' 'vfio: VFIO_TYPE1v2_IOMMU yes' 'vfio: VFIO_NOIOMMU_IOMMU no' 'vfio: no group opened, no device touched').
	self assert: fake trace equals: #('open /dev/vfio/vfio' 'container VFIO_GET_API_VERSION' 'container VFIO_CHECK_EXTENSION' 'container VFIO_CHECK_EXTENSION' 'container VFIO_CHECK_EXTENSION' 'close container')
! !
