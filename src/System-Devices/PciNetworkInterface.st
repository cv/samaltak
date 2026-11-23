NetworkInterface subclass: #PciNetworkInterface
	instanceVariableNames: 'pci mac semaphore armed lastActive wake sleeping process received sent failed tick tickIndex tickEvent ticking sentUs receivedUs'
	classVariableNames: ''
	package: 'System-Devices'!

PciNetworkInterface comment: 'I am the abstract class of the image''s drivers of network controllers on PCI (E1000eInterface, VirtioNetInterface). open finds the first controller one of them supports among the firmware''s PCI devices, takes it from the firmware''s drivers (its network stack with them) and starts it; NetworkInterface open falls back to the VM''s (VmNetworkInterface, the firmware''s driver) without one.

The controllers interrupt nobody. The stack''s Process takes the frames received (receiveInto:) when it wakes, at least every 10 ms; my Process, just above the idle Process, wakes it sooner: for replyUs after a frame went out, until one comes, it looks for one without pause (the peer''s answer, an ACK, is due: so a TCP sender is not held back); otherwise while frames came or went in the last busyMs it looks for one at every tick of the firmware''s timer, which then ticks every millisecond (Firmware>>fineTicks:; a timer event of mine, watched, signals tick), and signals the stack''s semaphore when one waits (once, until receiveInto: has answered nil); then the timer ticks at its own period again, and my Process sleeps until a frame comes or goes again. Between ticks the CPU halts (it looked without pause for 20 ms after every frame before: a vCPU busy all that time), for at most a millisecond more before a frame that was not awaited is seen. Without the firmware''s timer (tests) it looks without pause. Subclasses: startDevice, stopDevice, hasFrame, waiting, receiveFrame: (the next frame into a ByteArray: its length, nil if none), transmit:count:.'!

!PciNetworkInterface class methodsFor: 'opening'!
open
	"A driver of mine, running, for the first network controller on PCI one of my subclasses supports; nil if there is none (or no firmware)."
	| firmware nic |
	firmware := Firmware current.
	firmware isNil ifTrue: [^nil].
	(PciDevice in: firmware detect: [:d |
		nic := (self allSubclasses detect: [:c | c supports: d] ifNone: [nil]) ifNotNil: [:c | c new setPci: d].
		nic notNil and: [nic start]]) isNil ifTrue: [^nil].
	^nic
!
supports: aPciDevice
	^false
!
busyMs
	"How long after the last frame came or went my Process still looks for one at every tick."
	^100
!
replyUs
	"How long after a frame went out my Process looks for the answer without pause."
	^1000
! !

!PciNetworkInterface methodsFor: 'initialization'!
initialize
	received := sent := failed := 0.
	armed := true.
	sleeping := false.
	lastActive := sentUs := receivedUs := 0.
	ticking := false.
	wake := Semaphore new
!
setPci: aPciDevice
	pci := aPciDevice
!
start
	"Take the controller from the firmware's drivers and start it. Answer whether it runs."
	(pci disconnect and: [pci enable]) ifFalse: [^false].
	self startDevice ifTrue: [^true].
	self stopDevice.
	^false
! !

!PciNetworkInterface methodsFor: 'interface'!
macAddress
	^mac
!
send: aFrame count: n
	(n <= 1514 and: [self transmit: aFrame count: n]) ifFalse: [
		failed := failed + 1.
		^false].
	sent := sent + 1.
	sentUs := Time microsecondClockValue.
	self busy.
	^true
!
receiveInto: aByteArray
	| n |
	n := self receiveFrame: aByteArray.
	n isNil ifTrue: [
		armed := true.
		^nil].
	received := received + 1.
	receivedUs := Time microsecondClockValue.
	self busy.
	^n
!
semaphore: aSemaphore
	semaphore := aSemaphore.
	armed := true.
	process isNil ifTrue: [process := [self watch] forkAt: Processor lowestPriority + 1 named: 'network controller']
!
close
	self rest.
	tickEvent isNil ifFalse: [
		Machine watch: tickEvent semaphoreIndex: 0.
		Firmware current closeEvent: tickEvent].
	self forget.
	self stopDevice.
	pci isNil ifFalse: [pci release].
	pci := nil
!
forget
	"In an image resumed from a snapshot: the controller and its memory were the previous VM's."
	(process notNil and: [process isActiveProcess not]) ifTrue: [process terminate].
	process := nil.
	tickIndex isNil ifFalse: [Smalltalk vm unregisterExternalSemaphore: tickIndex].
	tick := tickIndex := tickEvent := nil.
	ticking := false
!
status
	"{frames received. sent. sends that failed. frames waiting}"
	^{received. sent. failed. self waiting}
! !

!PciNetworkInterface methodsFor: 'polling'!
busy
	"A frame came or went: my Process looks for the next one without pause."
	lastActive := Time millisecondClockValue.
	sleeping ifTrue: [
		sleeping := false.
		wake signal]
!
watch
	[(armed and: [self hasFrame]) ifTrue: [
		armed := false.
		lastActive := Time millisecondClockValue.
		receivedUs := Time microsecondClockValue.
		semaphore signal].
	self awaitsReply
		ifTrue: [Processor yield]
		ifFalse: [
			Time millisecondClockValue - lastActive < self class busyMs
				ifTrue: [self nap]
				ifFalse: [
					self rest.
					sleeping := true.
					wake wait]]] repeat
!
awaitsReply
	"Did a frame go out in the last replyUs, and none come since?"
	^sentUs > receivedUs and: [Time microsecondClockValue - sentUs < self class replyUs]
!
nap
	"Until the firmware's next tick; without its timer events, only let others run."
	ticking ifFalse: [self startTicking].
	tick isNil ifTrue: [^Processor yield].
	"ticks that came while others ran: look once more now"
	tick excessSignals > 0 ifTrue: [^tick initSignals].
	tick wait
!
startTicking
	"The firmware's timer every millisecond, my timer event at each of its ticks."
	| firmware |
	ticking := true.
	firmware := Firmware current.
	firmware isNil ifTrue: [^self].
	tickEvent isNil ifTrue: [
		tickEvent := firmware timerEvent.
		tickEvent isNil ifTrue: [^self].
		tick := Semaphore new.
		tickIndex := Smalltalk vm registerExternalSemaphore: tick.
		Machine watch: tickEvent semaphoreIndex: tickIndex].
	tick initSignals.
	firmware fineTicks: true.
	firmware setTimer: tickEvent every: 1000
!
rest
	"Quiet again: no more ticks of mine; the firmware's timer at its own period."
	ticking ifFalse: [^self].
	ticking := false.
	tickEvent isNil ifTrue: [^self].
	Firmware current setTimer: tickEvent every: nil.
	Firmware current fineTicks: false
! !

!PciNetworkInterface methodsFor: 'controller'!
startDevice
	"Reset the controller, set it up, start it: answer whether it runs; mac is its address."
	^self subclassResponsibility
!
stopDevice
	"Stop the controller (it uses its memory no more), also when startDevice failed half-way."
	^self subclassResponsibility
!
hasFrame
	^self subclassResponsibility
!
waiting
	"How many frames the controller has received that receiveFrame: has not taken."
	^self subclassResponsibility
!
receiveFrame: aByteArray
	^self subclassResponsibility
!
transmit: aFrame count: n
	^self subclassResponsibility
! !
