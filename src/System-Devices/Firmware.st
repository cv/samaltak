Object subclass: #Firmware
	instanceVariableNames: 'systemTable bootServices guids out lock timer period fine'
	classVariableNames: 'Current'
	package: 'System-Devices'!

Firmware comment: 'I am the UEFI firmware''s boot services (UEFI 2.10, 7) for drivers in Smalltalk, over Machine: protocols by GUID, handles and the firmware''s drivers that manage them, events, pool memory, the timer interrupt''s period (fineTicks:); and of its runtime services ResetSystem (Firmware powerOff, restart, warmRestart: the World menu''s Power off, Restart, Warm restart). Firmware current is nil on an operating system. A status is an error if its high bit is set (isError:). Structures are read at their offsets (LP64, natural alignment, the same on x86-64 and AArch64).'!

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
!
timerEvent
	"A new timer event (CreateEvent, EVT_TIMER) that notifies nobody: watch it (Machine watch:semaphoreIndex:). Nil if the firmware has none."
	^self outWord: [:p | self boot: 80 with: 16r80000000 with: 0 with: 0 with: 0 with: p]
!
setTimer: anEvent every: microseconds
	"Signal anEvent every microseconds from now on (SetTimer, TimerPeriodic: at the firmware's ticks); nil: no more (TimerCancel)."
	microseconds isNil
		ifTrue: [self boot: 88 with: anEvent with: 0 with: 0]
		ifFalse: [self boot: 88 with: anEvent with: 1 with: (microseconds max: 1) * 10]
!
closeEvent: anEvent
	self boot: 112 with: anEvent
! !

!Firmware methodsFor: 'timer'!
timerProtocol
	"EFI_TIMER_ARCH_PROTOCOL (PI 1.8, volume 2, 12.10: RegisterHandler, SetTimerPeriod, GetTimerPeriod), the timer interrupt that drives the firmware's timer events; nil if the firmware publishes none."
	timer isNil ifTrue: [timer := (self locateProtocol: '26baccb3-6f42-11d4-bce7-0080c73c8881') ifNil: [0]].
	^timer = 0 ifTrue: [nil] ifFalse: [timer]
!
tickPeriod
	"The timer interrupt's period, in 100 ns (OVMF's and ArmVirtQemu's: 100000, 10 ms); nil if unknown."
	| t |
	t := self timerProtocol.
	t isNil ifTrue: [^nil].
	^self outWord: [:p | Machine call: (self function: t at: 16) with: t with: p]
!
tickPeriod: hundredNs
	"Set the timer interrupt's period (SetTimerPeriod); answer whether the firmware did."
	| t |
	t := self timerProtocol.
	t isNil ifTrue: [^false].
	^(self isError: (Machine call: (self function: t at: 8) with: t with: hundredNs)) not
!
fineTicks: aBoolean
	"The timer interrupt every millisecond (true), or at the firmware's own period again (false): for a driver that looks at a device at every tick while it is busy (PciNetworkInterface). Timer events then fire within a millisecond of their time instead of the firmware's 10 ms, and the CPU halts between ticks. The VM's UefiSnp does the same for itself (UefiMachine>>fineTicks:): only one of the two drives a NIC."
	aBoolean = (fine == true) ifTrue: [^self].
	fine := aBoolean.
	aBoolean
		ifTrue: [
			period isNil ifTrue: [period := self tickPeriod ifNil: [0]].
			period > 10000 ifTrue: [self tickPeriod: 10000]]
		ifFalse: [period > 10000 ifTrue: [self tickPeriod: period]]
! !

!Firmware class methodsFor: 'accessing'!
current
	"The firmware, or nil on an operating system."
	Current isNil ifTrue: [Machine systemTable ifNotNil: [:t | Current := self new setSystemTable: t]].
	^Current
! !

!Firmware methodsFor: 'runtime services'!
runtimeServices
	^Machine uint64At: systemTable + 88
!
resetSystem: type
	"The firmware's ResetSystem (UEFI 2.10, 8.5.1) of type: 0 cold, 1 warm, 2 shutdown (power off), status 0. It does not return."
	^Machine call: (self function: self runtimeServices at: 104) with: type with: 0 with: 0 with: 0
! !

!Firmware class methodsFor: 'resetting'!
powerOff
	"Power the machine off (QEMU exits)."
	^self reset: 2
!
restart
	"A cold reset: the machine boots again (QEMU with -no-reboot exits)."
	^self reset: 0
!
warmRestart
	"A warm reset where the platform has one (else as cold)."
	^self reset: 1
!
reset: type
	"Leave as Smalltalk quit: does (the shutdown list), then the firmware's ResetSystem of type (0 cold, 1 warm, 2 shutdown) in place of the VM's exit, which powers off; on an operating system an error."
	| firmware |
	firmware := self current.
	firmware isNil ifTrue: [^self error: 'no firmware to reset'].
	Transcript flush.
	[Smalltalk processShutDownList: true] on: Error do: [:e | e return: nil].
	Smalltalk vm stderrWrite: 'samaltak: reset ', (#('cold' 'warm' 'shutdown') at: type + 1), (String with: Character lf).
	firmware resetSystem: type.
	Smalltalk primQuit: 0
! !

!Firmware class methodsFor: 'system startup'!
initialize
	Smalltalk addToStartUpList: self
!
startUp: resuming
	"The previous VM's firmware and memory are gone."
	resuming ifTrue: [Current := nil]
! !
