Object subclass: #VfioFake
	instanceVariableNames: 'calls fds nextFd groupNumber deviceName config regions barMemory anonymous dma faults containerOf iommuSet resets reserved'
	classVariableNames: ''
	package: 'Tests-Devices'!

VfioFake comment: 'I am Linux''s VFIO for tests (VfioPciDevice os: me): the calls of PosixDevice''s protocol (open:flags:, close:, ioctl:request:argument:, read:at:into:count:, write:at:from:count:, mmap:protection:flags:fd:offset:, munmap:length:, and its constants with Linux''s values) on a container (/dev/vfio/vfio), one group (/dev/vfio/<group>) and one PCI function in it, without a kernel. I check each call as vfio_iommu_type1 and vfio-pci would (argsz, the order: a container before SET_IOMMU, an IOMMU before the device, page-aligned DMA of my own anonymous memory, no overlapping IOVAs) and record it, with the structure''s bytes as the caller passed them, so a test can check the exact sequence and layouts (calls, trace).

The function: a configuration space (config:, 4 KB, read and written through the configuration region at 7 << 40, VFIO_PCI_OFFSET_SHIFT), memory BARs (bar:size:mappable:, Machine memory a test can preset, mmap''d at index << 40 when mappable), reset support. faults: makes a step fail as the kernel would: #notViable (a function of the group has another driver), #setContainer (EINVAL: the kernel refuses DMA ownership, as for a function with firmware RMR ranges), #noType1v2, #noType1, #noReset.'!

!VfioFake class methodsFor: 'instance creation'!
group: anInteger device: aLocation
	^self new setGroup: anInteger device: aLocation
! !

!VfioFake methodsFor: 'initialization'!
setGroup: anInteger device: aLocation
	groupNumber := anInteger.
	deviceName := aLocation.
	calls := OrderedCollection new.
	fds := Dictionary new.
	nextFd := 100.
	config := ByteArray new: 4096.
	regions := Dictionary new.
	barMemory := Dictionary new.
	anonymous := Dictionary new.
	dma := OrderedCollection new.
	faults := Set new.
	resets := 0.
	reserved := #()
! !

!VfioFake methodsFor: 'setting up'!
config: aByteArray
	config := aByteArray copy
!
bar: index size: n mappable: aBoolean
	"A memory BAR of n bytes in zeroed Machine memory (barMemory:)."
	regions at: index put: (Array with: (aBoolean ifTrue: [7] ifFalse: [3]) with: n).
	barMemory at: index put: (Machine allocate: n)
!
fault: aSymbol
	faults add: aSymbol
!
reserved: anArray
	reserved := anArray
!
release
	barMemory do: [:a | Machine free: a].
	barMemory := Dictionary new.
	anonymous do: [:v | Machine free: v last].
	anonymous := Dictionary new
! !

!VfioFake methodsFor: 'accessing'!
calls
	"Each call: {#open. path} {#close. kind} {#ioctl. kind. request name. argument} {#mmap. what. length} {#munmap. what. length} {#read or #write. region index. offset. count}; an ioctl''s argument is the structure''s bytes as passed, the int, the string, or the integer."
	^calls
!
trace
	"The calls but configuration reads and writes, as text: ''open /dev/vfio/vfio'', ''container VFIO_GET_API_VERSION'', ''mmap bar 0'', ''close device''..."
	^((calls reject: [:c | (c first = #read or: [c first = #write]) and: [(c at: 2) = 7]]) collect: [:c |
		c first = #open ifTrue: ['open ', (c at: 2)] ifFalse: [
		c first = #close ifTrue: ['close ', (c at: 2)] ifFalse: [
		c first = #ioctl ifTrue: [(c at: 2), ' ', (c at: 3)] ifFalse: [
		(c first = #mmap or: [c first = #munmap]) ifTrue: [c first asString, ' ', (c at: 2)] ifFalse: [
		c first asString, ' region ', (c at: 2) printString]]]]]) asArray
!
ioctls: aName
	"The arguments of every ioctl aName, in order."
	^((calls select: [:c | c first = #ioctl and: [(c at: 3) = aName]]) collect: [:c | c at: 4]) asArray
!
barMemory: index
	^barMemory at: index
!
config
	^config
!
dma
	"{vaddr. iova. size. flags} of each live DMA mapping"
	^dma
!
openFds
	^fds
!
resets
	^resets
!
reservedRegionsOf: aGroup
	^reserved
! !

!VfioFake methodsFor: 'constants'!
isAvailable
	^true
!
O_RDWR
	^2
!
O_CLOEXEC
	^16r80000
!
PROT_READ
	^1
!
PROT_WRITE
	^2
!
MAP_SHARED
	^1
!
MAP_PRIVATE
	^2
!
MAP_ANONYMOUS
	^16r20
! !

!VfioFake methodsFor: 'private'!
fail: errno call: what
	^OSError signal: what, ': errno ', errno printString errno: errno path: nil
!
kind: fd
	^fds at: fd ifAbsent: [self fail: OSError EBADF call: 'bad descriptor']
!
newFd: kind
	nextFd := nextFd + 1.
	fds at: nextFd put: kind.
	^nextFd
!
constant: aName
	^VfioPciDevice constant: aName
!
structOf: aName
	"The structure request aName passes, or nil."
	^#(#('VFIO_GROUP_GET_STATUS' 'vfio_group_status') #('VFIO_DEVICE_GET_INFO' 'vfio_device_info') #('VFIO_DEVICE_GET_REGION_INFO' 'vfio_region_info')
		#('VFIO_IOMMU_GET_INFO' 'vfio_iommu_type1_info') #('VFIO_IOMMU_MAP_DMA' 'vfio_iommu_type1_dma_map') #('VFIO_IOMMU_UNMAP_DMA' 'vfio_iommu_type1_dma_unmap'))
		detect: [:p | p first = aName] ifNone: [nil]
!
argsz: a atLeast: n call: what
	(Machine uint32At: a) < n ifTrue: [self fail: OSError EINVAL call: what]
! !

!VfioFake methodsFor: 'calls'!
open: path flags: anInteger
	calls add: {#open. path}.
	path = '/dev/vfio/vfio' ifTrue: [^self newFd: 'container'].
	path = ('/dev/vfio/', groupNumber printString) ifTrue: [^self newFd: 'group'].
	^self fail: OSError ENOENT call: 'open'
!
close: fd
	calls add: {#close. self kind: fd}.
	fds removeKey: fd.
	^0
!
ioctl: fd request: request argument: a
	| kind name struct arg |
	kind := self kind: fd.
	name := VfioPciDevice requestName: request.
	name isNil ifTrue: [^self fail: OSError ENOTTY call: 'ioctl'].
	struct := self structOf: name.
	arg := struct notNil
		ifTrue: [Machine bytesAt: a count: ((VfioPciDevice struct: struct last) at: 2)]
		ifFalse: [name = 'VFIO_GROUP_SET_CONTAINER'
			ifTrue: [Machine uint32At: a]
			ifFalse: [name = 'VFIO_GROUP_GET_DEVICE_FD'
				ifTrue: [| s n | n := 0. [(Machine uint8At: a + n) ~= 0] whileTrue: [n := n + 1]. s := (Machine bytesAt: a count: n) asString. s]
				ifFalse: [a]]].
	calls add: {#ioctl. kind. name. arg}.
	^self perform: name kind: kind fd: fd argument: a
!
perform: name kind: kind fd: fd argument: a
	name = 'VFIO_GET_API_VERSION' ifTrue: [kind = 'container' ifFalse: [^self fail: OSError ENOTTY call: name]. ^0].
	name = 'VFIO_CHECK_EXTENSION' ifTrue: [^(self extensions includes: a) ifTrue: [1] ifFalse: [0]].
	name = 'VFIO_GROUP_GET_STATUS' ifTrue: [
		self argsz: a atLeast: 8 call: name.
		Machine uint32At: a + 4 put: ((faults includes: #notViable) ifTrue: [0] ifFalse: [1]) + (containerOf isNil ifTrue: [0] ifFalse: [2]).
		^0].
	name = 'VFIO_GROUP_SET_CONTAINER' ifTrue: [
		(fds at: (Machine uint32At: a) ifAbsent: [nil]) = 'container' ifFalse: [^self fail: OSError EBADF call: name].
		((faults includes: #notViable) or: [faults includes: #setContainer]) ifTrue: [^self fail: OSError EINVAL call: name].
		containerOf := Machine uint32At: a.
		^0].
	name = 'VFIO_SET_IOMMU' ifTrue: [
		(containerOf isNil or: [(self extensions includes: a) not]) ifTrue: [^self fail: OSError EINVAL call: name].
		iommuSet := a.
		^0].
	name = 'VFIO_GROUP_GET_DEVICE_FD' ifTrue: [
		iommuSet isNil ifTrue: [^self fail: OSError EINVAL call: name].
		(calls last at: 4) = deviceName ifFalse: [^self fail: OSError ENODEV call: name].
		^self newFd: 'device'].
	name = 'VFIO_DEVICE_GET_INFO' ifTrue: [
		self argsz: a atLeast: 24 call: name.
		Machine uint32At: a + 4 put: ((faults includes: #noReset) ifTrue: [2] ifFalse: [3]); uint32At: a + 8 put: 9; uint32At: a + 12 put: 5.
		^0].
	name = 'VFIO_DEVICE_GET_REGION_INFO' ifTrue: [| index r |
		self argsz: a atLeast: 32 call: name.
		index := Machine uint32At: a + 8.
		index >= 9 ifTrue: [^self fail: OSError EINVAL call: name].
		r := index = 7 ifTrue: [#(3 4096)] ifFalse: [regions at: index ifAbsent: [#(0 0)]].
		Machine uint32At: a + 4 put: r first; uint64At: a + 16 put: r last; uint64At: a + 24 put: (index bitShift: 40).
		^0].
	name = 'VFIO_DEVICE_RESET' ifTrue: [
		(faults includes: #noReset) ifTrue: [^self fail: OSError EINVAL call: name].
		resets := resets + 1.
		^0].
	name = 'VFIO_IOMMU_MAP_DMA' ifTrue: [| vaddr iova size |
		self argsz: a atLeast: 32 call: name.
		(iommuSet isNil or: [kind ~= 'container']) ifTrue: [^self fail: OSError EINVAL call: name].
		vaddr := Machine uint64At: a + 8. iova := Machine uint64At: a + 16. size := Machine uint64At: a + 24.
		(size = 0 or: [(vaddr \\ 4096) ~= 0 or: [(iova \\ 4096) ~= 0 or: [(size \\ 4096) ~= 0]]]) ifTrue: [^self fail: OSError EINVAL call: name].
		((anonymous at: vaddr ifAbsent: [#(0 0)]) first) >= size ifFalse: [^self fail: OSError EFAULT call: name].
		(dma anySatisfy: [:m | iova < ((m at: 2) + (m at: 3)) and: [(m at: 2) < (iova + size)]]) ifTrue: [^self fail: OSError EEXIST call: name].
		dma add: (Array with: vaddr with: iova with: size with: (Machine uint32At: a + 4)).
		^0].
	name = 'VFIO_IOMMU_UNMAP_DMA' ifTrue: [| iova size m |
		self argsz: a atLeast: 24 call: name.
		iova := Machine uint64At: a + 8. size := Machine uint64At: a + 16.
		m := dma detect: [:each | (each at: 2) = iova and: [(each at: 3) = size]] ifNone: [^self fail: OSError EINVAL call: name].
		dma remove: m.
		^0].
	^self fail: OSError ENOTTY call: name
!
extensions
	^(#(1 3) reject: [:e | (e = 3 and: [faults includes: #noType1v2]) or: [faults includes: #noType1]]) asArray
!
region: offset
	"{index. offset in it} of a device file offset"
	^Array with: (offset bitShift: -40) with: (offset bitAnd: (1 bitShift: 40) - 1)
!
read: fd at: offset into: address count: n
	| r |
	(self kind: fd) = 'device' ifFalse: [^self fail: OSError EINVAL call: 'pread'].
	r := self region: offset.
	calls add: {#read. r first. r last. n}.
	r first = 7 ifTrue: [
		r last + n > config size ifTrue: [^self fail: OSError EINVAL call: 'pread'].
		Machine bytesAt: address put: (config copyFrom: r last + 1 to: r last + n).
		^n].
	(barMemory includesKey: r first) ifFalse: [^self fail: OSError EINVAL call: 'pread'].
	Machine bytesAt: address put: (Machine bytesAt: (barMemory at: r first) + r last count: n).
	^n
!
write: fd at: offset from: address count: n
	| r |
	(self kind: fd) = 'device' ifFalse: [^self fail: OSError EINVAL call: 'pwrite'].
	r := self region: offset.
	calls add: {#write. r first. r last. n}.
	r first = 7 ifTrue: [
		config replaceFrom: r last + 1 to: r last + n with: (Machine bytesAt: address count: n) startingAt: 1.
		^n].
	(barMemory includesKey: r first) ifFalse: [^self fail: OSError EINVAL call: 'pwrite'].
	Machine bytesAt: (barMemory at: r first) + r last put: (Machine bytesAt: address count: n).
	^n
!
mmap: length protection: p flags: f fd: fd offset: offset
	| r a |
	fd = -1 ifTrue: [
		(f bitAnd: self MAP_ANONYMOUS) = 0 ifTrue: [^self fail: OSError EBADF call: 'mmap'].
		"page-aligned, as mmap answers"
		r := Machine allocate: length + 4096.
		a := r + 4095 // 4096 * 4096.
		Machine bytesAt: a put: (ByteArray new: length).
		anonymous at: a put: (Array with: length with: r).
		calls add: {#mmap. 'anonymous ', length printString. length}.
		^a].
	(self kind: fd) = 'device' ifFalse: [^self fail: OSError ENODEV call: 'mmap'].
	r := self region: offset.
	(r last ~= 0 or: [(((regions at: r first ifAbsent: [#(0 0)]) first) bitAnd: 4) = 0 or: [length > (regions at: r first) last]]) ifTrue: [^self fail: OSError EINVAL call: 'mmap'].
	calls add: {#mmap. 'bar ', r first printString. length}.
	^barMemory at: r first
!
munmap: address length: n
	(anonymous includesKey: address) ifTrue: [
		calls add: {#munmap. 'anonymous ', n printString. n}.
		Machine free: (anonymous at: address) last.
		anonymous removeKey: address.
		^0].
	barMemory keysAndValuesDo: [:i :a | a = address ifTrue: [calls add: {#munmap. 'bar ', i printString. n}. ^0]].
	^self fail: OSError EINVAL call: 'munmap'
! !
