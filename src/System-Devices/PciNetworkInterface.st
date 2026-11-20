NetworkInterface subclass: #PciNetworkInterface
	instanceVariableNames: 'pci mac semaphore armed lastActive wake sleeping process received sent failed'
	classVariableNames: ''
	package: 'System-Devices'!

PciNetworkInterface comment: 'I am the abstract class of the image''s drivers of network controllers on PCI (E1000eInterface, VirtioNetInterface). open finds the first controller one of them supports among the firmware''s PCI devices, takes it from the firmware''s drivers (its network stack with them) and starts it; NetworkInterface open falls back to the VM''s (VmNetworkInterface, the firmware''s driver) without one.

The controllers interrupt nobody. The stack''s Process takes the frames received (receiveInto:) when it wakes, at least every 10 ms; my Process, just above the idle Process, wakes it sooner: while frames came or went in the last busyMs it looks for one without pause and signals the stack''s semaphore when one waits (once, until receiveInto: has answered nil); then it sleeps until a frame comes or goes again. Subclasses: startDevice, stopDevice, hasFrame, waiting, receiveFrame: (the next frame into a ByteArray: its length, nil if none), transmit:count:.'!

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
	"How long after the last frame came or went my Process still looks for one without pause."
	^20
! !

!PciNetworkInterface methodsFor: 'initialization'!
initialize
	received := sent := failed := 0.
	armed := true.
	sleeping := false.
	lastActive := 0.
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
	self busy.
	^n
!
semaphore: aSemaphore
	semaphore := aSemaphore.
	armed := true.
	process isNil ifTrue: [process := [self watch] forkAt: Processor lowestPriority + 1 named: 'network controller']
!
close
	self forget.
	self stopDevice.
	pci isNil ifFalse: [pci release].
	pci := nil
!
forget
	"In an image resumed from a snapshot: the controller and its memory were the previous VM's."
	(process notNil and: [process isActiveProcess not]) ifTrue: [process terminate].
	process := nil
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
		semaphore signal].
	Time millisecondClockValue - lastActive < self class busyMs
		ifTrue: [Processor yield]
		ifFalse: [
			sleeping := true.
			wake wait]] repeat
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
