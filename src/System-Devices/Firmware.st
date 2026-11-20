Object subclass: #Firmware
	instanceVariableNames: 'systemTable bootServices guids out lock'
	classVariableNames: 'Current'
	package: 'System-Devices'!

Firmware comment: 'I am the UEFI firmware''s boot services (UEFI 2.10, 7) for drivers in Smalltalk, over Machine: protocols by GUID, handles and the firmware''s drivers that manage them, events, pool memory. Firmware current is nil on an operating system. A status is an error if its high bit is set (isError:). Structures are read at their offsets (LP64, natural alignment, the same on x86-64 and AArch64).'!

!Firmware methodsFor: 'initialization'!
setSystemTable: anAddress
	systemTable := anAddress.
	bootServices := Machine uint64At: systemTable + 96.
	guids := Dictionary new.
	out := Machine allocate: 16.
	lock := Semaphore forMutualExclusion
! !

!Firmware methodsFor: 'accessing'!
systemTable
	^systemTable
!
conInHandle
	^Machine uint64At: systemTable + 40
!
conOut
	"EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL of the console."
	^Machine uint64At: systemTable + 64
! !

!Firmware methodsFor: 'calling'!
isError: status
	^status >= 16r8000000000000000
!
function: anAddress at: offset
	"The function pointer at offset in the table at anAddress."
	^Machine uint64At: anAddress + offset
!
boot: offset with: a
	^Machine call: (self function: bootServices at: offset) with: a
!
boot: offset with: a with: b
	^Machine call: (self function: bootServices at: offset) with: a with: b
!
boot: offset with: a with: b with: c
	^Machine call: (self function: bootServices at: offset) with: a with: b with: c
!
boot: offset with: a with: b with: c with: d
	^Machine call: (self function: bootServices at: offset) with: a with: b with: c with: d
!
boot: offset with: a with: b with: c with: d with: e
	^Machine call: (self function: bootServices at: offset) with: a with: b with: c with: d with: e
!
outWord: aBlock
	"aBlock value: the address of a word for an out-parameter; answer that word if aBlock answers a success status, else nil."
	^lock critical: [
		Machine uint64At: out put: 0.
		(self isError: (aBlock value: out)) ifTrue: [nil] ifFalse: [Machine uint64At: out]]
! !

!Firmware methodsFor: 'protocols'!
guid: aString
	"The address of the GUID 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' in memory (kept)."
	^guids at: aString ifAbsent: [| hex g |
		hex := (aString reject: [:c | c = $-]) asUppercase.
		g := Machine allocate: 16.
		Machine uint32At: g put: (Integer readFrom: (hex copyFrom: 1 to: 8) base: 16).
		Machine uint16At: g + 4 put: (Integer readFrom: (hex copyFrom: 9 to: 12) base: 16).
		Machine uint16At: g + 6 put: (Integer readFrom: (hex copyFrom: 13 to: 16) base: 16).
		0 to: 7 do: [:i | Machine uint8At: g + 8 + i put: (Integer readFrom: (hex copyFrom: 17 + (2 * i) to: 18 + (2 * i)) base: 16)].
		guids at: aString put: g]
!
locateProtocol: aGuidString
	"The first interface of the protocol, or nil."
	^self outWord: [:p | self boot: 320 with: (self guid: aGuidString) with: 0 with: p]
!
protocol: aGuidString on: aHandle
	"The handle's interface of the protocol, or nil."
	^self outWord: [:p | self boot: 152 with: aHandle with: (self guid: aGuidString) with: p]
!
handlesSupporting: aGuidString
	"The handles with the protocol (LocateHandleBuffer, ByProtocol)."
	| buffer count handles |
	count := Machine allocate: 8.
	buffer := self outWord: [:p | self boot: 312 with: 2 with: (self guid: aGuidString) with: 0 with: count with: p].
	buffer isNil ifTrue: [
		Machine free: count.
		^#()].
	handles := (1 to: (Machine uint64At: count)) collect: [:i | Machine uint64At: buffer + (8 * (i - 1))].
	Machine free: count.
	self freePool: buffer.
	^handles asArray
!
freePool: anAddress
	self boot: 72 with: anAddress
! !

!Firmware methodsFor: 'drivers'!
opensOf: aHandle do: aBlock
	"aBlock value: the agent value: the controller value: the attributes of each open of each protocol on aHandle (ProtocolsPerHandle, OpenProtocolInformation)."
	| words protocols entries |
	words := Machine allocate: 16.
	protocols := self outWord: [:p | self boot: 304 with: aHandle with: p with: words].
	protocols notNil ifTrue: [
		0 to: (Machine uint64At: words) - 1 do: [:i |
			entries := self outWord: [:p | self boot: 296 with: aHandle with: (Machine uint64At: protocols + (8 * i)) with: p with: words + 8].
			entries notNil ifTrue: [
				0 to: (Machine uint64At: words + 8) - 1 do: [:k | | e |
					e := entries + (24 * k).
					aBlock value: (Machine uint64At: e) value: (Machine uint64At: e + 8) value: (Machine uint32At: e + 16)].
				self freePool: entries]].
		self freePool: protocols].
	Machine free: words
!
childrenOf: aHandle
	"The controllers the drivers of the controller aHandle made (they opened one of its protocols BY_CHILD_CONTROLLER)."
	| children |
	children := OrderedCollection new.
	self opensOf: aHandle do: [:agent :controller :attributes |
		((attributes bitAnd: 8) ~= 0 and: [(children includes: controller) not]) ifTrue: [children add: controller]].
	^children asArray
!
isManaged: aHandle
	"Has a driver (or an application) one of its protocols open BY_DRIVER or EXCLUSIVE?"
	self opensOf: aHandle do: [:agent :controller :attributes | (attributes bitAnd: 16r30) = 0 ifFalse: [^true]].
	^false
!
disconnect: aHandle
	"Stop the drivers that manage the controller aHandle, those of the controllers they made first (DisconnectController). Answer whether none manages it any more (the status may say otherwise: iPXE's does)."
	(self childrenOf: aHandle) do: [:child | self disconnect: child].
	self boot: 272 with: aHandle with: 0 with: 0.
	^(self isManaged: aHandle) not
! !

!Firmware methodsFor: 'events'!
checkEvent: anEvent
	"Was anEvent signaled (it is not any more)?"
	^(self isError: (self boot: 120 with: anEvent)) not
! !

!Firmware class methodsFor: 'accessing'!
current
	"The firmware, or nil on an operating system."
	Current isNil ifTrue: [Machine systemTable ifNotNil: [:t | Current := self new setSystemTable: t]].
	^Current
! !

!Firmware class methodsFor: 'system startup'!
initialize
	Smalltalk addToStartUpList: self
!
startUp: resuming
	"The previous VM's firmware and memory are gone."
	resuming ifTrue: [Current := nil]
! !
