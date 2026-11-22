Object subclass: #NvCompute
	instanceVariableNames: 'channel device localMemory localPerTpc qmds slotFences nextSlot programs'
	classVariableNames: ''
	package: 'System-NV'!

NvCompute comment: 'I launch compute kernels (NvKernel, from an NvCubin) on an NvChannel: I bind the compute class, give it local memory (the shader stack) and its shared and local memory windows, upload each kernel''s code and constant banks on its first launch, and launch a grid by a QMD (NvQmd, version 5 for Blackwell) with constant bank 0 after it, sent with SEND_PCAS_A.

	NvDevice during: [:gpu | | compute kernel a |
		compute := gpu newCompute.
		kernel := NvTestKernels cubin kernelNamed: ''fill''.
		a := gpu allocate: 4096.
		compute run: kernel grid: 4 block: 256 arguments: {a gpuAddress. 7. 1024}.
		a uint32At: 4092]                                          "7"

launch:grid:block:arguments: is asynchronous and answers the channel''s fence value for it (wait: it); run:... waits. grid and block are an Integer or 1 to 3 Integers; arguments are as NvKernel parameterBytes: takes them (GPU addresses and counts as Integers, Floats). Up to 64 launches are in flight; a 65th waits for the oldest. Constant bank 0 holds what the CUDA driver puts there and the kernel reads: the shared and local memory windows (16r2F0), the shared memory size (16r16C), blockDim (16r360), gridDim (16r370), the stack pointer (16r37C), then the parameters (16r380 on sm_120 and sm_121).

close frees my memory and the channel (or leave it to NvDevice close).'!

!NvCompute methodsFor: 'initialization'!
channel: anNvChannel
	| slm pb |
	channel := anNvChannel.
	device := channel device.
	programs := IdentityDictionary new.
	[qmds := device allocate: 64 * 16r1000.
	slotFences := Array new: 64 withAll: 0.
	nextSlot := 0.
	"Local memory: 16r240 bytes per thread for every warp an SM can hold, as CUDA sizes it at least."
	slm := 16r240.
	localPerTpc := self roundUp: (self roundUp: slm * 32 to: 16r200) * device maxWarpsPerSm * device smsPerTpc to: 16r8000.
	localMemory := device allocate: (self roundUp: localPerTpc * device tpcsPerGpc * device gpcCount to: 16r20000).
	pb := NvPushBuffer new.
	pb method: 0 subchannel: 1 value: channel computeClass.
	pb method: 16r7B0 subchannel: 1 address: self class localWindow.
	pb method: 16r2A0 subchannel: 1 address: self class sharedWindow.
	pb method: 16r790 subchannel: 1 address: localMemory gpuAddress.
	pb method: 16r2E4 subchannel: 1 data: (Array with: (localPerTpc bitShift: -32) with: (localPerTpc bitAnd: 16rFFFFFFFF) with: 16rFF).
	channel submitAndWait: pb]
		ifCurtailed: [self close]
! !

!NvCompute methodsFor: 'accessing'!
channel
	^channel
!
device
	^device
!
localMemory
	^localMemory
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
	| g b program params cbuf slot qmdOffset q pb fence |
	g := self triple: grid.
	b := self triple: block.
	(b inject: 1 into: [:p :x | p * x]) > (aKernel maxThreads ifNil: [1024])
		ifTrue: [^self error: aKernel name, ' allows at most ', (aKernel maxThreads ifNil: [1024]) printString, ' threads per block'].
	((g at: 1) between: 1 and: 16r7FFFFFFF) & ((g at: 2) between: 1 and: 65535) & ((g at: 3) between: 1 and: 65535)
		ifFalse: [^self error: 'bad grid ', g printString].
	(aKernel relocations isEmpty) ifFalse: [^self error: aKernel name, ' has relocations, which I cannot apply'].
	program := self programFor: aKernel.
	params := aKernel parameterBytes: values.
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
	q grid: g block: b.
	q constantBuffer: 0 address: qmds gpuAddress + qmdOffset + 16r200 size: cbuf size.
	qmds bytesAt: qmdOffset put: q bytes.
	qmds bytesAt: qmdOffset + 16r200 put: cbuf.
	pb := NvPushBuffer new.
	pb method: 16r1698 subchannel: 1 value: 16r1011.
	pb method: 16r2B4 subchannel: 1 value: (qmds gpuAddress + qmdOffset bitShift: -8).
	pb method: 16r2C0 subchannel: 1 value: 9.
	fence := channel submitWithFence: pb.
	slotFences at: slot + 1 put: fence.
	^fence
!
programFor: aKernel
	"(code memory, bank index -> memory, QMD template, constant bank 0 template) of aKernel, made on first use; a
	launch copies the templates and fills in its grid, block, parameters and constant bank 0 address."
	^programs at: aKernel ifAbsentPut: [| code banks shared bank0 cbuf smemConfig q |
		code := device allocate: aKernel code size + 16r1000.
		code bytesAt: 0 put: aKernel code.
		banks := Dictionary new.
		aKernel constantBanks keysAndValuesDo: [:index :bytes |
			index > 0 ifTrue: [| m |
				m := device allocate: bytes size.
				m bytesAt: 0 put: bytes.
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
			at: 'shader_local_memory_high_size_shifted4' put: 16r240 // 16;
			at: 'program_prefetch_size' put: (aKernel code size // 256 min: 16r1FF);
			at: 'constant_buffer_invalidate_0' put: 1.
		q programAddress: code gpuAddress.
		banks keysAndValuesDo: [:index :memory |
			q constantBuffer: index address: memory gpuAddress size: (aKernel constantBanks at: index) size].
		Array with: code with: banks with: q bytes with: cbuf]
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
		programs notNil ifTrue: [programs do: [:p | p first free. p second do: [:m | m free]]].
		qmds notNil ifTrue: [qmds free].
		localMemory notNil ifTrue: [localMemory free].
		channel := nil]
! !

!NvCompute class methodsFor: 'constants'!
sharedWindow
	"Where shared memory appears in a kernel''s generic address space (as tinygrad places it)."
	^16r729400000000
!
localWindow
	^16r729300000000
! !
