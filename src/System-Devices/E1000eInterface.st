PciNetworkInterface subclass: #E1000eInterface
	instanceVariableNames: 'registers memory device rxNext rxTaken txNext txClean'
	classVariableNames: ''
	package: 'System-Devices'!

E1000eInterface comment: 'I drive an Intel 82574L (e1000e: QEMU''s default NIC on q35) through its registers in BAR 0 (82574 datasheet, 10.2), polled: interrupts masked, legacy descriptors (7.1.4, 7.2.10), in one block of DMA memory: the receive ring of rxCount descriptors at 0, the transmit ring of txCount at 2048, their 2 KB buffers from 4096 on. A frame received is the descriptor at rxNext once the controller set its DD bit; the descriptors taken go back to the controller with the tail (RDT), 16 at a time and whenever no frame waits. A frame to send goes into the buffer at txNext, the tail (TDT) past it; the controller sets DD when it is done (RS), and the descriptors from txClean on that have it are free again.'!

!E1000eInterface class methodsFor: 'driving'!
supports: aPciDevice
	^aPciDevice vendor = 16r8086 and: [aPciDevice deviceId = 16r10D3]
!
rxCount
	^128
!
txCount
	^64
!
memorySize
	^4096 + (2048 * (self rxCount + self txCount))
!
registers: registersAddress memory: hostAddress device: deviceAddress
	"A driver of the controller with its registers at registersAddress and memorySize bytes of DMA memory at hostAddress, deviceAddress for the controller; initRings starts it (tests: a controller in memory)."
	^self new setRegisters: registersAddress memory: hostAddress device: deviceAddress
! !

!E1000eInterface methodsFor: 'initialization'!
setRegisters: registersAddress memory: hostAddress device: deviceAddress
	registers := registersAddress.
	memory := hostAddress.
	device := deviceAddress
! !

!E1000eInterface methodsFor: 'registers'!
reg: offset
	^Machine uint32At: registers + offset
!
reg: offset put: value
	Machine uint32At: registers + offset put: value
!
rxDescriptor: i
	^memory + (16 * i)
!
txDescriptor: i
	^memory + 2048 + (16 * i)
!
rxBuffer: i
	"Its offset in my memory."
	^4096 + (2048 * i)
!
txBuffer: i
	^4096 + (2048 * (self class rxCount + i))
! !

!E1000eInterface methodsFor: 'controller'!
startDevice
	"Reset the controller (interrupts masked), take its MAC address (RAL0, RAH0), set up the rings, bring the link up."
	registers := pci barAddress: 0.
	registers isNil ifTrue: [^false].
	memory := pci allocate: self class memorySize.
	memory isNil ifTrue: [^false].
	device := pci deviceAddress: memory.
	self reset ifFalse: [^false].
	mac := ByteArray new: 6.
	0 to: 5 do: [:i | mac at: i + 1 put: (((self reg: 16r5400 + (i // 4 * 4)) bitShift: -8 * (i \\ 4)) bitAnd: 255)].
	self reg: 16r0000 put: ((self reg: 16r0000) bitOr: 16r40).
	self initRings.
	1 to: 200 do: [:i |
		((self reg: 16r0008) bitAnd: 2) = 0 ifFalse: [^true].
		(Delay forMilliseconds: 10) wait].
	^true
!
reset
	"CTRL.RST, interrupts masked before and after (IMC), the causes cleared (ICR). Answer whether it is done."
	self reg: 16r00D8 put: 16rFFFFFFFF.
	self reg: 16r0000 put: ((self reg: 16r0000) bitOr: 1 << 26).
	1 to: 100 do: [:i |
		(Delay forMilliseconds: 1) wait.
		((self reg: 16r0000) bitAnd: 1 << 26) = 0 ifTrue: [
			self reg: 16r00D8 put: 16rFFFFFFFF.
			self reg: 16r00C0.
			^true]].
	^false
!
initRings
	"Every receive descriptor the controller's (RDT one behind RDH), every transmit descriptor mine; multicast table cleared; receive (RCTL: EN, BAM, SECRC, 2 KB buffers) and transmit (TCTL: EN, PSP, CT 15, COLD 63; TIPG) on."
	0 to: self class rxCount - 1 do: [:i |
		Machine uint64At: (self rxDescriptor: i) put: device + (self rxBuffer: i).
		Machine uint64At: (self rxDescriptor: i) + 8 put: 0].
	0 to: self class txCount - 1 do: [:i |
		Machine uint64At: (self txDescriptor: i) put: device + (self txBuffer: i).
		Machine uint64At: (self txDescriptor: i) + 8 put: 0].
	rxNext := rxTaken := txNext := txClean := 0.
	0 to: 127 do: [:i | self reg: 16r5200 + (4 * i) put: 0].
	self reg: 16r2800 put: (device bitAnd: 16rFFFFFFFF).
	self reg: 16r2804 put: (device bitShift: -32).
	self reg: 16r2808 put: 16 * self class rxCount.
	self reg: 16r2810 put: 0.
	self reg: 16r2818 put: self class rxCount - 1.
	self reg: 16r3800 put: (device + 2048 bitAnd: 16rFFFFFFFF).
	self reg: 16r3804 put: (device + 2048 bitShift: -32).
	self reg: 16r3808 put: 16 * self class txCount.
	self reg: 16r3810 put: 0.
	self reg: 16r3818 put: 0.
	Machine barrier.
	self reg: 16r0100 put: 16r04008002.
	self reg: 16r0410 put: 16r00602008.
	self reg: 16r0400 put: 16r0003F0FA
!
stopDevice
	registers isNil ifTrue: [^self].
	self reg: 16r0100 put: 0.
	self reg: 16r0400 put: 0.
	self reset
! !

!E1000eInterface methodsFor: 'frames'!
hasFrame
	^((Machine uint8At: (self rxDescriptor: rxNext) + 12) bitAnd: 1) = 1
!
waiting
	| n |
	n := 0.
	[n < self class rxCount and: [((Machine uint8At: (self rxDescriptor: rxNext + n \\ self class rxCount) + 12) bitAnd: 1) = 1]] whileTrue: [n := n + 1].
	^n
!
receiveFrame: aByteArray
	"The descriptor at rxNext once it is done (DD; its second word: length, checksum, status, errors, special): its frame unless it is not whole (EOP) or has errors (CE, SE, SEQ, CXE, RXE). The descriptors taken go back to the controller (RDT) 16 at a time, and when there is no frame."
	| d w n |
	[d := self rxDescriptor: rxNext.
	 w := Machine uint64At: d + 8.
	 (w bitAnd: 16r100000000) = 0 ifTrue: [
		self giveBack.
		^nil].
	 Machine barrier.
	 ((w bitAnd: 16r200000000) = 0 or: [(w bitAnd: 16r970000000000) ~= 0])
		ifTrue: [n := nil]
		ifFalse: [
			n := (w bitAnd: 16rFFFF) min: aByteArray size.
			Machine copy: n from: memory at: (self rxBuffer: rxNext) to: aByteArray at: 0].
	 Machine uint64At: d + 8 put: 0.
	 rxNext := rxNext + 1 \\ self class rxCount.
	 rxTaken := rxTaken + 1.
	 rxTaken >= 16 ifTrue: [self giveBack].
	 n isNil] whileTrue.
	^n
!
giveBack
	"The descriptors taken: the tail one behind rxNext."
	rxTaken = 0 ifTrue: [^self].
	Machine barrier.
	self reg: 16r2818 put: rxNext - 1 \\ self class rxCount.
	rxTaken := 0
!
transmit: aFrame count: n
	"Into the buffer at txNext (padded to 60 bytes), the descriptor's command EOP, IFCS, RS; the tail past it. False if the ring is full."
	| next length |
	self reclaim.
	next := txNext + 1 \\ self class txCount.
	next = txClean ifTrue: [^false].
	Machine copy: n from: aFrame at: 0 to: memory at: (self txBuffer: txNext).
	length := n.
	n < 60 ifTrue: [
		Machine copy: 60 - n from: (ByteArray new: 60) at: 0 to: memory at: (self txBuffer: txNext) + n.
		length := 60].
	Machine uint64At: (self txDescriptor: txNext) + 8 put: length + (16r0B bitShift: 24).
	txNext := next.
	Machine barrier.
	self reg: 16r3818 put: txNext.
	^true
!
reclaim
	"The descriptors from txClean on that the controller is done with (DD)."
	[txClean ~= txNext and: [((Machine uint8At: (self txDescriptor: txClean) + 12) bitAnd: 1) = 1]] whileTrue: [
		txClean := txClean + 1 \\ self class txCount]
! !
