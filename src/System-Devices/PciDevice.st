Object subclass: #PciDevice
	instanceVariableNames: 'firmware handle pci scratch regions'
	classVariableNames: ''
	package: 'System-Devices'!

PciDevice comment: 'I am a PCI function for drivers in Smalltalk, through the firmware''s PCI I/O protocol (UEFI 2.10, 14.4): its configuration space and capabilities, the address of a memory BAR (the firmware maps the BARs where the configuration space says, so a driver reads and writes its registers there with Machine), memory decoding and bus mastering, DMA memory (AllocateBuffer and Map, a common buffer: the device''s address of it differs from the CPU''s behind an IOMMU), and the firmware''s drivers, which a driver of ours takes the device from (disconnect).'!

!PciDevice class methodsFor: 'finding'!
guid
	"EFI_PCI_IO_PROTOCOL"
	^'4cf5b200-68b8-4ca5-9eec-b23e3f50029a'
!
in: aFirmware detect: aBlock
	"The first of the firmware's PCI functions for which aBlock answers true, or nil."
	(aFirmware handlesSupporting: self guid) do: [:h |
		(self firmware: aFirmware handle: h) ifNotNil: [:d |
			(aBlock value: d) ifTrue: [^d].
			d release]].
	^nil
!
firmware: aFirmware handle: aHandle
	"The function behind aHandle, or nil if it has no PCI I/O."
	^(aFirmware protocol: self guid on: aHandle) ifNotNil: [:p | self new setFirmware: aFirmware handle: aHandle pci: p]
! !

!PciDevice methodsFor: 'initialization'!
setFirmware: aFirmware handle: aHandle pci: aProtocol
	firmware := aFirmware.
	handle := aHandle.
	pci := aProtocol.
	scratch := Machine allocate: 32.
	regions := OrderedCollection new
! !

!PciDevice methodsFor: 'accessing'!
firmware
	^firmware
!
handle
	^handle
!
vendor
	^self config: 0 width: 2
!
deviceId
	^self config: 2 width: 2
!
subsystemId
	^self config: 16r2E width: 2
! !

!PciDevice methodsFor: 'configuration'!
pci: offset with: a
	"Call the PCI I/O function at offset in the protocol."
	^Machine call: (firmware function: pci at: offset) with: pci with: a
!
pci: offset with: a with: b
	^Machine call: (firmware function: pci at: offset) with: pci with: a with: b
!
pci: offset with: a with: b with: c
	^Machine call: (firmware function: pci at: offset) with: pci with: a with: b with: c
!
pci: offset with: a with: b with: c with: d
	^Machine call: (firmware function: pci at: offset) with: pci with: a with: b with: c with: d
!
pci: offset with: a with: b with: c with: d with: e
	^Machine call: (firmware function: pci at: offset) with: pci with: a with: b with: c with: d with: e
!
widthCode: w
	^w = 1 ifTrue: [0] ifFalse: [w = 2 ifTrue: [1] ifFalse: [2]]
!
config: offset width: w
	"The configuration space's w bytes (1, 2, 4) at offset."
	Machine uint32At: scratch put: 0.
	self pci: 48 with: (self widthCode: w) with: offset with: 1 with: scratch.
	^Machine read: scratch size: w
!
config: offset width: w put: v
	Machine uint32At: scratch put: v.
	self pci: 56 with: (self widthCode: w) with: offset with: 1 with: scratch
!
capabilitiesDo: aBlock
	"aBlock value: the configuration offset of each capability value: its ID."
	| cap |
	((self config: 6 width: 2) bitAnd: 16r10) = 0 ifTrue: [^self].
	cap := (self config: 16r34 width: 1) bitAnd: 16rFC.
	[cap ~= 0] whileTrue: [
		aBlock value: cap value: (self config: cap width: 1).
		cap := (self config: cap + 1 width: 1) bitAnd: 16rFC]
!
barAddress: index
	"The address of memory BAR index (64-bit ones take two), nil if it is an I/O BAR."
	| low |
	low := self config: 16r10 + (4 * index) width: 4.
	(low bitAnd: 1) = 1 ifTrue: [^nil].
	^(low bitAnd: 16rFFFFFFF0) + ((low bitAnd: 6) = 4
		ifTrue: [(self config: 16r14 + (4 * index) width: 4) bitShift: 32]
		ifFalse: [0])
! !

!PciDevice methodsFor: 'driving'!
disconnect
	"Take the device from the firmware's drivers. Answer whether none manages it any more."
	^firmware disconnect: handle
!
enable
	"Decode memory, master the bus. Answer whether it could."
	self pci: 120 with: 4 with: 0 with: scratch.
	^(firmware isError: (self pci: 120 with: 2 with: ((Machine uint64At: scratch) bitAnd: 16r0600) with: 0)) not
!
allocate: bytes
	"The CPU's address of zeroed DMA memory of bytes (whole pages, below 4 GB), or nil; deviceAddress: is the device's."
	| pages host zero |
	pages := bytes + 4095 // 4096.
	(firmware isError: (self pci: 88 with: 0 with: 4 with: pages with: scratch with: 0)) ifTrue: [^nil].
	host := Machine uint64At: scratch.
	Machine uint64At: scratch put: pages * 4096.
	(firmware isError: (self pci: 72 with: 2 with: host with: scratch with: scratch + 8 with: scratch + 16)) ifTrue: [
		self pci: 96 with: pages with: host.
		^nil].
	regions add: {host. pages. Machine uint64At: scratch + 8. Machine uint64At: scratch + 16}.
	zero := ByteArray new: 4096.
	0 to: pages - 1 do: [:i | Machine bytesAt: host + (4096 * i) put: zero].
	^host
!
deviceAddress: aHostAddress
	"The device's address of aHostAddress in DMA memory of allocate:'s."
	| r |
	r := regions detect: [:each | aHostAddress >= (each at: 1) and: [aHostAddress < ((each at: 1) + (4096 * (each at: 2)))]].
	^(r at: 3) + (aHostAddress - (r at: 1))
!
release
	"Give back the DMA memory (the device must not use it any more) and mine."
	regions do: [:r |
		self pci: 80 with: (r at: 4).
		self pci: 96 with: (r at: 2) with: (r at: 1)].
	regions := OrderedCollection new.
	scratch isNil ifFalse: [Machine free: scratch].
	scratch := nil
! !
