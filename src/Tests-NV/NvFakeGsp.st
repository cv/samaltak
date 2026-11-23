Object subclass: #NvFakeGsp
	instanceVariableNames: 'endpoint objects received answers eventsBefore'
	classVariableNames: ''
	package: 'Tests-NV'!

NvFakeGsp comment: 'I am GSP-RM''s side of the message queues for tests (NvGspTransportTest): I make the status queue''s header as GSP does when it boots, and on each ring of the doorbell read every command message (the queue checks its checksum and sequence number), keep it in received, and answer it on the status queue as GSP-RM would: GSP_RM_ALLOC records the object (an unknown parent: status NV_ERR_INVALID_OBJECT_PARENT), GSP_RM_CONTROL runs the block in answers for its command on the parameters (a ByteArray) if there is one, FREE forgets the object and its children (unknown: NV_ERR_INVALID_OBJECT_HANDLE), anything else gets rpc_result NV_ERR_NOT_SUPPORTED. eventsBefore: n sends n UCODE_LIBOS_PRINT events before each reply.'!

!NvFakeGsp class methodsFor: 'instance creation'!
on: anNvGspQueues
	^self new setEndpoint: anNvGspQueues gspEndpoint
! !

!NvFakeGsp methodsFor: 'initialization'!
setEndpoint: anNvGspEndpoint
	endpoint := anNvGspEndpoint.
	endpoint initializeTransmit: NvGspQueues statusQueueSize.
	objects := Dictionary new.
	received := OrderedCollection new.
	answers := Dictionary new.
	eventsBefore := 0
! !

!NvFakeGsp methodsFor: 'accessing'!
objects
	"handle -> {class. parent}"
	^objects
!
received
	"The RPCs received, as NvStructs."
	^received
!
answers
	"control command -> a block on the parameters' ByteArray"
	^answers
!
eventsBefore: n
	eventsBefore := n
!
endpoint
	^endpoint
! !

!NvFakeGsp methodsFor: 'serving'!
ring
	"The doorbell: answer every message waiting."
	| m |
	[(m := endpoint receive) notNil] whileTrue: [
		received add: m.
		self answer: m]
!
answer: anRpc
	| function reply |
	eventsBefore timesRepeat: [endpoint send: (NvGsp rpcFunction: (NvGsp function: #UCODE_LIBOS_PRINT) length: 0 sequence: 0)].
	function := anRpc u32At: 12.
	reply := NvStruct on: anRpc bytes copy.
	((anRpc u32At: 0) = NvGsp headerVersion and: [(anRpc u32At: 4) = (NvGsp constant: 'NV_VGPU_MSG_SIGNATURE_VALID')])
		ifFalse: [^self reply: reply result: 16r1F].
	function = (NvGsp function: #GSP_RM_ALLOC) ifTrue: [^self reply: reply result: 0 status: (self alloc: reply) at: 32 + 16].
	function = (NvGsp function: #GSP_RM_CONTROL) ifTrue: [^self reply: reply result: 0 status: (self control: reply) at: 32 + 12].
	function = (NvGsp function: #FREE) ifTrue: [^self reply: reply result: 0 status: (self free: reply) at: 32 + 12].
	self reply: reply result: 16r56
!
alloc: anRpc
	| parent |
	parent := anRpc u32At: 32 + 4.
	(parent = 0 or: [objects includesKey: parent]) ifFalse: [^16r1E].
	objects at: (anRpc u32At: 32 + 8) put: {anRpc u32At: 32 + 12. parent}.
	^0
!
control: anRpc
	| n params |
	n := anRpc u32At: 32 + 16.
	answers at: (anRpc u32At: 32 + 8) ifPresent: [:block |
		params := anRpc bytes copyFrom: 73 to: 72 + n.
		block value: params.
		anRpc bytesAt: 72 put: params].
	^0
!
free: anRpc
	| handle |
	handle := anRpc u32At: 32 + 8.
	(objects includesKey: handle) ifFalse: [^16r19].
	self forget: handle.
	^0
!
forget: handle
	(objects keys select: [:h | ((objects at: h) at: 2) = handle]) do: [:child | self forget: child].
	objects removeKey: handle
!
reply: anRpc result: result status: status at: offset
	anRpc u32At: offset put: status.
	self reply: anRpc result: result
!
reply: anRpc result: result
	| length |
	anRpc u32At: 16 put: result; u32At: 20 put: result.
	"Answer as many bytes as the message's entries hold, but no more than fit them (an alloc's parameters lie past its length)."
	length := 48 + (anRpc u32At: 8).
	endpoint send: (NvStruct on: (anRpc bytes copyFrom: 1 to: ((length + 4095 // 4096 * 4096) - 48 min: anRpc size)))
! !
