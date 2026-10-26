Object subclass: #RecordingDisplay
	instanceVariableNames: 'lock events texts frames'
	classVariableNames: ''
	package: 'Tests-VM'!

RecordingDisplay comment: 'I stand in for the VM Simulator''s screen (VMSimulation>>display:, see GuestDisplay): I keep the strings the guest draws (with their rule), count its frames, and hand out the key events a test queues.'!

!RecordingDisplay methodsFor: 'initialization'!
initialize
	lock := Semaphore forMutualExclusion.
	events := OrderedCollection new.
	texts := OrderedCollection new.
	frames := 0
! !

!RecordingDisplay methodsFor: 'accessing'!
frames
	^frames
!
texts
	"{string. rule} pairs, oldest first."
	^lock critical: [texts copy]
!
hasShown: aString rule: anInteger
	^self texts anySatisfy: [:each | each first = aString and: [each last = anInteger]]
!
key: aCode modifiers: anInteger
	lock critical: [events addLast: (Array with: 4 with: 0 with: 0 with: aCode with: anInteger)]
! !

!RecordingDisplay methodsFor: 'guest display'!
open: w height: h
	^7 @ 16
!
fillX: x y: y width: w height: h rule: rule
!
copyX: x y: y width: w height: h toX: toX y: toY
!
text: aString x: x y: y rule: rule
	lock critical: [texts addLast: (Array with: aString with: rule)]
!
bits: aByteArray x: x y: y width: w height: h rule: rule
!
nextEvent
	^lock critical: [events isEmpty ifTrue: [nil] ifFalse: [events removeFirst]]
!
flush
	frames := frames + 1
! !
