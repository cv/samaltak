TestCase subclass: #NvGspSequencerTest
	instanceVariableNames: 'gpu'
	classVariableNames: ''
	package: 'Tests-NV'!

NvGspSequencerTest comment: 'Tests NvGspSequencer on buffers as GSP-RM sends them (rpc_run_cpu_sequencer_v17_00 in a GSP_RUN_CPU_SEQUENCER RPC), against NvFakeGb10''s registers: each opcode''s effect, the save area, a poll that times out with its error code, the falcon operations that are not here, and buffers that run past their end. Needs no GPU.'!

!NvGspSequencerTest class methodsFor: 'fixtures'!
rpc: words
	"The event GSP-RM sends with words as its command buffer."
	| p |
	p := NvStruct new: 40 + (4 * words size).
	p u32At: 0 put: words size + 1; u32At: 4 put: words size.
	words doWithIndex: [:w :i | p u32At: 40 + (4 * (i - 1)) put: w].
	^NvGsp rpc: (NvGsp function: #GSP_RUN_CPU_SEQUENCER) payload: p counted: 0 params: nil sequence: 0
! !

!NvGspSequencerTest methodsFor: 'running'!
setUp
	gpu := NvFakeGb10 memory: nil firmware: nil
!
run: words
	^(NvGspSequencer on: gpu) run: (self class rpc: words); yourself
! !

!NvGspSequencerTest methodsFor: 'tests'!
testOpcodes
	| s |
	gpu others at: 16r200 put: 16rFF00FF00; at: 16r300 put: 16r5.
	s := self run: #(0 16r100 16r12345678  1 16r200 16r0000FF00 16r00001200  2 16r300 16r7 16r5 1000 9  3 10  4 16r100 3).
	self assert: (gpu others at: 16r100) equals: 16r12345678.
	self assert: (gpu others at: 16r200) equals: 16rFF001200.
	self assert: (s saved at: 4) equals: 16r12345678.
	self assert: s steps equals: 5.
	self assert: (gpu writes collect: [:w | w key]) asArray equals: #(16r100 16r200)
!
testModify
	gpu others at: 16r200 put: 16rFF00FF00.
	self run: #(1 16r200 16r0000FF00 16r00001200).
	self assert: (gpu others at: 16r200) equals: 16rFF001200
!
testPollTimesOut
	| e |
	gpu others at: 16r300 put: 0.
	e := [self run: #(2 16r300 1 1 2000 77). nil] on: Error do: [:ex | ex return: ex messageText].
	self assert: (e includesSubstring: 'REG_POLL of 16r300 timed out').
	self assert: (e includesSubstring: 'error 77')
!
testWhatIsNotHere
	| e |
	e := [self run: #(5). nil] on: Error do: [:ex | ex return: ex messageText].
	self assert: (e includesSubstring: 'CORE_RESET is not implemented').
	self should: [self run: #(0 16r100)] raise: Error.
	self should: [self run: #(4 16r100 8)] raise: Error.
	self assert: gpu writes isEmpty
! !
