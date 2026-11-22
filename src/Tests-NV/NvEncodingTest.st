TestCase subclass: #NvEncodingTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-NV'!

NvEncodingTest comment: 'Tests what System-NV encodes without a GPU: NvStruct, the RM parameter blocks of NvRm at the offsets of the C headers of driver 580.178.04 (docs/nv.md), ioctl request numbers, NvPushBuffer''s method headers and GPFIFO entries (as tinygrad''s ops_nv.py makes them), and NvQmd''s bit fields.'!

!NvEncodingTest methodsFor: 'tests'!
testStruct
	| s |
	s := NvStruct new: 24.
	s u64At: 8 put: 16r123456789ABCDEF0.
	self assert: (s u32At: 8) equals: 16r9ABCDEF0.
	self assert: (s u32At: 12) equals: 16r12345678.
	self assert: (s u64At: 8) equals: 16r123456789ABCDEF0.
	s u32At: 0 put: -1.
	self assert: (s u32At: 0) equals: 16rFFFFFFFF.
	self assert: (s s32At: 0) equals: -1.
	s bytesAt: 16 put: 'abc' asByteArray.
	self assert: (s stringAt: 16 size: 8) equals: 'abc'.
	self assert: (s stringAt: 16 size: 2) equals: 'ab'
!
testStructInMachineMemory
	| s address |
	s := (NvStruct new: 16) u64At: 0 put: 42; yourself.
	address := s copyToMachine.
	[Machine uint32At: address + 8 put: 7.
	s readFrom: address.
	self assert: (s u64At: 0) equals: 42.
	self assert: (s u32At: 8) equals: 7.
	self assert: ((NvStruct fromMachine: address size: 16) u32At: 8) equals: 7]
		ensure: [Machine free: address]
!
testRequests
	self assert: (NvRm request: NvRm escRmAlloc size: 32) equals: 16rC020462B.
	self assert: (NvRm request: NvRm escRmControl size: 32) equals: 16rC020462A.
	self assert: (NvRm request: NvRm escRmFree size: 16) equals: 16rC0104629.
	self assert: (NvRm request: NvRm escRmMapMemory size: 56) equals: 16rC038464E.
	self assert: (NvRm request: NvRm escRmMapMemoryDma size: 64) equals: 16rC0404657.
	self assert: (NvRm request: NvRm escCardInfo size: 64 * NvRm cardInfoSize) equals: 16rD20046C8
!
testCallParameters
	| s |
	s := NvRm allocRoot: 1 parent: 2 handle: 3 class: 16r2080 params: 16r123456789 size: 4.
	self assert: s size equals: 32.
	self assert: ((0 to: 12 by: 4) collect: [:o | s u32At: o]) equals: #(1 2 3 16r2080).
	self assert: (s u64At: 16) equals: 16r123456789.
	self assert: (s u32At: 24) equals: 4.
	s := NvRm controlClient: 1 object: 2 command: 16r20801201 params: 16r5000 size: 32.
	self assert: (s u32At: 8) equals: 16r20801201.
	self assert: (s u64At: 16) equals: 16r5000.
	self assert: (s u32At: 24) equals: 32.
	s := NvRm freeRoot: 1 parent: 2 handle: 3.
	self assert: s size equals: 16.
	self assert: (s u32At: 8) equals: 3.
	s := NvRm mapMemoryClient: 1 device: 2 memory: 3 offset: 0 length: 16r10000 flags: 16r1000000 fd: 9.
	self assert: s size equals: 56.
	self assert: (s u64At: 24) equals: 16r10000.
	self assert: (s u32At: 44) equals: 16r1000000.
	self assert: (s u32At: 48) equals: 9.
	s := NvRm mapDmaClient: 1 device: 2 dma: 3 memory: 4 length: 16r2000 flags: NvRm mapDmaFlags.
	self assert: s size equals: 64.
	self assert: (s u32At: 12) equals: 4.
	self assert: (s u64At: 24) equals: 16r2000.
	self assert: (s u32At: 32) equals: 16r110.
	s := NvRm unmapDmaClient: 1 device: 2 dma: 3 memory: 4 gpuAddress: 16r200000000.
	self assert: s size equals: 48.
	self assert: (s u64At: 24) equals: 16r200000000
!
testAllocParameters
	| s |
	s := NvRm deviceParams: 0 client: 16rC1D00001.
	self assert: s size equals: 56.
	self assert: (s u32At: 4) equals: 16rC1D00001.
	self assert: (NvRm subdeviceParams: 0) size equals: 4.
	self assert: (NvRm vaSpaceParams: 0) size equals: 56.
	s := NvRm memoryParams: 16r3000 owner: 7 type: NvRm typeImage alignment: 4096.
	self assert: s size equals: 128.
	self assert: (s u32At: 0) equals: 7.
	self assert: (s u64At: 64) equals: 16r3000.
	self assert: (s u64At: 72) equals: 4096.
	self assert: (s u64At: 88) equals: 16r2FFF.
	self assert: (s u32At: 24) equals: NvRm memoryAttrNoncontiguousPci.
	self assert: (NvRm channelGroupParams: 1) size equals: 20.
	self assert: ((NvRm channelGroupParams: 1) u32At: 12) equals: 1.
	s := NvRm contextShareParams: 5.
	self assert: s size equals: 12.
	self assert: ((0 to: 4 by: 4) collect: [:o | s u32At: o]) equals: #(5 1).
	s := NvRm gpfifoParams: 1024 ringAddress: 16r200000000 ringMemory: 11 userdMemory: 12 userdOffset: 16r2000 errorNotifier: 13 contextShare: 14.
	self assert: s size equals: 368.
	self assert: ((0 to: 4 by: 4) collect: [:o | s u32At: o]) equals: #(13 11).
	self assert: (s u64At: 8) equals: 16r200000000.
	self assert: (s u32At: 16) equals: 1024.
	self assert: (s u32At: 24) equals: 14.
	self assert: (s u32At: 32) equals: 12.
	self assert: (s u64At: 64) equals: 16r2000.
	self assert: (s u32At: 128) equals: 0
!
testControlParameters
	self assert: NvRm buildVersionParams size equals: 1032.
	self assert: (NvRm idInfoParams: 3) size equals: 32.
	self assert: ((NvRm classListParams: 5 list: 16r9000) u64At: 8) equals: 16r9000.
	self assert: (NvRm grInfoParams: 2 list: 16r9000) size equals: 32.
	self assert: (NvRm scheduleParams: true) bytes equals: #[1 0 0].
	self assert: (NvRm workSubmitTokenParams u32At: 0) equals: 16rFFFFFFFF
!
testStatusNames
	self assert: (NvRm statusName: 0) equals: 'NV_OK'.
	self assert: (NvRm statusName: 16r1F) equals: 'NV_ERR_INVALID_ARGUMENT'.
	self assert: (NvRm statusName: 16r51) equals: 'NV_ERR_NO_MEMORY'.
	self assert: (NvRm statusName: 16r56) equals: 'NV_ERR_NOT_SUPPORTED'.
	self assert: (NvRm statusName: 16r8B) equals: 'NV_ERR_DMA_XFER_FAILED'.
	self assert: (NvRm statusName: 16rFFFF) equals: 'NV_ERR_GENERIC'.
	self assert: (NvRm statusName: 16r12345) equals: 'NV status 16r12345'.
	self assert: ([NvError signal: 'alloc' status: 16r22] on: NvError do: [:e | e status]) equals: 16r22.
	self assert: ([NvError signal: 'alloc' status: 16r22] on: NvError do: [:e | e messageText]) equals: 'alloc: NV_ERR_INVALID_CLASS'
!
testPushBuffer
	| pb |
	pb := NvPushBuffer new.
	pb method: 0 subchannel: 1 value: 16rCEC0.
	pb method: 16r2B4 subchannel: 1 value: 16r12345.
	pb method: 16r7B0 subchannel: 1 address: 16r729300000000.
	self assert: pb words equals: #(16r20012000 16rCEC0 16r200120AD 16r12345 16r200221EC 16r7293 0).
	self assert: pb size equals: 7.
	self assert: (pb bytes uint32At: 1) equals: 16r20012000.
	self assert: pb bytes size equals: 28.
	pb reset.
	pb semaphoreRelease: 16r1234567890 payload: 16r100000002.
	self assert: pb words equals: #(16r20050017 16r34567890 16r12 2 1 16r1100001 16r20010008 0).
	self assert: (NvPushBuffer gpfifoEntry: 16r10000 words: 16) equals: ((16r10000 bitOr: (16 bitShift: 42)) bitOr: (1 bitShift: 41))
!
testQmdFields
	| q |
	q := NvQmd new.
	self assert: q bytes size equals: 384.
	q at: 'grid_width' put: 7.
	self assert: (q bytes at: 157) equals: 7.
	q at: 'qmd_major_version' put: 5.
	self assert: (q bytes at: 59) equals: 16r50.
	self assert: (q at: 'qmd_major_version') equals: 5.
	self assert: (q at: 'grid_width') equals: 7.
	self should: [q at: 'grid_height' put: 16r10000] raise: Error.
	self should: [q at: 'no_such_field' put: 1] raise: Error
!
testQmdFieldsAreDisjoint
	"Each field set to all ones sets exactly its own bits."
	| table |
	table := NvQmd fieldTable.
	1 to: table size by: 3 do: [:i | | q width ones |
		q := NvQmd new.
		width := (table at: i + 1) - (table at: i + 2) + 1.
		q at: (table at: i) put: (1 bitShift: width) - 1.
		ones := q bytes inject: 0 into: [:sum :b | sum + ((0 to: 7) inject: 0 into: [:n :bit | n + ((b bitShift: 0 - bit) bitAnd: 1)])].
		self assert: ones equals: width]
!
testQmdLaunch
	| q |
	q := NvQmd new.
	q programAddress: 16r12345678900.
	self assert: (q at: 'program_address_lower_shifted4') equals: 16r34567890.
	self assert: (q at: 'program_address_upper_shifted4') equals: 16r12.
	self assert: (q at: 'program_prefetch_addr_lower_shifted') equals: 16r23456789.
	q constantBuffer: 3 address: 16r2000000040 size: 16r39C.
	self assert: (q at: 'constant_buffer_addr_lower_shifted6_3') equals: 16r80000001.
	self assert: (q at: 'constant_buffer_size_shifted4_3') equals: 16r39C.
	self assert: (q at: 'constant_buffer_valid_3') equals: 1.
	q grid: #(10 2 1) block: #(256 1 1).
	self assert: (q at: 'cta_thread_dimension0') equals: 256.
	self assert: (q at: 'grid_height') equals: 2.
	q release: 0 address: 16r300000000 payload: 9.
	self assert: (q at: 'release_semaphore0_addr_upper') equals: 3.
	self assert: (q at: 'release_semaphore0_payload_lower') equals: 9.
	self assert: (q at: 'release0_enable') equals: 1
! !
