TestCase subclass: #NvGpuTest
	instanceVariableNames: 'gpu compute cubin'
	classVariableNames: ''
	package: 'Tests-NV'!

NvGpuTest comment: 'Tests System-NV on a real NVIDIA GPU (the GB10): opens the device, allocates memory, makes a channel and runs the test kernels (NvTestKernels), checking their results from Smalltalk. Needs a GPU, so it does not run by default (runsByDefault): make test-nv runs it, and fails, saying so, where there is no NVIDIA driver. Every test closes the device in tearDown, which frees the channels and memory it made.'!

!NvGpuTest methodsFor: 'running'!
setUp
	NvDevice isAvailable ifFalse: [^self error: 'no NVIDIA GPU here (no /dev/nvidiactl, or no devices on this platform): NvGpuTest needs one'].
	cubin := NvTestKernels cubin.
	gpu := NvDevice open
!
tearDown
	gpu notNil ifTrue: [gpu close]
!
compute
	^compute ifNil: [compute := gpu newCompute]
!
kernel: aString
	^cubin kernelNamed: aString
!
timeLimitMilliseconds
	^60000
! !

!NvGpuTest methodsFor: 'tests'!
testFencesAcrossWrapsAndDrains
	"Enough fences to start the pushbuffer over and drain the ring many times: each is the newest value (a wrap's or drain's own fence comes before it, so the semaphore never goes back), and the GPU reaches the last."
	| ch f |
	ch := self compute channel.
	1 to: 5000 do: [:i |
		f := ch fence.
		f = ch lastFence ifFalse: [^self assert: false description: 'fence ', f printString, ' is not the newest, ', ch lastFence printString]].
	ch wait: f.
	self assert: ch completedValue equals: f
!
testOpen
	self assert: gpu isOpen.
	self assert: gpu smVersion >= 16rA00.
	self assert: gpu smCount > 0.
	self assert: (gpu classes includes: NvRm classVaSpace).
	self assert: (NvRm computeClasses anySatisfy: [:c | gpu classes includes: c])
!
testMemory
	| m |
	m := gpu allocate: 10000.
	self assert: m size equals: 12288.
	self assert: m gpuAddress > 0.
	self assert: (m uint32At: 0) equals: 0.
	m uint64At: 8 put: 16r123456789ABCDEF.
	self assert: (m uint64At: 8) equals: 16r123456789ABCDEF.
	m bytesAt: 100 put: #[1 2 3].
	self assert: (m bytesAt: 100 count: 3) equals: #[1 2 3].
	self should: [m uint32At: 12288] raise: Error.
	m free.
	self assert: m isFreed.
	self deny: (gpu memories includes: m)
!
testChannelFence
	| c |
	c := gpu newChannel.
	self assert: c token > 0.
	c sync.
	self assert: c completedValue equals: 1.
	1 to: 100 do: [:i | c fence].
	c sync.
	self assert: c completedValue equals: 102
!
testFill
	| m |
	m := gpu allocate: 4096 * 4.
	self compute run: (self kernel: 'fill') grid: 16 block: 256 arguments: (Array with: m gpuAddress with: 16rCAFEF00D with: 4000).
	self assert: (m uint32At: 0) equals: 16rCAFEF00D.
	self assert: (m uint32At: 3999 * 4) equals: 16rCAFEF00D.
	self assert: (m uint32At: 4000 * 4) equals: 0
!
testVectorAdd
	| n a b c bytes |
	n := 10000.
	a := gpu allocate: n * 4.
	b := gpu allocate: n * 4.
	c := gpu allocate: n * 4.
	bytes := ByteArray new: n * 4.
	0 to: n - 1 do: [:i | bytes float32At: i * 4 + 1 put: i asFloat].
	a bytesAt: 0 put: bytes.
	0 to: n - 1 do: [:i | bytes float32At: i * 4 + 1 put: (i * 2 + 0.5)].
	b bytesAt: 0 put: bytes.
	self compute run: (self kernel: 'vadd') grid: n + 255 // 256 block: 256 arguments: (Array with: a gpuAddress with: b gpuAddress with: c gpuAddress with: n).
	bytes := c bytesAt: 0 count: n * 4.
	self assert: ((0 to: n - 1) allSatisfy: [:i | (bytes float32At: i * 4 + 1) = (i * 3 + 0.5)])
!
testLaunchDimensions
	| m |
	m := gpu allocate: 4096.
	self compute run: (self kernel: 'dims') grid: #(3 2 1) block: #(4 5 6) arguments: (Array with: m gpuAddress).
	self assert: ((0 to: 5) collect: [:i | m uint32At: i * 4]) equals: #(4 5 6 3 2 1)
!
testSharedMemory
	| m |
	m := gpu allocate: 8 * 256 * 4.
	0 to: 8 * 256 - 1 do: [:i | m uint32At: i * 4 put: i].
	self compute run: (self kernel: 'reverse256') grid: 8 block: 256 arguments: (Array with: m gpuAddress).
	self assert: (m uint32At: 0) equals: 255.
	self assert: (m uint32At: 255 * 4) equals: 0.
	self assert: (m uint32At: 256 * 4) equals: 511
!
testConstantBank
	| m |
	m := gpu allocate: 4096.
	self compute run: (self kernel: 'lookup') grid: 1 block: 64 arguments: (Array with: m gpuAddress with: 64).
	self assert: ((0 to: 5) collect: [:i | m uint32At: i * 4]) equals: #(16r11111111 16r22222223 16r33333335 16r44444447 16r11111115 16r22222227)
!
testManyLaunches
	"More launches in flight than QMD slots: each waits for the slot it reuses."
	| m k fences |
	m := gpu allocate: 4096.
	k := self kernel: 'fill'.
	fences := (1 to: 200) collect: [:i | self compute launch: k grid: 1 block: 32 arguments: (Array with: m gpuAddress with: i with: 32)].
	self compute wait: fences last.
	self assert: (m uint32At: 0) equals: 200
!
testBadLaunch
	self should: [self compute launch: (self kernel: 'copy16') grid: 1 block: 512 arguments: #(0 0 0)] raise: Error.
	self should: [self compute launch: (self kernel: 'fill') grid: 1 block: 32 arguments: #(0)] raise: Error
!
testCloseFreesEverything
	gpu newCompute.
	gpu allocate: 4096.
	self assert: gpu channels size equals: 1.
	gpu close.
	self deny: gpu isOpen.
	gpu close
! !

!NvGpuTest class methodsFor: 'testing'!
runsByDefault
	"I need an NVIDIA GPU: make test-nv runs me."
	^false
! !
