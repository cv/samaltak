PciDevice subclass: #VfioPciDevice
	instanceVariableNames: 'os name groupNumber container group device deviceInfo regionInfos bars iommuType iovaBase nextIova reserved'
	classVariableNames: ''
	package: 'System-Devices'!

VfioPciDevice comment: 'I am a PCI function of a Linux host that the kernel gives to user space through VFIO (Documentation/driver-api/vfio.rst; the function bound to vfio-pci), as a PciDevice: the same reading and driving protocol the firmware''s PCI I/O gives on UEFI, so a driver written for it (NvProbe, NvBar0, NvPciDmaMemory and NvGspBoot) runs over me unchanged, hosted, with the Debugger.

	VfioPciDevice open: ''000f:01:00.0''		"the group from sysfs"
	VfioPciDevice open: ''000f:01:00.0'' group: 20

open: makes a container (/dev/vfio/vfio: VFIO_GET_API_VERSION, VFIO_CHECK_EXTENSION for the Type1 IOMMU, v2 preferred), opens the group (/dev/vfio/<group>: VFIO_GROUP_GET_STATUS must say viable), puts it in the container (VFIO_GROUP_SET_CONTAINER), sets the IOMMU (VFIO_SET_IOMMU), takes the device''s descriptor (VFIO_GROUP_GET_DEVICE_FD) and its info (VFIO_DEVICE_GET_INFO) and the configuration region''s (VFIO_DEVICE_GET_REGION_INFO). Then:
- configuration space: config:width: and config:width:put: read and write the configuration region (pread and pwrite of the device at its offset; the kernel virtualizes some of it, as the firmware does);
- BARs: a memory BAR is mmap''d (shared) at its region''s offset the first time a register is touched; mem32At:bar: and mem32At:bar:put: are loads and stores there (a barrier before each store, so that memory the CPU wrote before a doorbell reaches the device first); a BAR the kernel does not let map goes through pread and pwrite instead; barResource: is {its address in configuration space. the region''s size};
- DMA memory: allocate: maps anonymous memory of the process (mmap, zeroed) and gives it to the IOMMU at an I/O virtual address I choose (VFIO_IOMMU_MAP_DMA, read and write), from iovaBase (4 GB) up, past the group''s reserved regions (sysfs reserved_regions: the MSI window, RMR ranges); deviceAddress: is that address, the one the device must be given; free: and release unmap it (VFIO_IOMMU_UNMAP_DMA);
- reset: VFIO_DEVICE_RESET (an FLR here), only when asked;
- release: every DMA mapping, BAR mapping and descriptor, in reverse order.
No interrupts: drivers poll. Nothing here binds or unbinds a kernel driver: the function must already be vfio-pci''s (tools/nv-vfio.sh bind; docs/nv-dayone.md).

os is what makes the calls: PosixDevice (its class side), or a fake VFIO in tests (VfioFake), which answers the same protocol and records every call. structs and constants are the kernel''s layouts and numbers from linux/vfio.h; VfioLayoutTest checks them against the C compiler (tools/vfio-layouts.sh). availability answers what the host offers (the container''s API version and IOMMU types) without opening any group.'!

!VfioPciDevice class methodsFor: 'layouts'!
structs
	"{C name. sizeof. {{field. offset. size}...}} of the VFIO structures I pass (linux/vfio.h)."
	^#(
		#('vfio_group_status' 8 #(#('argsz' 0 4) #('flags' 4 4)))
		#('vfio_device_info' 24 #(#('argsz' 0 4) #('flags' 4 4) #('num_regions' 8 4) #('num_irqs' 12 4) #('cap_offset' 16 4) #('pad' 20 4)))
		#('vfio_region_info' 32 #(#('argsz' 0 4) #('flags' 4 4) #('index' 8 4) #('cap_offset' 12 4) #('size' 16 8) #('offset' 24 8)))
		#('vfio_iommu_type1_info' 24 #(#('argsz' 0 4) #('flags' 4 4) #('iova_pgsizes' 8 8) #('cap_offset' 16 4) #('pad' 20 4)))
		#('vfio_iommu_type1_dma_map' 32 #(#('argsz' 0 4) #('flags' 4 4) #('vaddr' 8 8) #('iova' 16 8) #('size' 24 8)))
		#('vfio_iommu_type1_dma_unmap' 24 #(#('argsz' 0 4) #('flags' 4 4) #('iova' 8 8) #('size' 16 8)))
	)
!
struct: aName
	^self structs detect: [:each | each first = aName] ifNone: [self error: 'no VFIO structure ', aName]
!
constants
	"The linux/vfio.h numbers I use. The ioctls are _IO(VFIO_TYPE '';'', VFIO_BASE 100 + n): 16r3B00 + 100 + n, no size or direction bits (the structures carry their size in argsz)."
	| d |
	d := Dictionary new.
	#(#('VFIO_GET_API_VERSION' 0) #('VFIO_CHECK_EXTENSION' 1) #('VFIO_SET_IOMMU' 2) #('VFIO_GROUP_GET_STATUS' 3) #('VFIO_GROUP_SET_CONTAINER' 4)
		#('VFIO_GROUP_UNSET_CONTAINER' 5) #('VFIO_GROUP_GET_DEVICE_FD' 6) #('VFIO_DEVICE_GET_INFO' 7) #('VFIO_DEVICE_GET_REGION_INFO' 8)
		#('VFIO_DEVICE_RESET' 11) #('VFIO_IOMMU_GET_INFO' 12) #('VFIO_IOMMU_MAP_DMA' 13) #('VFIO_IOMMU_UNMAP_DMA' 14))
		do: [:each | d at: each first put: 16r3B00 + 100 + each last].
	#(#('VFIO_API_VERSION' 0) #('VFIO_TYPE1_IOMMU' 1) #('VFIO_TYPE1v2_IOMMU' 3) #('VFIO_NOIOMMU_IOMMU' 8)
		#('VFIO_GROUP_FLAGS_VIABLE' 1) #('VFIO_GROUP_FLAGS_CONTAINER_SET' 2) #('VFIO_DEVICE_FLAGS_RESET' 1) #('VFIO_DEVICE_FLAGS_PCI' 2)
		#('VFIO_REGION_INFO_FLAG_READ' 1) #('VFIO_REGION_INFO_FLAG_WRITE' 2) #('VFIO_REGION_INFO_FLAG_MMAP' 4) #('VFIO_REGION_INFO_FLAG_CAPS' 8)
		#('VFIO_DMA_MAP_FLAG_READ' 1) #('VFIO_DMA_MAP_FLAG_WRITE' 2)
		#('VFIO_PCI_BAR0_REGION_INDEX' 0) #('VFIO_PCI_ROM_REGION_INDEX' 6) #('VFIO_PCI_CONFIG_REGION_INDEX' 7) #('VFIO_PCI_NUM_REGIONS' 9))
		do: [:each | d at: each first put: each last].
	^d
!
constant: aName
	^self constants at: aName
!
requestName: aNumber
	"The VFIO ioctl named by request aNumber, or nil."
	self constants keysAndValuesDo: [:k :v | ((k beginsWith: 'VFIO_') and: [v = aNumber and: [v >= 16r3B64]]) ifTrue: [^k]].
	^nil
! !

!VfioPciDevice class methodsFor: 'instance creation'!
open: aLocation
	"The function at aLocation (segment:bus:device.function, lspci -D), in the IOMMU group sysfs puts it in."
	^self open: aLocation group: (self groupOf: aLocation)
!
open: aLocation group: anInteger
	^self open: aLocation group: anInteger os: PosixDevice
!
open: aLocation group: anInteger os: anOs
	^self new setOs: anOs name: aLocation group: anInteger; open; yourself
! !

!VfioPciDevice class methodsFor: 'host'!
groupOf: aLocation
	"The IOMMU group of aLocation: the /sys/kernel/iommu_groups/<n> whose devices include it (sysfs; read only)."
	(Directory entries: '/sys/kernel/iommu_groups') do: [:n |
		(File exists: '/sys/kernel/iommu_groups/', n, '/devices/', aLocation) ifTrue: [^n asNumber]].
	^self error: aLocation, ' is in no IOMMU group (no IOMMU, or no such function)'
!
reservedRegionsOf: aGroup
	"{start. end. type} of each reserved region of IOMMU group aGroup (sysfs, read only), or none if it cannot be read."
	| path |
	path := '/sys/kernel/iommu_groups/', aGroup printString, '/reserved_regions'.
	(File exists: path) ifFalse: [^#()].
	^self parseReservedRegions: (File readBytes: path) asString
!
parseReservedRegions: aString
	"sysfs reserved_regions lines: start end type (0x-prefixed hex)."
	^((aString lines reject: [:l | l trimBoth isEmpty]) collect: [:l | | parts |
		parts := l substrings.
		{Integer readFrom: (parts first allButFirst: 2) asUppercase base: 16. Integer readFrom: ((parts at: 2) allButFirst: 2) asUppercase base: 16. parts at: 3}]) asArray
!
availability
	^self availabilityOn: PosixDevice
!
availabilityOn: anOs
	"What the host''s VFIO offers, read only: opens the container device (/dev/vfio/vfio) alone, asks its API version and which IOMMU types it has, and closes it; opens no group and touches no device. Lines of text."
	| lines fd |
	lines := OrderedCollection new.
	anOs isAvailable ifFalse: [^lines add: 'vfio: no operating system devices (not hosted)'; yourself].
	(anOs == PosixDevice and: [(File exists: '/dev/vfio/vfio') not]) ifTrue: [^lines add: 'vfio: no /dev/vfio/vfio (vfio or iommufd not loaded)'; yourself].
	fd := [anOs open: '/dev/vfio/vfio' flags: (anOs O_RDWR bitOr: anOs O_CLOEXEC)] on: OSError do: [:e | ^lines add: 'vfio: cannot open /dev/vfio/vfio: ', e messageText; yourself].
	[lines add: 'vfio: /dev/vfio/vfio API version ', (anOs ioctl: fd request: (self constant: 'VFIO_GET_API_VERSION') argument: 0) printString,
		' (VFIO_API_VERSION ', (self constant: 'VFIO_API_VERSION') printString, ')'.
	#('VFIO_TYPE1_IOMMU' 'VFIO_TYPE1v2_IOMMU' 'VFIO_NOIOMMU_IOMMU') do: [:ext |
		lines add: 'vfio: ', ext, ' ', ((anOs ioctl: fd request: (self constant: 'VFIO_CHECK_EXTENSION') argument: (self constant: ext)) > 0 ifTrue: ['yes'] ifFalse: ['no'])].
	lines add: 'vfio: no group opened, no device touched']
		ensure: [anOs close: fd].
	^lines
! !

!VfioPciDevice methodsFor: 'initialization'!
setOs: anOs name: aLocation group: anInteger
	os := anOs.
	name := aLocation.
	groupNumber := anInteger.
	scratch := Machine allocate: 64.
	regions := OrderedCollection new.
	regionInfos := Dictionary new.
	bars := Dictionary new.
	iovaBase := 16r100000000.
	nextIova := iovaBase.
	reserved := #()
! !

!VfioPciDevice methodsFor: 'opening'!
open
	"Container, group, IOMMU and device, in the order of Documentation/driver-api/vfio.rst''s example; whatever was opened is closed again if a step fails."
	[self openContainer; openGroup; openDevice] ifCurtailed: [self release]
!
openContainer
	| version |
	container := self call: 'open /dev/vfio/vfio' do: [os open: '/dev/vfio/vfio' flags: (os O_RDWR bitOr: os O_CLOEXEC)].
	version := self ioctl: container request: 'VFIO_GET_API_VERSION' argument: 0.
	version = (self class constant: 'VFIO_API_VERSION') ifFalse: [^self error: 'VFIO API version ', version printString, ', not ', (self class constant: 'VFIO_API_VERSION') printString].
	iommuType := #('VFIO_TYPE1v2_IOMMU' 'VFIO_TYPE1_IOMMU')
		detect: [:t | (self ioctl: container request: 'VFIO_CHECK_EXTENSION' argument: (self class constant: t)) > 0]
		ifNone: [^self error: 'VFIO: the container offers no Type1 IOMMU'].
	iommuType := self class constant: iommuType
!
openGroup
	| status fd |
	group := self call: 'open /dev/vfio/', groupNumber printString do: [os open: '/dev/vfio/', groupNumber printString flags: (os O_RDWR bitOr: os O_CLOEXEC)].
	status := self ioctl: group request: 'VFIO_GROUP_GET_STATUS' struct: 'vfio_group_status' with: #().
	((status at: 'flags') bitAnd: (self class constant: 'VFIO_GROUP_FLAGS_VIABLE')) = 0 ifTrue: [
		^self error: 'VFIO group ', groupNumber printString, ' is not viable: every function in it must be bound to vfio-pci or to no driver'].
	fd := Machine allocate: 8.
	[Machine uint32At: fd put: container.
	 self ioctl: group request: 'VFIO_GROUP_SET_CONTAINER' argument: fd]
		ensure: [Machine free: fd].
	self ioctl: container request: 'VFIO_SET_IOMMU' argument: iommuType.
	reserved := (os respondsTo: #reservedRegionsOf:)
		ifTrue: [os reservedRegionsOf: groupNumber]
		ifFalse: [[self class reservedRegionsOf: groupNumber] on: Error do: [:e | e return: #()]]
!
openDevice
	| s |
	s := Machine allocate: name size + 1.
	[Machine bytesAt: s put: name asByteArray, #[0].
	 device := self ioctl: group request: 'VFIO_GROUP_GET_DEVICE_FD' argument: s]
		ensure: [Machine free: s].
	deviceInfo := self ioctl: device request: 'VFIO_DEVICE_GET_INFO' struct: 'vfio_device_info' with: #().
	((deviceInfo at: 'flags') bitAnd: (self class constant: 'VFIO_DEVICE_FLAGS_PCI')) = 0 ifTrue: [^self error: 'VFIO: ', name, ' is not a PCI device'].
	(deviceInfo at: 'num_regions') > (self class constant: 'VFIO_PCI_CONFIG_REGION_INDEX') ifFalse: [^self error: 'VFIO: ', name, ' has no configuration region'].
	self regionInfo: (self class constant: 'VFIO_PCI_CONFIG_REGION_INDEX')
! !

!VfioPciDevice methodsFor: 'calls'!
call: what do: aBlock
	"aBlock''s result; an OSError becomes an error that says what failed (and, for the known cases, why)."
	^aBlock on: OSError do: [:e | self error: 'VFIO ', what, ' of ', name, ': ', e messageText, (self hint: what errno: e errno)]
!
hint: what errno: anInteger
	(what = 'VFIO_GROUP_SET_CONTAINER' and: [anInteger = OSError EINVAL]) ifTrue: [
		^' (the kernel refuses to give the group''s DMA to user space; for a device with firmware-reserved direct (RMR) ranges it logs "Firmware has requested this device have a 1:1 IOMMU mapping": docs/nv-gsp.md 13)'].
	((what beginsWith: 'open /dev/vfio/') and: [anInteger = OSError EACCES]) ifTrue: [^' (the group''s device belongs to root: chown it, or run as root)'].
	((what beginsWith: 'open /dev/vfio/') and: [anInteger = OSError ENOENT]) ifTrue: [^' (no such group: is the function bound to vfio-pci?)'].
	^''
!
ioctl: fd request: aName argument: anInteger
	^self call: aName do: [os ioctl: fd request: (self class constant: aName) argument: anInteger]
!
ioctl: fd request: aName struct: aStruct with: pairs
	"Call request aName with the structure aStruct (argsz set, the fields of pairs, {name. value}, the rest zero) and answer all its fields after the call, name -> value."
	| decl a result |
	decl := self class struct: aStruct.
	a := Machine allocate: (decl at: 2).
	[Machine bytesAt: a put: (ByteArray new: (decl at: 2)).
	 Machine uint32At: a put: (decl at: 2).
	 pairs do: [:p | | f |
		f := (decl at: 3) detect: [:each | each first = p first].
		Machine write: a + (f at: 2) size: (f at: 3) value: p last].
	 self call: aName do: [os ioctl: fd request: (self class constant: aName) argument: a].
	 result := Dictionary new.
	 (decl at: 3) do: [:f | result at: f first put: (Machine read: a + (f at: 2) size: (f at: 3))]]
		ensure: [Machine free: a].
	^result
! !

!VfioPciDevice methodsFor: 'accessing'!
location
	^name
!
group
	^groupNumber
!
iommuType
	^iommuType
!
deviceInfo
	"name -> value of vfio_device_info"
	^deviceInfo
!
regionInfo: index
	"name -> value of the region''s vfio_region_info (flags, size, offset), asked once."
	^regionInfos at: index ifAbsentPut: [self ioctl: device request: 'VFIO_DEVICE_GET_REGION_INFO' struct: 'vfio_region_info' with: {{'index'. index}}]
!
dmaMappings
	"{cpu address. pages. IOVA. nil} of each DMA buffer, as PciDevice keeps them."
	^regions
!
iovaBase: anInteger
	"Where DMA buffers'' I/O virtual addresses start (4 GB by default)."
	iovaBase := anInteger.
	nextIova := anInteger max: nextIova
!
reservedRegions
	^reserved
!
reservedRegions: anArray
	"{start. end. type} ranges no IOVA may overlap (open: reads the group''s from sysfs)."
	reserved := anArray
! !

!VfioPciDevice methodsFor: 'configuration'!
config: offset width: w
	| info |
	info := self regionInfo: (self class constant: 'VFIO_PCI_CONFIG_REGION_INDEX').
	Machine uint32At: scratch put: 0.
	(self call: 'configuration read' do: [os read: device at: (info at: 'offset') + offset into: scratch count: w]) = w
		ifFalse: [^self error: 'VFIO: short configuration read at 16r', (offset printString: 16)].
	^Machine read: scratch size: w
!
config: offset width: w put: v
	| info |
	info := self regionInfo: (self class constant: 'VFIO_PCI_CONFIG_REGION_INDEX').
	Machine write: scratch size: w value: v.
	(self call: 'configuration write' do: [os write: device at: (info at: 'offset') + offset from: scratch count: w]) = w
		ifFalse: [^self error: 'VFIO: short configuration write at 16r', (offset printString: 16)]
!
barResource: index
	"{address. length}: where configuration space puts BAR index and the size of its region, or nil."
	| info |
	index > 5 ifTrue: [^nil].
	info := self regionInfo: index.
	(info at: 'size') = 0 ifTrue: [^nil].
	^Array with: (self barAddress: index) with: (info at: 'size')
! !

!VfioPciDevice methodsFor: 'registers'!
bar: index
	"{CPU address of the mapping or nil (no mmap: pread/pwrite). size. region offset} of BAR index, mapped the first time, or nil if it has no region."
	^bars at: index ifAbsent: [| info m |
		info := self regionInfo: index.
		(info at: 'size') = 0 ifTrue: [^nil].
		m := ((info at: 'flags') bitAnd: (self class constant: 'VFIO_REGION_INFO_FLAG_MMAP')) = 0
			ifFalse: [self call: 'mmap of BAR ', index printString do: [
				os mmap: (info at: 'size') protection: (os PROT_READ bitOr: os PROT_WRITE) flags: os MAP_SHARED fd: device offset: (info at: 'offset')]].
		bars at: index put: (Array with: m with: (info at: 'size') with: (info at: 'offset'))]
!
mem32At: offset bar: index
	| b |
	b := self bar: index.
	(b isNil or: [offset < 0 or: [offset + 4 > (b at: 2)]]) ifTrue: [^nil].
	(b at: 1) isNil ifFalse: [^Machine uint32At: (b at: 1) + offset].
	(self call: 'BAR read' do: [os read: device at: (b at: 3) + offset into: scratch count: 4]) = 4 ifFalse: [^nil].
	^Machine uint32At: scratch
!
mem32At: offset bar: index put: aValue
	| b |
	b := self bar: index.
	(b isNil or: [offset < 0 or: [offset + 4 > (b at: 2)]]) ifTrue: [^false].
	Machine barrier.
	(b at: 1) isNil ifFalse: [Machine uint32At: (b at: 1) + offset put: aValue. ^true].
	Machine uint32At: scratch put: aValue.
	^(self call: 'BAR write' do: [os write: device at: (b at: 3) + offset from: scratch count: 4]) = 4
! !

!VfioPciDevice methodsFor: 'driving'!
disconnect
	"The kernel gave the function to VFIO already (vfio-pci is bound): nothing to take it from."
	^true
!
enable
	"Decode memory, master the bus (the command register, through the configuration region). Answer whether it could."
	self config: 4 width: 2 put: ((self config: 4 width: 2) bitOr: 16r6).
	^((self config: 4 width: 2) bitAnd: 16r6) = 16r6
!
reset
	"Reset the function (VFIO_DEVICE_RESET: FLR, or what the kernel has for it). Only when asked: never on my own."
	((deviceInfo at: 'flags') bitAnd: (self class constant: 'VFIO_DEVICE_FLAGS_RESET')) = 0 ifTrue: [^self error: 'VFIO: ', name, ' has no reset'].
	self ioctl: device request: 'VFIO_DEVICE_RESET' argument: 0
!
allocate: bytes
	"The CPU''s address of zeroed DMA memory of bytes (whole pages): anonymous memory of the process, mapped for the device at an IOVA of mine (deviceAddress:)."
	| n host iova |
	n := bytes + 4095 // 4096 * 4096 max: 4096.
	host := self call: 'mmap of DMA memory' do: [os mmap: n protection: (os PROT_READ bitOr: os PROT_WRITE) flags: (os MAP_PRIVATE bitOr: os MAP_ANONYMOUS) fd: -1 offset: 0].
	iova := self iovaFor: n.
	[self ioctl: container request: 'VFIO_IOMMU_MAP_DMA' struct: 'vfio_iommu_type1_dma_map' with: {
		{'flags'. (self class constant: 'VFIO_DMA_MAP_FLAG_READ') bitOr: (self class constant: 'VFIO_DMA_MAP_FLAG_WRITE')}. {'vaddr'. host}. {'iova'. iova}. {'size'. n}}]
		ifCurtailed: [os munmap: host length: n].
	nextIova := iova + n.
	regions add: (Array with: host with: n // 4096 with: iova with: nil).
	^host
!
iovaFor: n
	"The next free IOVA for n bytes at or above nextIova, aligned to 4 KB, overlapping no reserved region, below 2^40 (the GPU''s SMMU output and its DMA limit)."
	| a clash |
	a := nextIova + 4095 // 4096 * 4096.
	[clash := reserved detect: [:r | a <= (r at: 2) and: [a + n - 1 >= (r at: 1)]] ifNone: [nil].
	 clash notNil] whileTrue: [a := (clash at: 2) + 1 + 4095 // 4096 * 4096].
	a + n > (1 bitShift: 40) ifTrue: [^self error: 'VFIO: no IOVA below 2^40 for ', n printString, ' bytes'].
	^a
!
free: aHostAddress
	"Give back one buffer of allocate:''s."
	| r |
	r := regions detect: [:each | (each at: 1) = aHostAddress] ifNone: [^self error: 'VFIO: no DMA buffer at 16r', (aHostAddress printString: 16)].
	self unmap: r.
	regions remove: r
!
unmap: r
	self ioctl: container request: 'VFIO_IOMMU_UNMAP_DMA' struct: 'vfio_iommu_type1_dma_unmap' with: {{'iova'. r at: 3}. {'size'. 4096 * (r at: 2)}}.
	os munmap: (r at: 1) length: 4096 * (r at: 2)
!
release
	"Every DMA mapping, BAR mapping and descriptor I made, latest first; the function stays vfio-pci''s."
	regions isNil ifFalse: [regions reverseDo: [:r | container isNil ifFalse: [self unmap: r]]].
	regions := OrderedCollection new.
	bars isNil ifFalse: [bars do: [:b | (b at: 1) isNil ifFalse: [os munmap: (b at: 1) length: (b at: 2)]]].
	bars := Dictionary new.
	device isNil ifFalse: [os close: device. device := nil].
	group isNil ifFalse: [os close: group. group := nil].
	container isNil ifFalse: [os close: container. container := nil].
	scratch isNil ifFalse: [Machine free: scratch].
	scratch := nil
! !
