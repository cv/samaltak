Object subclass: #NvChannel
	instanceVariableNames: 'device group contextShare gpfifo computeObject computeClass ring errors pushBuffer semaphore token entries put pbOffset fenceValue syncedPut'
	classVariableNames: ''
	package: 'System-NV'!

NvChannel comment: 'I am a GPU channel: a channel group with one GPFIFO channel in the device''s VA space, the compute class bound to it, and what feeds it:
- ring: the GPFIFO (entries 8-byte entries, each pointing at pushbuffer words) and, at 16r2000 in the same memory, the channel''s USERD, where GPPut (16r8C) tells the GPU how far the ring is filled (GPGet, 16r88, is not kept up to date on the GB10: I wait for a fence before the ring could overflow);
- pushBuffer: 64 KB the pushbuffers I submit are copied into, used as a ring;
- semaphore: a 64-bit word the channel writes fence values to;
- token: the work submit token; writing it to the device''s doorbell (16r90 in the usermode page) makes the GPU look at GPPut.

	c := gpu newChannel.
	pb := NvPushBuffer new.
	pb method: 0 subchannel: 1 value: c computeClass.
	c submit: pb.
	c wait: c fence             "returns once the GPU has run all of it"

submit: is asynchronous; submitWithFence: adds a semaphore release to a pushbuffer and answers its value; fence submits a semaphore release and answers its value, wait: polls for it (an error after a timeout names GPGet and GPPut), sync is both. close waits for the work submitted, then frees the channel''s RM objects and memory (NvDevice close does it for channels left open).'!

!NvChannel methodsFor: 'initialization'!
device: anNvDevice
	device := anNvDevice.
	entries := 1024.
	put := 0.
	syncedPut := 0.
	pbOffset := 0.
	fenceValue := 0.
	[ring := device allocate: 16r3000.
	errors := device allocate: 16r1000.
	pushBuffer := device allocate: 16r10000.
	semaphore := device allocate: 16r1000.
	group := device alloc: NvRm classChannelGroup parent: device device params: (NvRm channelGroupParams: 1).
	contextShare := device alloc: NvRm classContextShare parent: group params: (NvRm contextShareParams: device vaSpace).
	gpfifo := device alloc: (device classFrom: NvRm gpfifoClasses) parent: group
		params: (NvRm gpfifoParams: entries ringAddress: ring gpuAddress ringMemory: ring handle userdMemory: ring handle
			userdOffset: self userdOffset errorNotifier: errors handle contextShare: contextShare).
	computeClass := device classFrom: NvRm computeClasses.
	computeObject := device alloc: computeClass parent: gpfifo params: nil.
	token := (device control: NvRm cmdGpfifoGetWorkSubmitToken object: gpfifo params: NvRm workSubmitTokenParams) u32At: 0.
	device control: NvRm cmdChannelGroupSchedule object: group params: (NvRm scheduleParams: true)]
		ifCurtailed: [self close]
! !

!NvChannel methodsFor: 'accessing'!
device
	^device
!
computeClass
	^computeClass
!
token
	^token
!
userdOffset
	^16r2000
!
gpGet
	^ring uint32At: self userdOffset + 16r88
!
gpPut
	^ring uint32At: self userdOffset + 16r8C
!
completedValue
	"The last fence value the GPU wrote."
	^semaphore uint64At: 0
!
lastFence
	^fenceValue
!
isOpen
	^gpfifo notNil
! !

!NvChannel methodsFor: 'submitting'!
submit: anNvPushBuffer
	"Queue anNvPushBuffer's words for the GPU and ring the doorbell; returns at once."
	anNvPushBuffer isEmpty ifTrue: [^self].
	self submitBytes: anNvPushBuffer bytes
!
submitBytes: bytes
	"Queue pushbuffer words (little-endian, as NvPushBuffer bytes makes them) and ring the doorbell; returns at once."
	self makeRoomFor: bytes size.
	self pushEntry: bytes
!
makeRoomFor: byteCount
	"Room in the pushbuffer and the ring for byteCount more bytes: start the pushbuffer over, or drain the ring, if needed
	(both wait for the GPU, with a fence of their own). Before a fence value is taken for the words: a fence taken
	first would be written after the drain's, the semaphore going back, a wait for it returning early."
	gpfifo isNil ifTrue: [^self error: 'closed channel'].
	byteCount + 64 > pushBuffer size ifTrue: [^self error: 'pushbuffer of ', byteCount printString, ' bytes too big'].
	pbOffset + byteCount + 64 > pushBuffer size ifTrue: [self wrapPushBuffer].
	put - syncedPut >= (entries - 2) ifTrue: [self drain]
!
drain
	"Wait until the GPU has run every entry in the ring (one more entry, a fence, is always free for it)."
	| pb |
	pb := NvPushBuffer new.
	fenceValue := fenceValue + 1.
	pb semaphoreRelease: semaphore gpuAddress payload: fenceValue.
	self pushEntry: pb bytes.
	self wait: fenceValue.
	syncedPut := put
!
pushEntry: bytes
	pushBuffer bytesAt: pbOffset put: bytes.
	ring uint64At: put \\ entries * 8 put: (NvPushBuffer gpfifoEntry: pushBuffer gpuAddress + pbOffset words: bytes size // 4).
	put := put + 1.
	pbOffset := pbOffset + bytes size + 7 // 8 * 8.
	Machine barrier.
	ring uint32At: self userdOffset + 16r8C put: put \\ entries.
	self ringDoorbell
!
errorNotifier
	"What RM wrote to the channel's error notifier (NvNotification): {info32. info16. status}; status 0 while all is well."
	^Array with: (errors uint32At: 8) with: ((errors uint32At: 12) bitAnd: 16rFFFF) with: ((errors uint32At: 12) bitShift: -16)
!
ringDoorbell
	"Tell the GPU to look at GPPut."
	Machine barrier.
	Machine uint32At: device doorbell + 16r90 put: token
!
wrapPushBuffer
	"Wait until the GPU has run everything in the pushbuffer, then start again at its beginning."
	self drain.
	pbOffset := 0
!
submitBytes: bytes fenceAt: offset
	"Queue pushbuffer words that end with a semaphore release of my semaphore (semaphoreAddress) whose 64-bit payload is at the 0-based byte offset: I write the next fence value there; answer it."
	self makeRoomFor: bytes size.
	fenceValue := fenceValue + 1.
	bytes uint32At: offset + 1 put: (fenceValue bitAnd: 16rFFFFFFFF).
	bytes uint32At: offset + 5 put: (fenceValue bitShift: -32).
	self pushEntry: bytes.
	^fenceValue
!
semaphoreAddress
	"The GPU address of the 64-bit word fence values are written to."
	^semaphore gpuAddress
!
flushL2
	"After the work submitted so far, the GPU's L2 writes its dirty lines of system memory back (sysmembar,
	MEM_OP L2_FLUSH_DIRTY, sysmembar): then the CPU sees what kernels wrote to memory allocated gpuCached. Returns at
	once; a fence after it says when."
	self submit: (self l2Operations: #(16r10))
!
flushAndInvalidateL2
	"flushL2, then the L2 drops its lines of system memory (L2_SYSMEM_NCOH_INVALIDATE): then kernels see what the CPU
	wrote to memory allocated gpuCached. UVM's sequence on an integrated GPU (uvm_blackwell_host.c, l2_invalidate)."
	self submit: (self l2Operations: #(16r10 16r11))
!
l2Operations: operations
	"Host MEM_OPs (MEM_OP_D's operation, bits 31:27) between two sysmembars (operation 5, MEM_OP_C 0: SYS_MEMBAR)."
	| pb |
	pb := NvPushBuffer new.
	(#(5), operations, #(5)) do: [:op |
		pb method: 16r28 subchannel: 0 data: (Array with: 0 with: 0 with: 0 with: (op bitShift: 27))].
	^pb
!
timestamp: gpuAddress payload: value
	"Once the work before it is done, the GPU writes value (64 bits) to gpuAddress and its clock (ns, 64 bits) after it (SEM_EXECUTE with RELEASE_TIMESTAMP); no fence, no interrupt."
	| pb |
	pb := NvPushBuffer new.
	pb method: 16r5C subchannel: 0 data: (Array
		with: (gpuAddress bitAnd: 16rFFFFFFFF) with: (gpuAddress bitShift: -32)
		with: (value bitAnd: 16rFFFFFFFF) with: (value bitShift: -32)
		with: (((1 bitOr: (1 bitShift: 20)) bitOr: (1 bitShift: 24)) bitOr: (1 bitShift: 25))).
	self submit: pb
!
submitWithFence: anNvPushBuffer
	"Submit anNvPushBuffer followed by a semaphore release; answer the value it writes."
	| bytes |
	anNvPushBuffer semaphoreRelease: semaphore gpuAddress payload: 0.
	bytes := anNvPushBuffer bytes.
	"its payload: the release's fourth word (header, address low and high, payload); a non-stall interrupt follows (two words)"
	^self submitBytes: bytes fenceAt: bytes size - 20
!
fence
	"Submit a semaphore release after the work submitted so far; answer the value it writes."
	^self submitWithFence: NvPushBuffer new
!
wait: value
	self wait: value timeoutMilliseconds: 5000
!
wait: value timeoutMilliseconds: ms
	"Return once the GPU has written a fence value of at least value; error after ms. Polls without pause, timed by the
	real clock (Time utcMicroseconds): the image's clock stands still during a frame on the recording clock."
	| deadline n |
	(semaphore uint64At: 0) >= value ifTrue: [^self].
	deadline := Time utcMicroseconds + (ms * 1000).
	n := 0.
	[(semaphore uint64At: 0) >= value] whileFalse: [
		n := n + 1.
		(n \\ 256 = 0 and: [Time utcMicroseconds > deadline]) ifTrue: [
			^self error: 'GPU timeout waiting for fence ', value printString, ' (at ', self completedValue printString,
				'; GPGet ', self gpGet printString, ', GPPut ', self gpPut printString, '; error notifier ', self errorNotifier printString, ')']]
!
sync
	"Return once the GPU has run all the work submitted."
	self wait: self fence
!
submitAndWait: anNvPushBuffer
	self submit: anNvPushBuffer.
	self sync
! !

!NvChannel methodsFor: 'closing'!
close
	"Wait (briefly) for the work submitted, then free my RM objects and memory. Safe to call twice."
	group isNil ifTrue: [^self].
	[(gpfifo notNil and: [fenceValue > 0]) ifTrue: [[self wait: fenceValue timeoutMilliseconds: 2000] on: Error do: [:e | ]]]
		ensure: [
			gpfifo notNil ifTrue: [[device free: gpfifo parent: group] on: Error do: [:e | ]].
			contextShare notNil ifTrue: [[device free: contextShare parent: group] on: Error do: [:e | ]].
			[device free: group parent: device device] on: Error do: [:e | ].
			gpfifo := contextShare := group := computeObject := nil.
			{semaphore. pushBuffer. errors. ring} do: [:m | m notNil ifTrue: [[m free] on: Error do: [:e | ]]].
			device forgetChannel: self]
! !
