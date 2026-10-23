Object subclass: #RemoteInputPlan
	instanceVariableNames: 'steps'
	classVariableNames: ''
	package: 'System-Remote'!

RemoteInputPlan comment: 'I am a timed sequence of platform input events for the virtual input device: each step is {delayMs. event}, where delayMs is how long to wait before injecting event, an 8-slot event Array [type timeMs x y buttonOrKey modifiers textOrDelta windowId] as in vm/platform/README.md. RemoteInputPlanner makes me; RemoteInputDevice plays me.'!

!RemoteInputPlan methodsFor: 'initialization'!
initialize
	steps := OrderedCollection new
! !

!RemoteInputPlan methodsFor: 'adding'!
add: anEvent after: milliseconds
	steps add: (Array with: milliseconds with: anEvent).
	^anEvent
!
addAll: aPlan
	aPlan steps do: [:step | steps add: step].
	^aPlan
! !

!RemoteInputPlan methodsFor: 'accessing'!
steps
	^steps
!
events
	^(steps collect: [:step | step last]) asArray
!
types
	"The event type codes, in order (handy in tests)."
	^(steps collect: [:step | step last first]) asArray
!
duration
	"Total milliseconds of delays."
	^steps inject: 0 into: [:sum :step | sum + step first]
!
size
	^steps size
!
isEmpty
	^steps isEmpty
!
do: aBlock
	"aBlock value: delayMs value: event"
	steps do: [:step | aBlock value: step first value: step last]
! !

!RemoteInputPlan methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a RemoteInputPlan ('; print: steps size; nextPutAll: ' events, '; print: self duration; nextPutAll: ' ms)'
! !
