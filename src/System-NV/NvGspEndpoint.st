Object subclass: #NvGspEndpoint
	instanceVariableNames: 'tx rx txSequence rxSequence'
	classVariableNames: ''
	package: 'System-NV'!

NvGspEndpoint comment: 'I am one side of GSP''s message queues (NvGspQueues): I send RPC messages on my transmit queue and receive them from my receive queue, as GspMsgQueueSendCommand and GspMsgQueueReceiveStatus do (message_queue_cpu.c 469-760) over the msgq library (msgq.c). Both queues are msgq rings in Machine memory at tx and rx. The two sides swap read pointers (MSGQ_FLAGS_SWAP_RX): my read pointer of rx lives in my own queue''s msgqRxHeader (tx + rxHdrOff), the other side''s read pointer of my queue in its (rx + rxHdrOff).

A message travels as GSP_MSG_QUEUE_ELEMENTs: a 48-byte header (checksum, sequence number, the count of 4 KB entries it spans), then the RPC (an rpc_message_header_v03_00 and its payload); its length is the header''s 48 bytes and the RPC''s length field, zero-padded to 8; the checksum makes the XOR of those bytes 0 (NvGsp checksum:). receive answers the RPC (as many bytes as its entries hold: GSP_RM_ALLOC''s parameters lie past its length) or nil when nothing waits.'!

!NvGspEndpoint class methodsFor: 'instance creation'!
transmit: txAddress receive: rxAddress
	^self new setTransmit: txAddress receive: rxAddress
! !

!NvGspEndpoint class methodsFor: 'constants'!
elementHeaderSize
	"GSP_MSG_QUEUE_ELEMENT_HDR_SIZE: offsetof(GSP_MSG_QUEUE_ELEMENT, rpc)."
	^(NvGsp layout: 'GSP_MSG_QUEUE_ELEMENT') offsetOf: 'rpc'
!
entrySize
	^NvGsp constant: 'GSP_MSG_QUEUE_ELEMENT_SIZE_MIN'
!
maxMessageSize
	^NvGsp constant: 'GSP_MSG_QUEUE_ELEMENT_SIZE_MAX'
! !

!NvGspEndpoint methodsFor: 'initialization'!
setTransmit: txAddress receive: rxAddress
	tx := txAddress.
	rx := rxAddress.
	txSequence := 0.
	rxSequence := 0
!
initializeTransmit: size
	"My queue's msgqTxHeader as msgqTxCreate writes it (msgq.c 188-245: header alignment 16, entries 4 KB-aligned, MSGQ_FLAGS_SWAP_RX), and my read pointer 0."
	| header entryOff |
	header := NvGsp struct: 'msgqTxHeader'.
	entryOff := (header size + 15 // 16 * 16) + 4 + self class entrySize - 1 // self class entrySize * self class entrySize.
	header at: 'version' put: (NvGsp constant: 'MSGQ_VERSION');
		at: 'size' put: size;
		at: 'msgSize' put: self class entrySize;
		at: 'msgCount' put: size - entryOff // self class entrySize;
		at: 'writePtr' put: 0;
		at: 'flags' put: (NvGsp constant: 'MSGQ_FLAGS_SWAP_RX');
		at: 'rxHdrOff' put: (header size + 15 // 16 * 16);
		at: 'entryOff' put: entryOff.
	Machine bytesAt: tx put: header bytes.
	Machine uint32At: tx + (header at: 'rxHdrOff') put: 0
! !

!NvGspEndpoint methodsFor: 'accessing'!
transmitAddress
	^tx
!
receiveAddress
	^rx
!
txSequence
	^txSequence
!
rxSequence
	^rxSequence
!
headerOf: queueAddress at: aName
	^Machine uint32At: queueAddress + ((NvGsp layout: 'msgqTxHeader') offsetOf: aName)
!
isLinked
	"Has the other side made its queue (a valid msgqTxHeader: msgqRxLink's checks, msgq.c 331-370)?"
	| size |
	size := self headerOf: rx at: 'size'.
	^(self headerOf: rx at: 'version') = (NvGsp constant: 'MSGQ_VERSION')
		and: [(self headerOf: rx at: 'msgSize') = self class entrySize
		and: [size > 0
		and: [(self headerOf: rx at: 'msgCount') = (size - (self headerOf: rx at: 'entryOff') // self class entrySize)
		and: [(self headerOf: rx at: 'msgCount') > 0]]]]
!
freeEntries
	"Entries I can write: one stays empty, so a full ring differs from an empty one."
	| count theirRead |
	count := self headerOf: tx at: 'msgCount'.
	theirRead := Machine uint32At: rx + (self headerOf: rx at: 'rxHdrOff').
	^(theirRead - (self headerOf: tx at: 'writePtr') - 1) \\ count
!
availableEntries
	"Entries the other side wrote that I have not read."
	| count |
	self isLinked ifFalse: [^0].
	count := self headerOf: rx at: 'msgCount'.
	^((self headerOf: rx at: 'writePtr') - self readPointer) \\ count
!
readPointer
	^Machine uint32At: tx + (self headerOf: tx at: 'rxHdrOff')
! !

!NvGspEndpoint methodsFor: 'sending'!
send: anRpc
	"Put anRpc (an NvStruct: rpc header and payload) on my queue as one message; answer how many entries it took."
	| rpc length elements message count write entryOff |
	rpc := anRpc bytes.
	length := self class elementHeaderSize + (rpc uint32At: 9).
	(length > self class maxMessageSize) ifTrue: [^self error: 'GSP message of ', length printString, ' bytes: larger ones go as continuation records'].
	elements := length + self class entrySize - 1 // self class entrySize.
	self class elementHeaderSize + rpc size > (elements * self class entrySize)
		ifTrue: [^self error: 'GSP message: ', rpc size printString, ' bytes would not fit the ', elements printString, ' entries its length gives'].
	message := ByteArray new: elements * self class entrySize.
	message replaceFrom: self class elementHeaderSize + 1 to: self class elementHeaderSize + rpc size with: rpc startingAt: 1.
	message uint32At: 37 put: txSequence; uint32At: 41 put: elements.
	message uint32At: 33 put: (NvGsp checksum: (message copyFrom: 1 to: length + 7 // 8 * 8)).
	self freeEntries < elements ifTrue: [^self error: 'GSP command queue full: ', self freeEntries printString, ' free entries for ', elements printString].
	count := self headerOf: tx at: 'msgCount'.
	write := self headerOf: tx at: 'writePtr'.
	entryOff := self headerOf: tx at: 'entryOff'.
	0 to: elements - 1 do: [:i |
		Machine bytesAt: tx + entryOff + ((write + i \\ count) * self class entrySize)
			put: (message copyFrom: i * self class entrySize + 1 to: i + 1 * self class entrySize)].
	Machine uint32At: tx + ((NvGsp layout: 'msgqTxHeader') offsetOf: 'writePtr') put: write + elements \\ count.
	txSequence := txSequence + 1.
	^elements
! !

!NvGspEndpoint methodsFor: 'receiving'!
receive
	"The next message's RPC (an NvStruct of its entries' bytes after the element header), or nil if none waits. Signals an error on a bad checksum or sequence number."
	| count read entryOff first elements message length rpc |
	self availableEntries = 0 ifTrue: [^nil].
	count := self headerOf: rx at: 'msgCount'.
	read := self readPointer.
	entryOff := self headerOf: rx at: 'entryOff'.
	first := Machine bytesAt: rx + entryOff + (read * self class entrySize) count: self class entrySize.
	elements := first uint32At: 41.
	(elements between: 1 and: self availableEntries) ifFalse: [^self error: 'GSP message spans ', elements printString, ' entries, ', self availableEntries printString, ' written'].
	message := ByteArray new: elements * self class entrySize.
	0 to: elements - 1 do: [:i |
		message replaceFrom: i * self class entrySize + 1 to: i + 1 * self class entrySize
			with: (Machine bytesAt: rx + entryOff + ((read + i \\ count) * self class entrySize) count: self class entrySize) startingAt: 1].
	length := self class elementHeaderSize + (message uint32At: self class elementHeaderSize + 9).
	(NvGsp checksum: (message copyFrom: 1 to: (length + 7 // 8 * 8 min: message size))) = 0
		ifFalse: [^self error: 'GSP message: bad checksum'].
	(message uint32At: 37) = rxSequence ifFalse: [^self error: 'GSP message: sequence number ', (message uint32At: 37) printString, ', expected ', rxSequence printString].
	Machine uint32At: tx + (self headerOf: tx at: 'rxHdrOff') put: read + elements \\ count.
	rxSequence := rxSequence + 1.
	rpc := message copyFrom: self class elementHeaderSize + 1 to: message size.
	^NvStruct on: rpc
! !
