TestCase subclass: #NvGspClientTest
	instanceVariableNames: 'region queues gsp transport memory window gpu'
	classVariableNames: ''
	package: 'Tests-NV'!

NvGspClientTest comment: 'Tests the client side of RM over GSP (steps 4-6 of cv/samaltak#20, docs/nv-gsp.md 14) against NvFakeGsp: the GMMU v3 entries bit for bit as dev_mmu.h places their fields, NvGmmu''s five levels, ALLOC_MEMORY and SET_PAGE_DIRECTORY byte for byte, then NvDevice, NvMemory, NvChannel and NvCompute unchanged over NvGspTransport: the class list and GR info from their V2 controls, memory described with ALLOC_MEMORY and mapped through page tables the fake walks, a channel with the descriptors CPU-RM fills, fences through the fake host''s semaphore releases, and a launch whose QMD and constant bank the fake reads through the page tables. Verified only against the fake; needs no GPU.'!

!NvGspClientTest methodsFor: 'running'!
setUp
	region := Machine allocate: NvGspQueues size.
	Machine bytesAt: region put: (ByteArray new: NvGspQueues size).
	queues := NvGspQueues at: region device: 16r80000000.
	queues prepare.
	memory := NvFakeDmaMemory new.
	gsp := NvFakeGsp on: queues.
	gsp memory: memory.
	window := Machine allocate: 16r10000.
	Machine bytesAt: window put: (ByteArray new: 16r10000).
	transport := NvGspTransport endpoint: queues cpuEndpoint doorbell: [gsp ring].
	transport memory: memory; usermode: window.
	gsp startHost: window
!
tearDown
	gpu notNil ifTrue: [gpu close].
	gsp stopHost.
	memory release.
	Machine free: window; free: region
!
open
	^gpu := NvDevice open: 0 over: transport
!
functions
	^(gsp received collect: [:m | m u32At: 12]) asArray
! !

!NvGspClientTest methodsFor: 'tests'!
testPageTableEntries
	"dev_mmu.h: PTE VALID 0, APERTURE 2:1 (2 coherent system memory), PCF 7:3 (1 regular RW atomic uncached), ADDRESS 51:12; PDE APERTURE 2:1, PCF 5:3 (3 uncached, no ATS), ADDRESS 51:12; dual PDE: small half APERTURE 66:65, PCF 69:67, ADDRESS 115:76."
	self assert: (NvGsp pte: 16r123456000) equals: 16r12345600D.
	self assert: (NvGsp pde: 16r40000001000) equals: 16r4000000101C.
	self assert: (NvGsp dualPdeSmall: 16r40000002000) equals: #(0 16r4000000201C).
	self should: [NvGsp pte: 16r123456010] raise: Error
!
testGmmuLevels
	| g va |
	g := NvGmmu on: memory.
	va := 16r200000000.
	g map: 16r40000005000 at: va size: 3 * 4096.
	self assert: g tableCount equals: 6.
	self assert: (g translate: va) equals: 16r40000005000.
	self assert: (g translate: va + 8195) equals: 16r40000007003.
	self assert: (g translate: va + (3 * 4096)) isNil.
	g map: 16r40000005000 at: va + 16r200000 size: 4096.
	self assert: g tableCount equals: 7.
	g map: 16r40000005000 at: (1 bitShift: 56) size: 4096.
	self assert: g tableCount equals: 12.
	self assert: (g root u64At: 8) equals: (NvGsp pde: (g root u64At: 8) - 16r1C).
	g unmap: va size: 4096.
	self assert: (g translate: va) isNil.
	self assert: (g translate: va + 4096) equals: 16r40000006000.
	self should: [g map: 0 at: (1 bitShift: 57) size: 4096] raise: Error
!
testAllocMemoryMessage
	| m |
	m := NvGsp allocMemoryClient: 16rC1D00001 device: 16rCAF00001 memory: 16rCAF00009 address: 16r40000100000 length: 8192 sequence: 5.
	self assert: m size equals: 32 + 56 + 8.
	self assert: (m u32At: 8) equals: 32 + 56 + 8.
	self assert: (m u32At: 12) equals: 4.
	self assert: ((32 to: 44 by: 4) collect: [:o | m u32At: o]) asArray equals: #(16rC1D00001 16rCAF00001 16rCAF00009 16r81).
	self assert: (m u32At: 32 + 16) equals: 16r1000.
	self assert: (m u64At: 32 + 32) equals: 8192.
	self assert: (m u32At: 32 + 40) equals: 1.
	self assert: (m u32At: 32 + 48) equals: 16r10000.
	self assert: (m u64At: 32 + 56) equals: 16r40000100.
	self assert: (m u32At: 24) equals: 5
!
testSetPageDirectoryParameters
	| p |
	p := NvGsp setPageDirectory: 16r40000003000 entries: 2 vaSpace: 16rCAF00005.
	self assert: p size equals: 32.
	self assert: p bytes equals: #[16r00 16r30 0 0 16r00 16r04 0 0  2 0 0 0  1 0 0 0  5 0 16rF0 16rCA  0 0 0 0  0 0 0 0  0 0 0 0]
!
testDeviceOpens
	| g |
	self open.
	self assert: gpu smVersion equals: 16rA04.
	self assert: gpu smCount equals: 48.
	self assert: (gpu classFrom: NvRm computeClasses) equals: 16rCEC0.
	self assert: gpu doorbell equals: window.
	g := transport vaSpaces at: gpu vaSpace.
	self assert: gsp pageDirectories size equals: 1.
	self assert: gsp pageDirectories first equals: {g root deviceAddress. 2. 1. gpu vaSpace}.
	self assert: (self functions first: 9) equals: #(103 103 103 76 76 103 76 103 103).
	self assert: ((gsp received at: 4) u32At: 32 + 8) equals: 16r800292.
	self assert: ((gsp received at: 5) u32At: 32 + 8) equals: 16r20801228
!
testMemory
	| m b |
	self open.
	m := gpu allocate: 8192.
	b := transport buffers at: m handle.
	self assert: (gsp memories at: m handle) equals: {b deviceAddress. 8192}.
	self assert: m cpuAddress equals: b cpuAddress.
	self assert: (gsp translate: m gpuAddress + 4100) equals: b deviceAddress + 4100.
	m uint32At: 4100 put: 16rCAFE.
	self assert: (gsp u32AtVa: m gpuAddress + 4100) equals: 16rCAFE.
	m free.
	self assert: self functions last equals: 10.
	self deny: (gsp memories keys includes: m handle) & (gsp objects includesKey: m handle)
!
testChannelAndFences
	| c p ring |
	self open.
	c := gpu newChannel.
	self assert: gsp channels size equals: 1.
	p := gsp channels anyOne first.
	ring := (gsp objects keys select: [:h | (gsp memories includesKey: h)]) detect: [:h | ((gsp memories at: h) last) = 16r3000].
	self assert: (p at: 'userdMem.base') equals: (gsp memories at: ring) first + 16r2000.
	self assert: (p at: 'instanceMem.size') equals: 4096.
	self assert: (p at: 'ramfcMem.base') equals: (p at: 'instanceMem.base').
	self assert: c token equals: 16r40000001.
	c sync.
	self assert: c completedValue equals: 1.
	c sync.
	self assert: c completedValue equals: 2.
	self assert: c gpGet equals: 2.
	self assert: (gsp methods anySatisfy: [:m | (m at: 3) = 16r6C and: [((m at: 4) bitAnd: 7) = 1]])
!
testLaunch
	"NvCompute's launch path: the fake runs 'fill' (pointer, value, count at 16r380 of constant bank 0, as the cubin's KPARAM_INFO says) when it sees the QMD."
	| m |
	self open.
	gsp onLaunch: [:qmd :fake | | bank ptr value count |
		bank := ((fake u32AtVa: qmd + (4 * 42)) + (((fake u32AtVa: qmd + (4 * 43)) bitAnd: 16r7FFFF) bitShift: 32)) bitShift: 6.
		ptr := fake u64AtVa: bank + 16r380.
		value := fake u32AtVa: bank + 16r388.
		count := fake u32AtVa: bank + 16r38C.
		0 to: count - 1 do: [:i | fake write32: value atVa: ptr + (4 * i)]].
	m := gpu allocate: 4096.
	gpu newCompute run: (NvTestKernels cubin kernelNamed: 'fill') grid: 1 block: 256 arguments: (Array with: m gpuAddress with: 7 with: 3).
	self assert: ((0 to: 3) collect: [:i | m uint32At: 4 * i]) asArray equals: #(7 7 7 0).
	self assert: gsp launches size equals: 1
!
testWithoutMemory
	| e |
	transport := NvGspTransport endpoint: queues cpuEndpoint doorbell: [gsp ring].
	e := [NvDevice open: 0 over: transport. nil] on: Error do: [:x | x return: x messageText].
	self assert: (e includesSubstring: 'set memory: first')
! !
