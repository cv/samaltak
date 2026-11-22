Object subclass: #NvChannel
	instanceVariableNames: 'device group contextShare gpfifo computeObject computeClass ring errors pushBuffer semaphore token entries put pbOffset fenceValue syncedPut rerings'
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
	bytes size + 64 > pushBuffer size ifTrue: [^self error: 'pushbuffer of ', bytes size printString, ' bytes too big'].
	pbOffset + bytes size + 64 > pushBuffer size ifTrue: [self wrapPushBuffer].
	self push: bytes
!
push: bytes
	"Copy bytes into the pushbuffer at pbOffset and queue a GPFIFO entry for them."
	gpfifo isNil ifTrue: [^self error: 'closed channel'].
	put - syncedPut >= (entries - 2) ifTrue: [self drain].
	self pushEntry: bytes
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
ringDoorbell
	"Tell the GPU to look at GPPut."
	Machine barrier.
	Machine uint32At: device doorbell + 16r90 put: token
!
rerings
	"How often a wait rang the doorbell again (wait:timeoutMilliseconds:)."
	^rerings ifNil: [0]
!
wrapPushBuffer
	"Wait until the GPU has run everything in the pushbuffer, then start again at its beginning."
	self drain.
	pbOffset := 0
!
submitBytes: bytes fenceAt: offset
	"Queue pushbuffer words that end with a semaphore release of my semaphore (semaphoreAddress) whose 64-bit payload is at the 0-based byte offset: I write the next fence value there; answer it."
	fenceValue := fenceValue + 1.
	bytes uint32At: offset + 1 put: (fenceValue bitAnd: 16rFFFFFFFF).
	bytes uint32At: offset + 5 put: (fenceValue bitShift: -32).
	self submitBytes: bytes.
	^fenceValue
!
semaphoreAddress
	"The GPU address of the 64-bit word fence values are written to."
	^semaphore gpuAddress
!
submitWithFence: anNvPushBuffer
	"Submit anNvPushBuffer followed by a semaphore release; answer the value it writes."
	fenceValue := fenceValue + 1.
	anNvPushBuffer semaphoreRelease: semaphore gpuAddress payload: fenceValue.
	self submit: anNvPushBuffer.
	^fenceValue
!
fence
	"Submit a semaphore release after the work submitted so far; answer the value it writes."
	^self submitWithFence: NvPushBuffer new
!
wait: value
	self wait: value timeoutMilliseconds: 5000
!
wait: value timeoutMilliseconds: ms
	"Return once the GPU has written a fence value of at least value; error after ms. Polls without pause; while the
	semaphore stands still, rings the doorbell again every 20 µs: on the GB10 a doorbell now and then arrives before
	the GPU sees the GPPut written before it (Machine barrier orders the stores for the CPUs, not for the GPU), and then
	the work waits for the next one (rerings counts them). Real time (Time utcMicroseconds): the image's clock stands still during a frame on the recording clock."
	| deadline last n now seen |
	(semaphore uint64At: 0) >= value ifTrue: [^self].
	last := Time utcMicroseconds.
	deadline := last + (ms * 1000).
	seen := semaphore uint64At: 0.
	n := 0.
	[(semaphore uint64At: 0) >= value] whileFalse: [
		n := n + 1.
		n \\ 16 = 0 ifTrue: [
			now := Time utcMicroseconds.
			now > deadline ifTrue: [
				^self error: 'GPU timeout waiting for fence ', value printString, ' (at ', self completedValue printString,
					'; GPGet ', self gpGet printString, ', GPPut ', self gpPut printString, ')'].
			(semaphore uint64At: 0) = seen
				ifTrue: [now - last >= 20 ifTrue: [
					rerings := (rerings ifNil: [0]) + 1.
					last := now.
					self ringDoorbell]]
				ifFalse: [
					seen := semaphore uint64At: 0.
					last := now]]]
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
