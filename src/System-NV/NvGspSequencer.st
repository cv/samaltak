Object subclass: #NvGspSequencer
	instanceVariableNames: 'registers saved steps timeoutMs'
	classVariableNames: ''
	package: 'System-NV'!

NvGspSequencer comment: 'I run a CPU sequencer buffer GSP-RM sends (GSP_RUN_CPU_SEQUENCER: rpc_run_cpu_sequencer_v17_00, a list of 32-bit words: an opcode then its payload) the way kgspExecuteSequencerBuffer_IMPL does (kernel_gsp.c 5297-5438; rmgspseq.h): REG_WRITE (address, value), REG_MODIFY (address, mask, value: clear the mask, or the value), REG_POLL (address, mask, value, timeout in us (0: the default 4 s), error code), DELAY_US, REG_STORE (address, index into the 8-word save area). The falcon operations (CORE_RESET, CORE_START, CORE_WAIT_FOR_HALT, CORE_RESUME) are not mine yet: they signal an error that names them. GSP-RM gets no reply (and nvidia.ko keeps the save area to itself).

registers answers read32: and sequencerWrite32:value: (NvBar0: its writes are recorded and, in a dry run, not made).'!

!NvGspSequencer class methodsFor: 'instance creation'!
on: aRegisters
	^self new setRegisters: aRegisters
! !

!NvGspSequencer methodsFor: 'initialization'!
setRegisters: aRegisters
	registers := aRegisters.
	saved := Array new: (NvGsp constant: 'GSP_SEQ_BUF_REG_SAVE_SIZE') withAll: 0.
	steps := 0.
	timeoutMs := 4000
! !

!NvGspSequencer methodsFor: 'accessing'!
saved
	"The REG_STORE save area."
	^saved
!
steps
	"Commands run."
	^steps
! !

!NvGspSequencer methodsFor: 'running'!
run: anRpc
	"Run the buffer of a GSP_RUN_CPU_SEQUENCER event (its RPC: the header, then rpc_run_cpu_sequencer_v17_00)."
	| size end words i |
	size := anRpc u32At: 32.
	end := anRpc u32At: 36.
	size = 0 ifTrue: [^self error: 'CPU sequencer: empty buffer'].
	end < size ifFalse: [^self error: 'CPU sequencer: command index ', end printString, ' past the buffer of ', size printString].
	words := (0 to: end - 1) collect: [:k | anRpc u32At: 72 + (4 * k)].
	i := 1.
	[i <= end] whileTrue: [| op n payload |
		op := words at: i.
		n := self payloadSize: op.
		i + n > end ifTrue: [^self error: 'CPU sequencer: opcode ', op printString, ' runs past the buffer'].
		payload := words copyFrom: i + 1 to: i + n.
		self perform: op payload: payload.
		steps := steps + 1.
		i := i + 1 + n]
!
payloadSize: op
	"GSP_SEQUENCER_PAYLOAD_SIZE_DWORDS (rmgspseq.h)."
	^#(2 3 5 1 2) at: op + 1 ifAbsent: [0]
!
perform: op payload: p
	op = 0 ifTrue: [^registers sequencerWrite32: (p at: 1) value: (p at: 2)].
	op = 1 ifTrue: [^registers sequencerWrite32: (p at: 1) value: (((registers read32: (p at: 1)) bitAnd: (16rFFFFFFFF bitXor: (p at: 2))) bitOr: (p at: 3))].
	op = 2 ifTrue: [^self poll: p].
	op = 3 ifTrue: [^(Delay forMilliseconds: (p at: 1) + 999 // 1000) wait].
	op = 4 ifTrue: [
		((p at: 2) between: 0 and: saved size - 1) ifFalse: [^self error: 'CPU sequencer: REG_STORE index ', (p at: 2) printString].
		^saved at: (p at: 2) + 1 put: (registers read32: (p at: 1))].
	^self error: 'CPU sequencer: ', (#('CORE_RESET' 'CORE_START' 'CORE_WAIT_FOR_HALT' 'CORE_RESUME') at: op - 4 ifAbsent: ['opcode ', op printString]), ' is not implemented here yet'
!
poll: p
	"REG_POLL: until (value & mask) = val, at most the payload's timeout (us; 0: the default), else an error with its error code."
	| start limit v |
	start := Time millisecondClockValue.
	limit := (p at: 4) = 0 ifTrue: [timeoutMs] ifFalse: [(p at: 4) + 999 // 1000].
	[((v := registers read32: (p at: 1)) bitAnd: (p at: 2)) = (p at: 3)] whileFalse: [
		Time millisecondClockValue - start > limit ifTrue: [
			^self error: 'CPU sequencer: REG_POLL of 16r', ((p at: 1) printString: 16), ' timed out (value 16r', (v printString: 16), ', error ', (p at: 5) printString, ')'].
		(Delay forMilliseconds: 1) wait]
! !
