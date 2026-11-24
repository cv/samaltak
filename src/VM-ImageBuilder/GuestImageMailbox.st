VMConstants subclass: #GuestImageMailbox
	instanceVariableNames: 'simulation endpoint objects nameBytes bindingHash lastSerial nextPoll'
	classVariableNames: ''
	package: 'VM-ImageBuilder'!

GuestImageMailbox comment: 'The v1 guest display mailbox is an ordinary Smalltalk global. At each platform poll I follow the current special objects, system dictionary, binding and mailbox anew. Guest oops are only local to one poll or the boot handshake: the guest interpreter cannot run or collect here. Only copied frame bytes and host integers cross the boundary.'!

!GuestImageMailbox class methodsFor: 'configuration'!
pollMicroseconds
	^8000
! !

!GuestImageMailbox class methodsFor: 'instance creation'!
simulation: aSimulation display: anEndpoint
	^self new simulation: aSimulation display: anEndpoint
! !

!GuestImageMailbox methodsFor: 'initialization'!
simulation: aSimulation display: anEndpoint
	simulation := aSimulation.
	endpoint := anEndpoint.
	objects := simulation module: ObjectMemory.
	nameBytes := 'GuestDisplayMailbox' asByteArray.
	nextPoll := 0
!
attach
	| assoc |
	bindingHash := objects wordHash
		ifTrue: [ImageBuilder new stringHash: nameBytes asString]
		ifFalse: [self legacyBindingHash].
	assoc := self binding.
	assoc = 0 ifTrue: [^false].
	objects storeRef: assoc at: ASSOC_VALUE put: objects trueOop.
	^true
!
legacyBindingHash
	| h |
	h := 2166136261.
	nameBytes do: [:b | h := ((h bitXor: b) * 16777619) bitAnd: 16rFFFFFFFF].
	^h bitAnd: 16r3FFFFFFF
! !

!GuestImageMailbox methodsFor: 'object access'!
isObject: oop
	^oop ~= 0 and: [oop ~= objects nilOop and: [objects isPtr: oop]]
!
isArray: oop
	^(self isObject: oop) and: [(objects rawClass: oop) = objects clsArray and: [(objects formatOf: oop) = F_VAR]]
!
smallIntegerAt: index of: oop
	| value |
	value := objects loadRef: oop at: index.
	^(objects isInt: value) ifTrue: [objects intVal: value]
!
binding
	"SystemDictionary begins with tally and array, as in ImageBuilder. Probe the guest's hash table; never enumerate the heap or retain a binding address."
	| globals table size index assoc key |
	globals := objects special: SO_SMALLTALK.
	((self isObject: globals) and: [(objects fmtHasPointers: (objects formatOf: globals)) and: [(objects numSlots: globals) >= 2]]) ifFalse: [^0].
	table := objects loadRef: globals at: 1.
	(self isArray: table) ifFalse: [^0].
	size := objects numSlots: table.
	size = 0 ifTrue: [^0].
	index := bindingHash \\ size.
	size timesRepeat: [
		assoc := objects loadRef: table at: index.
		assoc = objects nilOop ifTrue: [^0].
		((self isObject: assoc) and: [(objects rawClass: assoc) = (objects special: SO_ASSOCIATION)]) ifTrue: [
			key := objects loadRef: assoc at: ASSOC_KEY.
			(self isBindingName: key) ifTrue: [^assoc]].
		index := index + 1.
		index = size ifTrue: [index := 0]].
	^0
!
isBindingName: key
	^(self isObject: key)
		and: [(objects rawClass: key) = (objects special: SO_BYTESYMBOL)
		and: [(objects byteSize: key) = nameBytes size
		and: [(simulation memory bytesAt: key + 16 count: nameBytes size) = nameBytes]]]
! !

!GuestImageMailbox methodsFor: 'exchange'!
poll
	| now assoc mailbox |
	now := simulation microsecondClock.
	now < nextPoll ifTrue: [^self].
	nextPoll := now + self class pollMicroseconds.
	assoc := self binding.
	assoc = 0 ifTrue: [^self].
	mailbox := objects loadRef: assoc at: ASSOC_VALUE.
	((self isArray: mailbox) and: [(objects numSlots: mailbox) = 9 and: [(self smallIntegerAt: 0 of: mailbox) = 1]]) ifFalse: [^self].
	"Present a frame before supplying new input; it cannot reflect input we have yet to send."
	self presentFrameOf: mailbox.
	self sendInputTo: mailbox
!
presentFrameOf: mailbox
	| serial width height frame count elapsed |
	serial := self smallIntegerAt: 4 of: mailbox.
	(serial isNil or: [serial <= 0 or: [serial = lastSerial]]) ifTrue: [^self].
	width := self smallIntegerAt: 1 of: mailbox.
	height := self smallIntegerAt: 2 of: mailbox.
	(width notNil and: [height notNil and: [(width between: 1 and: 4096) and: [
		(height between: 1 and: 4096) and: [width * height <= 4194304]]]]) ifFalse: [^self].
	frame := objects loadRef: mailbox at: 3.
	count := width + 7 // 8 * height.
	((self isObject: frame) and: [(objects rawClass: frame) = objects clsBytearray and: [
		((objects formatOf: frame) between: F_BYTES and: F_BYTES + 7) and: [(objects byteSize: frame) = count]]]) ifFalse: [^self].
	elapsed := self smallIntegerAt: 8 of: mailbox.
	lastSerial := serial.
	endpoint displayFrame: (simulation memory bytesAt: frame + 16 count: count)
		extent: width @ height
		time: ((elapsed isNil or: [elapsed <= 0]) ifTrue: [nil] ifFalse: [elapsed])
!
sendInputTo: mailbox
	| slots read write next event |
	(objects isImmutable: mailbox) ifTrue: [^self].
	slots := objects loadRef: mailbox at: 5.
	((self isArray: slots) and: [(objects numSlots: slots) = 160 and: [(objects isImmutable: slots) not]]) ifFalse: [^self].
	read := self smallIntegerAt: 6 of: mailbox.
	write := self smallIntegerAt: 7 of: mailbox.
	(read notNil and: [write notNil and: [(read between: 0 and: 31) and: [write between: 0 and: 31]]]) ifFalse: [^self].
	"Bound work even if the endpoint always has input; a full ring leaves the remaining events queued."
	31 timesRepeat: [
		next := (write + 1) bitAnd: 31.
		next = read ifTrue: [^self].
		event := endpoint nextEvent.
		event isNil ifTrue: [^self].
		((event isArray and: [event size = 5]) and: [event allSatisfy: [:value |
			value isInteger and: [objects intFits: value]]]) ifTrue: [
			event doWithIndex: [:value :i |
				objects storeRef: slots at: write * 5 + i - 1 put: (objects intOop: value)].
			objects storeRef: mailbox at: 7 put: (objects intOop: next).
			write := next]]
! !
