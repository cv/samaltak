NvTransport subclass: #NvGspTransport
	instanceVariableNames: 'endpoint doorbell sequence nextClient nextObject gpuId events timeoutMs open'
	classVariableNames: ''
	package: 'System-NV'!

NvGspTransport comment: 'I reach GSP-RM over its message queues (docs/nv-gsp.md 3): NvDevice''s alloc, control and free become GSP_RM_ALLOC, GSP_RM_CONTROL and FREE RPCs (NvGsp) carrying the same parameter blocks NvRm builds, sent through an NvGspEndpoint (the CPU side of NvGspQueues); after each I ring the doorbell (a block: on the GB10, writing 0 to NV_PGSP_QUEUE_HEAD(0), BAR0 16r110C00, kgspSetCmdQueueHead_TU102) and poll the status queue for the reply, keeping the events GSP sends meanwhile (events). A reply''s rpc_result or status other than NV_OK signals an NvError.

I pick the handles, as a client RM does: root clients from 16rC1D00001, objects from 16rCAF00001. What the kernel module does itself is not mine yet (docs/nv-gsp.md 3.3, steps 4-6 of cv/samaltak#20): controls whose parameters point at other memory (the class list, GR info) need serialization; memory, VA spaces and mappings need the client side of RM. They signal errors that say so. GSP must be running (booted, GSP_INIT_DONE): booting is step 3.'!

!NvGspTransport class methodsFor: 'instance creation'!
endpoint: anNvGspEndpoint doorbell: aBlock
	^self new setEndpoint: anNvGspEndpoint doorbell: aBlock
! !

!NvGspTransport class methodsFor: 'controls'!
pointerControls
	"Controls NvDevice makes whose parameters hold pointers to other memory: over RPC they need the kernel module's (FINN) serialization, not mine yet."
	^{NvRm cmdDeviceGetClassList. NvRm cmdGrGetInfo}
! !

!NvGspTransport methodsFor: 'initialization'!
setEndpoint: anNvGspEndpoint doorbell: aBlock
	endpoint := anNvGspEndpoint.
	doorbell := aBlock.
	sequence := 0.
	nextClient := 16rC1D00001.
	nextObject := 16rCAF00001.
	gpuId := 0.
	events := OrderedCollection new.
	timeoutMs := 4000
! !

!NvGspTransport methodsFor: 'accessing'!
endpoint
	^endpoint
!
events
	"The events (RPCs GSP sent on its own) received while waiting for replies, oldest first."
	^events
!
gpuId: anInteger
	gpuId := anInteger
!
timeoutMs: anInteger
	"How long to wait for a reply: RM's default GPU timeout is 4 s (osGetTimeoutParams)."
	timeoutMs := anInteger
! !

!NvGspTransport methodsFor: 'opening'!
open
	open := true
!
isOpen
	^open == true
!
attachGpu: index
	index = 0 ifFalse: [^self error: 'GSP transport: one GPU, not number ', index printString].
	^gpuId
!
close
	open := false
! !

!NvGspTransport methodsFor: 'rpc'!
call: anRpc
	"Send anRpc, ring the doorbell, answer GSP's reply (the message with the same function), keeping the events that come before it."
	| function start reply |
	function := anRpc u32At: 12.
	endpoint send: anRpc.
	sequence := sequence + 1.
	doorbell value.
	start := Time millisecondClockValue.
	[reply := endpoint receive.
	reply notNil and: [(reply u32At: 12) = function]] whileFalse: [
		reply isNil
			ifTrue: [
				Time millisecondClockValue - start > timeoutMs ifTrue: [^self error: 'GSP: no reply to RPC ', function printString, ' in ', timeoutMs printString, ' ms'].
				(Delay forMilliseconds: 1) wait]
			ifFalse: [events add: reply]].
	(reply u32At: 16) = 0 ifFalse: [^NvError signal: 'GSP RPC ', function printString status: (reply u32At: 16)].
	^reply
!
newClient
	^nextClient := nextClient + 1
!
newObject
	^nextObject := nextObject + 1
! !

!NvGspTransport methodsFor: 'resource manager'!
alloc: rmClass client: hClient parent: hParent params: anNvStructOrNil
	"GSP_RM_ALLOC: a new root client when hClient is 0 (its NV0000_ALLOC_PARAMETERS made if there are none), else an object of hClient; the parameters come back as GSP left them."
	| handle client params reply status |
	hClient = 0
		ifTrue: [
			handle := nextClient.
			self newClient.
			client := handle.
			params := anNvStructOrNil ifNil: [NvGsp rootParamsClient: handle] ifNotNil: [:p | p bytes]]
		ifFalse: [
			handle := nextObject.
			self newObject.
			client := hClient.
			params := anNvStructOrNil ifNotNil: [:p | p bytes]].
	reply := self call: (NvGsp rmAllocClient: client parent: hParent object: handle class: rmClass params: params sequence: sequence).
	status := reply u32At: 32 + 16.
	status = 0 ifFalse: [^NvError signal: 'RM alloc of class 16r', (rmClass printString: 16) status: status].
	anNvStructOrNil ifNotNil: [:p | p bytesAt: 0 put: (reply bytes copyFrom: 65 to: 64 + p size)].
	^handle
!
control: command client: hClient object: hObject params: anNvStruct
	"GSP_RM_CONTROL with anNvStruct's bytes; answer anNvStruct with GSP's."
	| reply status |
	(self class pointerControls includes: command) ifTrue: [
		^self error: 'GSP transport: control 16r', (command printString: 16), ' points at other memory; its serialization is step 4 (docs/nv-gsp.md)'].
	reply := self call: (NvGsp rmControlClient: hClient object: hObject command: command params: (anNvStruct ifNotNil: [:p | p bytes]) sequence: sequence).
	status := reply u32At: 32 + 12.
	status = 0 ifFalse: [^NvError signal: 'RM control 16r', (command printString: 16) status: status].
	anNvStruct ifNotNil: [:p | p bytesAt: 0 put: (reply bytes copyFrom: 73 to: 72 + p size)].
	^anNvStruct
!
free: hObject client: hClient parent: hParent
	| reply status |
	reply := self call: (NvGsp freeClient: hClient parent: hParent object: hObject sequence: sequence).
	status := reply u32At: 32 + 12.
	status = 0 ifFalse: [^NvError signal: 'RM free' status: status]
! !

!NvGspTransport methodsFor: 'mapping'!
notYet: what
	^self error: 'GSP transport: ', what, ' is the client side of RM, step 5 of cv/samaltak#20 (docs/nv-gsp.md 3.3)'
!
mapMemory: hMemory client: hClient device: hDevice size: size
	^self notYet: 'mapping memory to the CPU'
!
mapUsermode: hUsermode client: hClient device: hDevice size: size
	^self notYet: 'mapping the usermode page'
!
unmapCpu: address size: size
	^self notYet: 'unmapping'
!
mapToGpu: hMemory client: hClient device: hDevice dma: hDma size: size flags: flags
	^self notYet: 'mapping memory for the GPU'
!
unmapFromGpu: hMemory client: hClient device: hDevice dma: hDma gpuAddress: gpuAddress
	^self notYet: 'unmapping memory for the GPU'
! !
