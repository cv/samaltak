Object subclass: #NvCompute
	instanceVariableNames: 'channel device localMemory localPerTpc localPerThread qmds slotFences nextSlot programs launchWords qmdWord payloadOffset'
	classVariableNames: 'LaunchFields'
	package: 'System-NV'!

NvCompute comment: 'I launch compute kernels (NvKernel, from an NvCubin) on an NvChannel: I bind the compute class, give it local memory (the shader stack) and its shared and local memory windows, upload each kernel''s code and constant banks on its first launch, and launch a grid by a QMD (NvQmd, version 5 for Blackwell) with constant bank 0 after it, sent with SEND_PCAS_A.

	NvDevice during: [:gpu | | compute kernel a |
		compute := gpu newCompute.
		kernel := NvTestKernels cubin kernelNamed: ''fill''.
		a := gpu allocate: 4096.
		compute run: kernel grid: 4 block: 256 arguments: {a gpuAddress. 7. 1024}.
		a uint32At: 4092]                                          "7"

launch:grid:block:arguments: is asynchronous and answers the channel''s fence value for it (wait: it); run:... waits; launch:grid:block:parameters: takes the parameter area as bytes (a struct by value). A launch copies the kernel''s QMD and constant bank 0 templates, patches the grid, the block, the bank''s address and the parameters into them at offsets found once, and submits a pushbuffer made once (its QMD address and fence value patched). grid and block are an Integer or 1 to 3 Integers; arguments are as NvKernel parameterBytes: takes them (GPU addresses and counts as Integers, Floats). Up to 64 launches are in flight; a 65th waits for the oldest. Constant bank 0 holds what the CUDA driver puts there and the kernel reads: the shared and local memory windows (16r2F0), the shared memory size (16r16C), blockDim (16r360), gridDim (16r370), the stack pointer (16r37C), then the parameters (16r380 on sm_120 and sm_121).

close frees my memory and the channel (or leave it to NvDevice close).'!

!NvCompute methodsFor: 'initialization'!
channel: anNvChannel
	| pb |
	channel := anNvChannel.
	device := channel device.
	programs := IdentityDictionary new.
	[qmds := device allocate: 64 * 16r1000.
	slotFences := Array new: 64 withAll: 0.
	nextSlot := 0.
	pb := NvPushBuffer new.
	pb method: 0 subchannel: 1 value: channel computeClass.
	pb method: 16r7B0 subchannel: 1 address: self class localWindow.
	pb method: 16r2A0 subchannel: 1 address: self class sharedWindow.
	channel submitAndWait: pb.
	self localMemoryPerThread: 16r240.
	"A launch's pushbuffer: send the QMD (its address >> 8 at qmdWord), schedule it, then the fence (its payload at
	payloadOffset; no interrupt: waits poll). The shader caches are invalidated when a kernel's code arrives
	(programFor:), the QMD invalidates constant bank 0."
	pb := NvPushBuffer new.
	pb method: 16r2B4 subchannel: 1 value: 0.
	qmdWord := pb size - 1 * 4 + 1.
	pb method: 16r2C0 subchannel: 1 value: 9.
	payloadOffset := pb size + 3 * 4.
	pb semaphoreRelease: channel semaphoreAddress payload: 0.
	launchWords := pb bytes copyFrom: 1 to: pb bytes size - 8]
		ifCurtailed: [self close]
! !

!NvCompute methodsFor: 'accessing'!
channel
	^channel
!
localPerThread
	"The local memory each thread has (bytes): what the kernels launched so far need, at least 16r240."
	^localPerThread
!
device
	^device
!
localMemory
	^localMemory
!
programs
	"aKernel -> what launching it took (code, banks, templates, data), for the kernels launched and not forgotten."
	^programs
! !

!NvCompute methodsFor: 'launching'!
run: aKernel grid: grid block: block arguments: values
	"Launch and wait until the grid has run."
	channel wait: (self launch: aKernel grid: grid block: block arguments: values)
!
wait: aFence
	channel wait: aFence
!
launch: aKernel grid: grid block: block arguments: values
	"Queue a launch of aKernel; answer its fence value."
	^self launch: aKernel grid: grid block: block parameters: (aKernel parameterBytes: values)
!
launch: aKernel grid: grid block: block parameters: params
	"Queue a launch of aKernel with params as its parameter area (parameterBytes:'s bytes); answer its fence value."
	| g b program cbuf slot qmdOffset q fence |
	g := self triple: grid.
	b := self triple: block.
	(b inject: 1 into: [:p :x | p * x]) > (aKernel maxThreads ifNil: [1024])
		ifTrue: [^self error: aKernel name, ' allows at most ', (aKernel maxThreads ifNil: [1024]) printString, ' threads per block'].
	((g at: 1) between: 1 and: 16r7FFFFFFF) & ((g at: 2) between: 1 and: 65535) & ((g at: 3) between: 1 and: 65535)
		ifFalse: [^self error: 'bad grid ', g printString].
	(aKernel relocations isEmpty) ifFalse: [^self error: aKernel name, ' has relocations, which I cannot apply'].
	program := self programFor: aKernel.
	params size > aKernel parameterSize ifTrue: [^self error: aKernel name, ' takes ', aKernel parameterSize printString, ' bytes of parameters'].
	cbuf := (program at: 4) copy.
	1 to: 3 do: [:i |
		cbuf uint32At: 16r360 + (i * 4) - 3 put: (b at: i).
		cbuf uint32At: 16r370 + (i * 4) - 3 put: (g at: i)].
	cbuf replaceFrom: aKernel parameterOffset + 1 to: aKernel parameterOffset + params size with: params startingAt: 1.
	slot := nextSlot.
	nextSlot := nextSlot + 1 \\ slotFences size.
	channel wait: (slotFences at: slot + 1).
	qmdOffset := slot * 16r1000.
	q := NvQmd fromBytes: (program at: 3) copy.
	self qmd: q grid: g block: b bank0: qmds gpuAddress + qmdOffset + 16r200.
	qmds bytesAt: qmdOffset put: q bytes.
	qmds bytesAt: qmdOffset + 16r200 put: cbuf.
	launchWords uint32At: qmdWord put: (qmds gpuAddress + qmdOffset bitShift: -8).
	fence := channel submitBytes: launchWords fenceAt: payloadOffset.
	slotFences at: slot + 1 put: fence.
	^fence
!
qmd: q grid: g block: b bank0: address
	"Patch a QMD template (its constant bank 0 size and valid bit set already) for a launch."
	| f |
	f := self class launchFields.
	1 to: 3 do: [:i |
		q bitsFrom: ((f at: i) at: 2) to: ((f at: i) at: 1) put: (g at: i).
		q bitsFrom: ((f at: i + 3) at: 2) to: ((f at: i + 3) at: 1) put: (b at: i)].
	q bitsFrom: ((f at: 7) at: 2) to: ((f at: 7) at: 1) put: ((address bitShift: -6) bitAnd: 16rFFFFFFFF).
	q bitsFrom: ((f at: 8) at: 2) to: ((f at: 8) at: 1) put: (address bitShift: -38)
!
programFor: aKernel
	"(code memory, bank index -> memory, QMD template, constant bank 0 template) of aKernel, made on first use; a
	launch copies the templates and fills in its grid, block, parameters and constant bank 0 address."
	^programs at: aKernel ifAbsentPut: [| code banks shared bank0 cbuf smemConfig q pb slm data |
		code := device allocate: aKernel code size + 16r1000.
		code bytesAt: 0 put: aKernel code.
		banks := Dictionary new.
		data := OrderedCollection new.
		aKernel constantBanks keysAndValuesDo: [:index :bytes |
			index > 0 ifTrue: [| m |
				m := device allocate: bytes size.
				m bytesAt: 0 put: (self bank: index of: aKernel data: data).
				banks at: index put: m]].
		shared := self roundUp: 16r400 + aKernel sharedSize to: 128.
		bank0 := aKernel constantBanks at: 0 ifAbsent: [ByteArray new].
		cbuf := ByteArray new: (self roundUp: ((bank0 size max: aKernel parameterOffset + aKernel parameterSize) max: 16r380) to: 16).
		cbuf size > 16rE00 ifTrue: [^self error: 'constant bank 0 of ', cbuf size printString, ' bytes too big'].
		cbuf replaceFrom: 1 to: bank0 size with: bank0 startingAt: 1.
		cbuf uint32At: 16r16C + 1 put: shared.
		cbuf uint32At: 16r2F0 + 1 put: (self class sharedWindow bitAnd: 16rFFFFFFFF).
		cbuf uint32At: 16r2F4 + 1 put: (self class sharedWindow bitShift: -32).
		cbuf uint32At: 16r2F8 + 1 put: (self class localWindow bitAnd: 16rFFFFFFFF).
		cbuf uint32At: 16r2FC + 1 put: (self class localWindow bitShift: -32).
		"The stack starts 16r240 below the top of a thread's local window and grows down into its frame: the
		thread's local memory must hold both (shader_local_memory_high_size)."
		slm := self localMemoryFor: aKernel.
		slm > localPerThread ifTrue: [self localMemoryPerThread: slm].
		cbuf uint32At: 16r37C + 1 put: 16rFFFDC0.
		smemConfig := ((#(32 64 100) detect: [:kb | kb * 1024 >= shared] ifNone: [^self error: 'too much shared memory']) * 1024) // 4096 + 1.
		q := NvQmd new.
		q at: 'qmd_group_id' put: 16r3F; at: 'qmd_type' put: 2; at: 'qmd_major_version' put: 5;
			at: 'sass_version' put: device sassVersion; at: 'api_visible_call_limit' put: 1; at: 'sampler_index' put: 1;
			at: 'invalidate_texture_header_cache' put: 1; at: 'invalidate_texture_sampler_cache' put: 1;
			at: 'invalidate_texture_data_cache' put: 1; at: 'invalidate_shader_data_cache' put: 1;
			at: 'cwd_membar_type' put: 1; at: 'register_count' put: aKernel registerCount; at: 'barrier_count' put: 1;
			at: 'shared_memory_size_shifted7' put: shared // 128;
			at: 'min_sm_config_shared_mem_size' put: smemConfig; at: 'target_sm_config_shared_mem_size' put: smemConfig;
			at: 'max_sm_config_shared_mem_size' put: 16r1A;
			at: 'shader_local_memory_high_size_shifted4' put: slm // 16;
			at: 'program_prefetch_size' put: (aKernel code size // 256 min: 16r1FF);
			at: 'constant_buffer_invalidate_0' put: 1.
		pb := NvPushBuffer new.
		pb method: 16r1698 subchannel: 1 value: 16r1011.
		channel submit: pb.
		q programAddress: code gpuAddress.
		q at: 'constant_buffer_size_shifted4_0' put: cbuf size; at: 'constant_buffer_valid_0' put: 1.
		banks keysAndValuesDo: [:index :memory |
			q constantBuffer: index address: memory gpuAddress size: (aKernel constantBanks at: index) size].
		Array with: code with: banks with: q bytes with: cbuf with: data]
!
bank: index of: aKernel data: aCollection
	"Constant bank index of aKernel with the addresses of its global data written in; the data goes into GPU memory of its own, added to aCollection."
	| bytes relocs memories |
	bytes := (aKernel constantBanks at: index) copy.
	relocs := aKernel bankRelocations select: [:r | r first = index].
	memories := Dictionary new.
	relocs do: [:r | | m address |
		(r at: 5) = 2 ifFalse: [^self error: aKernel name, ': a constant bank relocation of type ', (r at: 5) printString, ', which I cannot apply'].
		m := memories at: (r at: 3) ifAbsentPut: [| g |
			g := aKernel globals at: (r at: 3).
			aCollection add: (device allocate: (g size max: 16)).
			aCollection last bytesAt: 0 put: g.
			aCollection last].
		address := m gpuAddress + (r at: 4).
		bytes uint32At: (r at: 2) + 1 put: (address bitAnd: 16rFFFFFFFF).
		bytes uint32At: (r at: 2) + 5 put: (address bitShift: -32)].
	^bytes
!
forget: aKernel
	"Free what launching aKernel took (its code, banks and data), once the GPU has run everything submitted."
	| p |
	p := programs removeKey: aKernel ifAbsent: [^self].
	channel sync.
	self freeProgram: p
!
freeProgram: p
	p first free.
	(p at: 2) do: [:m | m free].
	(p at: 5) do: [:m | m free]
!
localMemoryFor: aKernel
	"A thread's local memory for aKernel: the 16r240 bytes above the stack pointer and its stack frame, in 32s."
	^self roundUp: 16r240 + (aKernel frameSize max: aKernel minStackSize) to: 32
!
localMemoryPerThread: bytes
	"Give every thread bytes of local memory (sized as CUDA does: bytes for each thread of every warp an SM can hold).
	The memory there was goes once the GPU has run all the work submitted: what was launched may use it."
	| perTpc memory pb |
	perTpc := self roundUp: (self roundUp: bytes * 32 to: 16r200) * device maxWarpsPerSm * device smsPerTpc to: 16r8000.
	memory := device allocate: (self roundUp: perTpc * device tpcsPerGpc * device gpcCount to: 16r20000).
	pb := NvPushBuffer new.
	pb method: 16r790 subchannel: 1 address: memory gpuAddress.
	pb method: 16r2E4 subchannel: 1 data: (Array with: (perTpc bitShift: -32) with: (perTpc bitAnd: 16rFFFFFFFF) with: 16rFF).
	channel submitAndWait: pb.
	localMemory isNil ifFalse: [localMemory free].
	localMemory := memory.
	localPerTpc := perTpc.
	localPerThread := bytes
!
triple: anIntegerOrArray
	| t |
	anIntegerOrArray isInteger ifTrue: [^Array with: anIntegerOrArray with: 1 with: 1].
	(anIntegerOrArray size between: 1 and: 3) ifFalse: [^self error: 'grid and block take 1 to 3 dimensions'].
	t := Array new: 3 withAll: 1.
	t replaceFrom: 1 to: anIntegerOrArray size with: anIntegerOrArray startingAt: 1.
	^t
!
roundUp: n to: m
	^n + m - 1 // m * m
! !

!NvCompute methodsFor: 'closing'!
close
	"Wait for my launches, free my memory and my channel."
	channel isNil ifTrue: [^self].
	[channel close] ensure: [
		programs notNil ifTrue: [programs do: [:p | self freeProgram: p]].
		qmds notNil ifTrue: [qmds free].
		localMemory notNil ifTrue: [localMemory free].
		channel := nil]
! !

!NvCompute class methodsFor: 'constants'!
launchFields
	"(hi lo) of the QMD fields a launch sets: grid (3), block (3), constant bank 0's address (lower, upper)."
	^LaunchFields ifNil: [LaunchFields := #('grid_width' 'grid_height' 'grid_depth' 'cta_thread_dimension0' 'cta_thread_dimension1' 'cta_thread_dimension2' 'constant_buffer_addr_lower_shifted6_0' 'constant_buffer_addr_upper_shifted6_0') collect: [:n | NvQmd field: n]]
!
sharedWindow
	"Where shared memory appears in a kernel''s generic address space (as tinygrad places it)."
	^16r729400000000
!
localWindow
	^16r729300000000
! !
