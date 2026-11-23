TestCase subclass: #NvGspTransportTest
	instanceVariableNames: 'region queues gsp transport'
	classVariableNames: ''
	package: 'Tests-NV'!

NvGspTransportTest comment: 'Tests NvGspQueues, NvGspEndpoint and NvGspTransport against NvFakeGsp over real queues in Machine memory: the page table and queue headers as nvidia.ko makes them, RPC messages and their elements byte for byte (checksum, sequence numbers, entry counts), the ring''s wrap-around, multi-entry messages, events before a reply, errors, and NvDevice''s RM calls over RPC as far as they go before the client side of RM (step 4 of cv/samaltak#20). Needs no GPU.'!

!NvGspTransportTest methodsFor: 'running'!
setUp
	region := Machine allocate: NvGspQueues size.
	Machine bytesAt: region put: (ByteArray new: NvGspQueues size).
	queues := NvGspQueues at: region device: 16r80000000.
	queues prepare.
	gsp := NvFakeGsp on: queues.
	transport := NvGspTransport endpoint: queues cpuEndpoint doorbell: [gsp ring].
	transport open
!
tearDown
	Machine free: region
! !

!NvGspTransportTest methodsFor: 'tests'!
testSharedMemory
	| a |
	self assert: NvGspQueues pageTableEntryCount equals: 129.
	self assert: NvGspQueues size equals: 4096 + 16r80000.
	self assert: ((0 to: 128) collect: [:i | Machine uint64At: region + (8 * i)]) asArray equals: ((0 to: 128) collect: [:i | 16r80000000 + (4096 * i)]) asArray.
	self assert: (Machine uint64At: region + (8 * 129)) equals: 0.
	self assert: ((0 to: 28 by: 4) collect: [:o | Machine uint32At: region + 4096 + o]) asArray equals: #(0 16r40000 4096 63 0 1 32 4096).
	self assert: ((0 to: 28 by: 4) collect: [:o | Machine uint32At: region + 4096 + 16r40000 + o]) asArray equals: #(0 16r40000 4096 63 0 1 32 4096).
	a := queues arguments: 16r90000000 size: NvGsp sysmemHeapSize.
	self assert: (a at: 'messageQueueInitArguments.sharedMemPhysAddr') equals: 16r80000000.
	self assert: (a at: 'messageQueueInitArguments.pageTableEntryCount') equals: 129.
	self assert: (a at: 'messageQueueInitArguments.cmdQueueOffset') equals: 4096.
	self assert: (a at: 'messageQueueInitArguments.statQueueOffset') equals: 4096 + 16r40000
!
testAllocControlFree
	| root device element params |
	root := transport alloc: NvRm classRootClient client: 0 parent: 0 params: nil.
	self assert: root equals: 16rC1D00001.
	"The message as it sits in the command queue's first entry."
	element := Machine bytesAt: region + 4096 + 4096 count: 4096.
	self assert: (element uint32At: 37) equals: 0.
	self assert: (element uint32At: 41) equals: 1.
	self assert: (NvGsp checksum: (element copyFrom: 1 to: 48 + 64)) equals: 0.
	self assert: (element copyFrom: 49 to: 48 + 64 + 120) equals: (NvGsp rmAllocClient: root parent: 0 object: root class: 16r41 params: (NvGsp rootParamsClient: root) sequence: 0) bytes.
	self assert: (Machine uint32At: region + 4096 + 16) equals: 1.
	device := transport alloc: NvRm classDevice client: root parent: root params: (NvRm deviceParams: 0 client: root).
	self assert: device equals: 16rCAF00001.
	self assert: (gsp objects at: device) equals: {NvRm classDevice. root}.
	self assert: ((gsp received at: 2) u32At: 24) equals: 1.
	gsp answers at: 16r20800110 put: [:p | p uint32At: 5 put: 16rA04].
	params := NvStruct new: 8.
	transport control: 16r20800110 client: root object: device params: params.
	self assert: (params u32At: 4) equals: 16rA04.
	self assert: ((gsp received at: 3) u32At: 8) equals: 32 + 40 + 8.
	transport free: root client: root parent: 0.
	self assert: gsp objects isEmpty.
	self assert: ((gsp received collect: [:m | m u32At: 12]) asArray) equals: #(103 103 76 10).
	self assert: ((gsp received collect: [:m | m u32At: 24]) asArray) equals: #(0 1 2 3).
	self assert: queues cpuEndpoint readPointer equals: 4
!
testErrors
	| root |
	root := transport alloc: NvRm classRootClient client: 0 parent: 0 params: nil.
	self should: [transport alloc: NvRm classDevice client: root parent: 16r1234 params: nil] raise: NvError.
	self should: [transport free: 16r1234 client: root parent: root] raise: NvError.
	self should: [transport control: NvRm cmdDeviceGetClassList client: root object: root params: (NvRm classListParams: 0 list: 0)] raise: Error.
	self should: [transport mapMemory: 1 client: root device: 2 size: 4096] raise: Error.
	self should: [transport call: (NvGsp rpcFunction: 0 length: 0 sequence: 9)] raise: NvError.
	"The queues are still in step after the errors."
	self assert: (transport alloc: NvRm classDevice client: root parent: root params: nil) > 0
!
testEventsBeforeTheReply
	gsp eventsBefore: 2.
	transport alloc: NvRm classRootClient client: 0 parent: 0 params: nil.
	self assert: transport events size equals: 2.
	self assert: (transport events first u32At: 12) equals: 16r100C
!
testTheRingWraps
	| root params |
	root := transport alloc: NvRm classRootClient client: 0 parent: 0 params: nil.
	gsp answers at: 16r1234 put: [:p | p uint32At: 1 put: (p uint32At: 1) + 1].
	params := NvStruct new: 4.
	1 to: 150 do: [:i | transport control: 16r1234 client: root object: root params: params].
	self assert: (params u32At: 0) equals: 150.
	self assert: (Machine uint32At: region + 4096 + 16) equals: 151 \\ 63
!
testLargeMessages
	| root params |
	root := transport alloc: NvRm classRootClient client: 0 parent: 0 params: nil.
	gsp answers at: 16r1235 put: [:p | p at: 6000 put: 16r5A].
	params := NvStruct new: 6000.
	params u32At: 0 put: 16r12345678.
	transport control: 16r1235 client: root object: root params: params.
	self assert: (params u8At: 5999) equals: 16r5A.
	self assert: (params u32At: 0) equals: 16r12345678.
	self assert: ((Machine bytesAt: region + 4096 + 8192 count: 48) uint32At: 41) equals: 2.
	self should: [transport control: 16r1235 client: root object: root params: (NvStruct new: 70000)] raise: Error
!
testNvDeviceOverGsp
	"NvDevice's open goes over RPC up to the class list, whose parameters point at other memory: step 4. Its failure frees the root client."
	| e |
	e := [NvDevice open: 0 over: transport. nil] on: Error do: [:ex | ex return: ex messageText].
	self assert: (e includesSubstring: 'step 4').
	self assert: ((gsp received collect: [:m | m u32At: 12]) asArray) equals: #(103 76 103 103 10).
	self assert: gsp objects isEmpty
! !
