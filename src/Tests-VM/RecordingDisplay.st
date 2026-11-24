Object subclass: #RecordingDisplay
	instanceVariableNames: 'lock events lastFrame extent frames'
	classVariableNames: ''
	package: 'Tests-VM'!

RecordingDisplay comment: 'I record completed packed frames from a VMGuestSimulation and supply input events for headless tests.'!

!RecordingDisplay methodsFor: 'initialization'!
initialize
	lock := Semaphore forMutualExclusion.
	events := OrderedCollection new.
	frames := 0
! !

!RecordingDisplay methodsFor: 'accessing'!
frames
	^lock critical: [frames]
!
extent
	^lock critical: [extent]
!
lastFrame
	"The latest packed 1-bit frame, or nil."
	^lock critical: [lastFrame]
!
key: aCode modifiers: anInteger
	self queueEvent: (Array with: 4 with: 0 with: 0 with: aCode with: anInteger)
!
queueEvent: anArray
	lock critical: [events addLast: anArray]
! !

!RecordingDisplay methodsFor: 'guest display'!
displayFrame: packedBytes extent: anExtent time: frameTime
	lock critical: [
		lastFrame := packedBytes copy.
		extent := anExtent.
		frames := frames + 1]
!
nextEvent
	^lock critical: [events isEmpty ifTrue: [nil] ifFalse: [events removeFirst]]
! !
