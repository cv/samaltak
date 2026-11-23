TestCase subclass: #NvGspTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-NV'!

NvGspTest comment: 'Tests NvGsp''s builders against what nvidia.ko 580.178.04 writes (docs/nv-gsp.md 2.2-2.4, 3.2; the source lines in each builder): the SEC2 chain-of-trust message, the GSP-FMC boot parameters, GspFwWprMeta, the LIBOS arguments and ids, GSP_ARGUMENTS_CACHED, radix-3 tables, RPC headers and messages, and the queue checksum, field by field at the offsets the compiler gives (NvGspLayoutTest checks those). Needs no GPU.'!

!NvGspTest methodsFor: 'tests'!
testCotMessage
	| payload m |
	payload := NvGsp cotPayloadFmc: 16r123450000 size: 195912 hash: (ByteArray new: 48 withAll: 16rA1) publicKey: (ByteArray new: 384 withAll: 16rB2) signature: (ByteArray new: 384 withAll: 16rC3) bootArgs: 16r123460000.
	self assert: payload size equals: 860.
	self assert: (payload u16At: 0) equals: 1.
	self assert: (payload u16At: 2) equals: 860.
	self assert: (payload u64At: 4) equals: 16r123450000.
	self assert: (payload u64At: 12) equals: 0.
	self assert: (payload u32At: 20) equals: 195912.
	self assert: (payload u64At: 24) equals: 0.
	self assert: (payload u32At: 32) equals: 0.
	self assert: ((payload bytes copyFrom: 37 to: 84) allSatisfy: [:b | b = 16rA1]).
	self assert: ((payload bytes copyFrom: 85 to: 468) allSatisfy: [:b | b = 16rB2]).
	self assert: ((payload bytes copyFrom: 469 to: 852) allSatisfy: [:b | b = 16rC3]).
	self assert: (payload u64At: 852) equals: 16r123460000.
	m := NvGsp sec2Message: payload.
	self assert: m size equals: 868.
	self assert: (m u32At: 0) equals: 1.
	self assert: (m u32At: 4) equals: 16r1410DE7E.
	self assert: (m bytes copyFrom: 9 to: 868) equals: payload bytes.
	self assert: (NvGsp sec2QueueTail: m) equals: 864
!
testFmcBootParameters
	| p |
	p := NvGsp fmcBootParamsWprMeta: 16r200001000 libosArgs: 16r200002000.
	self assert: p size equals: 88.
	self assert: (p u32At: 0) equals: 0.
	self assert: (p u32At: 8) equals: 1.
	self assert: (p u32At: 12) equals: 256.
	self assert: (p u64At: 16) equals: 16r200001000.
	self assert: (p u64At: 24) equals: 0.
	self assert: (p u8At: 36) equals: 1.
	self assert: (p u32At: 40) equals: 1.
	self assert: (p u64At: 48) equals: 16r200002000.
	self assert: ((p bytes copyFrom: 57 to: 88) allSatisfy: [:b | b = 0])
!
testWprMeta
	| desc m |
	desc := (NvGsp struct: 'RM_RISCV_UCODE_DESC') at: 'monitorCodeOffset' put: 16r100; at: 'monitorDataOffset' put: 16r2000; at: 'manifestOffset' put: 16r2F000; at: 'appVersion' put: 7; yourself.
	m := NvGsp wprMetaBootloader: 16r300000000 size: 196608 descriptor: desc radix3: 16r310000000 imageSize: 74985472 signature: 16r320000000 size: 4096 heapSize: 88 * 1048576.
	self assert: m size equals: 256.
	self assert: (m u64At: 0) equals: 16rDC3AAE21371A60B3.
	self assert: (m u64At: 8) equals: 1.
	self assert: (m u64At: 16) equals: 16r310000000.
	self assert: (m u64At: 24) equals: 74985472.
	self assert: (m u64At: 32) equals: 16r300000000.
	self assert: (m u64At: 40) equals: 196608.
	self assert: ((48 to: 64 by: 8) collect: [:o | m u64At: o]) asArray equals: #(16r100 16r2000 16r2F000).
	self assert: (m u64At: 72) equals: 16r320000000.
	self assert: (m u64At: 80) equals: 4096.
	self assert: (m u64At: 128) equals: 88 * 1048576.
	"No FRTS, VGA workspace, non-WPR heap or PMU reservation on GB10B; ACR places WPR2."
	self assert: ((#(88 96 104 112 120 136 144 152 160 168 176 184 192 200) collect: [:o | m u64At: o]) allSatisfy: [:v | v = 0]).
	self assert: (m u32At: 244) equals: 0
!
testLibosArguments
	| r page |
	self assert: (NvGsp initArgId: 'RMARGS') equals: 16r524D41524753.
	self assert: (NvGsp initArgId: 'LOGINIT') equals: 16r4C4F47494E4954.
	self assert: (NvGsp initArgId: 'ABCDEFGHIJ') equals: 16r4142434445464748.
	r := NvGsp libosRegion: 'LOGINIT' address: 16r400000000 size: 16r10000.
	self assert: r size equals: 32.
	self assert: (r u64At: 0) equals: 16r4C4F47494E4954.
	self assert: (r u64At: 8) equals: 16r400000000.
	self assert: (r u64At: 16) equals: 16r10000.
	self assert: (r u8At: 24) equals: 1.
	self assert: (r u8At: 25) equals: 1.
	page := NvGsp libosArguments: {r. NvGsp libosRegion: 'RMARGS' address: 16r400010000 size: 4096}.
	self assert: page size equals: 4096.
	self assert: (page u64At: 32) equals: 16r524D41524753.
	self assert: (page u64At: 64) equals: 0
!
testArguments
	| a |
	a := NvGsp arguments: 16r500000000 pageTableEntries: 129 commandQueue: 4096 statusQueue: 4096 + 16r40000 heap: 16r600000000 size: NvGsp sysmemHeapSize.
	self assert: a size equals: 88.
	self assert: (a u64At: 0) equals: 16r500000000.
	self assert: (a u32At: 8) equals: 129.
	self assert: (a u64At: 16) equals: 4096.
	self assert: (a u64At: 24) equals: 16r41000.
	self assert: (a u64At: 72) equals: 16r600000000.
	self assert: (a u64At: 80) equals: 512 * 1048576
!
testRadix3
	| tables |
	self assert: (NvGsp radix3Counts: 74985472) equals: #(1 1 36 18307).
	self assert: (NvGsp radix3Counts: 1) equals: #(1 1 1 1).
	self assert: (NvGsp radix3Counts: 512 * 4096) equals: #(1 1 1 512).
	self assert: (NvGsp radix3Counts: 512 * 4096 + 1) equals: #(1 1 2 513).
	self should: [NvGsp radix3Counts: 512 * 512 * 512 * 4096 + 1] raise: Error.
	tables := NvGsp radix3Tables: 74985472 pageAddress: [:i | 16r1000000 + (i * 4096)].
	self assert: tables size equals: 38 * 4096.
	self assert: (tables u64At: 0) equals: 16r1000000 + 4096.
	self assert: (tables u64At: 8) equals: 0.
	self assert: ((0 to: 35) collect: [:k | tables u64At: 4096 + (8 * k)]) asArray equals: ((2 to: 37) collect: [:p | 16r1000000 + (p * 4096)]) asArray.
	self assert: (tables u64At: 4096 + (8 * 36)) equals: 0.
	self assert: (tables u64At: 2 * 4096) equals: 16r1000000 + (38 * 4096).
	self assert: (tables u64At: 37 * 4096 + (8 * (18306 \\ 512))) equals: 16r1000000 + ((38 + 18306) * 4096)
!
testRpcMessages
	| m |
	m := NvGsp rmAllocClient: 16rC1D00001 parent: 16rC1D00001 object: 16rCAF00002 class: 16r80 params: #[1 2 3 4 5 6 7 8] sequence: 5.
	self assert: m size equals: 32 + 32 + 8.
	self assert: ((0 to: 28 by: 4) collect: [:o | m u32At: o]) asArray equals: {16r03000000. 16r43505256. 64. 103. 16rFFFFFFFF. 16rFFFFFFFF. 5. 0}.
	self assert: ((32 to: 56 by: 4) collect: [:o | m u32At: o]) asArray equals: {16rC1D00001. 16rC1D00001. 16rCAF00002. 16r80. 0. 8. 0}.
	self assert: (m bytes copyFrom: 65 to: 72) equals: #[1 2 3 4 5 6 7 8].
	m := NvGsp rmControlClient: 16rC1D00001 object: 16rCAF00003 command: 16r20800110 params: (ByteArray new: 12) sequence: 6.
	self assert: m size equals: 32 + 40 + 12.
	self assert: (m u32At: 8) equals: 32 + 40 + 12.
	self assert: (m u32At: 12) equals: 76.
	self assert: ((32 to: 60 by: 4) collect: [:o | m u32At: o]) asArray equals: {16rC1D00001. 16rCAF00003. 16r20800110. 0. 12. 0. 0. 0}.
	m := NvGsp freeClient: 16rC1D00001 parent: 16rC1D00001 object: 16rCAF00003 sequence: 7.
	self assert: m size equals: 48.
	self assert: (m u32At: 8) equals: 48.
	self assert: (m u32At: 12) equals: 10.
	self assert: ((32 to: 44 by: 4) collect: [:o | m u32At: o]) asArray equals: {16rC1D00001. 16rC1D00001. 16rCAF00003. 0}.
	self assert: ((NvGsp rootParamsClient: 16rC1D00009) first: 4) equals: #[16r09 0 16rD0 16rC1].
	self assert: (NvGsp rootParamsClient: 16rC1D00009) size equals: 120
!
testChecksum
	| b |
	b := ByteArray new: 16.
	self assert: (NvGsp checksum: b) equals: 0.
	b uint32At: 1 put: 16r11111111; uint32At: 5 put: 16r22222222; uint32At: 9 put: 16r44444444.
	self assert: (NvGsp checksum: b) equals: (16r11111111 bitXor: (16r22222222 bitXor: 16r44444444)).
	b uint32At: 13 put: (NvGsp checksum: b).
	self assert: (NvGsp checksum: b) equals: 0
! !
