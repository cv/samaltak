TestCase subclass: #NvTransportTest
	instanceVariableNames: 'transport gpu'
	classVariableNames: ''
	package: 'Tests-NV'!

NvTransportTest comment: 'Tests the seam between NvDevice (and NvMemory) and the resource manager: NvDevice open:over: an NvFakeTransport makes the same RM calls, in the same order, as it does over the kernel module''s ioctls (NvIoctlTransport, which NvGpuTest exercises on a real GPU), and close frees what it made. Needs no GPU.'!

!NvTransportTest methodsFor: 'running'!
setUp
	transport := NvFakeTransport new.
	gpu := NvDevice open: 0 over: transport
!
tearDown
	gpu close
! !

!NvTransportTest methodsFor: 'tests'!
testOpen
	| log root device subdevice |
	log := transport log.
	root := gpu root.
	device := gpu device.
	subdevice := gpu subdevice.
	self assert: (log first: 4) asArray equals: {
		{#alloc. NvRm classRootClient. 0. 0. root}.
		{#attachGpu. 0}.
		{#control. NvRm cmdGpuGetIdInfoV2. root. root}.
		{#alloc. NvRm classDevice. root. root. device}}.
	self assert: (log at: 5) equals: {#alloc. NvRm classSubdevice. root. device. subdevice}.
	self assert: ((log select: [:each | each first = #control]) collect: [:each | each at: 2]) asArray
		equals: {NvRm cmdGpuGetIdInfoV2. NvRm cmdDeviceGetClassList. NvRm cmdDeviceGetClassList. NvRm cmdGrGetInfo}.
	self assert: log last equals: {#mapUsermode. (log at: log size - 1) last}.
	self assert: ((log at: log size - 1) at: 2) equals: 16rC761.
	self assert: gpu smVersion equals: 16rA04.
	self assert: gpu smCount equals: 48.
	self assert: (gpu classes includes: 16rCDC0).
	self assert: gpu isOpen
!
testMemory
	| m n h |
	m := gpu allocate: 100.
	self assert: m size equals: 4096.
	m uint32At: 0 put: 42.
	self assert: (m uint32At: 0) equals: 42.
	self assert: (transport log last: 3) asArray equals: {
		{#alloc. NvRm classMemorySystem. gpu root. gpu device. m handle}.
		{#mapMemory. m handle}.
		{#mapToGpu. m handle. gpu virtualMemory}}.
	self assert: m gpuAddress equals: (16r200000000 + ((m handle bitAnd: 16rFFFF) bitShift: 20)).
	h := m handle.
	n := transport log size.
	m free.
	self assert: (transport log allButFirst: n) asArray equals: {
		{#unmapCpu. 4096}.
		{#unmapFromGpu. h. gpu virtualMemory}.
		{#free. h. gpu root. gpu device}}
!
testCloseFreesEverything
	| root |
	gpu allocate: 4096; allocate: 8192.
	root := gpu root.
	gpu close.
	self deny: gpu isOpen.
	self assert: transport objects isEmpty.
	self assert: transport mappings isEmpty.
	self assert: (transport log last: 2) asArray equals: {{#free. root. root. 0}. {#close}}.
	gpu close.
	self assert: transport log last equals: {#close}
!
testErrorsComeBackAsNvError
	self should: [gpu alloc: 16r50A0 parent: 16r1234 params: nil] raise: NvError.
	self should: [NvDevice open: 1 over: NvFakeTransport new] raise: Error
! !
