Object subclass: #RemoteInputJob
	instanceVariableNames: 'steps index answer device lastInject streak started result finished pending'
	classVariableNames: ''
	package: 'System-Remote'!

RemoteInputJob comment: 'I am one remote input command (click, type, key, drag, select, scroll, resize) as a sequence of steps that never wait: actions (blocks evaluated with me, which may add steps right after themselves), injections of input events (each a given number of ms after the previous one), and waits for a condition (polled every 20 ms, with a timeout). step runs what is due and answers how many ms to wait before calling it again (nil when I am done; the answer is then in answer).

The input dispatcher runs me in its own Process when it hosts remote control (ControlServer service): the events I inject come back to it through the platform queue and are delivered before I am stepped again, so waiting for the image to settle works without blocking it. runBlocking runs me in the calling Process (headless remote control, tests).'!

!RemoteInputJob methodsFor: 'initialization'!
initialize
	steps := OrderedCollection new.
	index := 0.
	answer := Dictionary new.
	device := RemoteInputDevice default.
	finished := false
! !

!RemoteInputJob methodsFor: 'accessing'!
answer
	^answer
!
answer: aDictionary
	answer := aDictionary
!
isFinished
	^finished
!
result
	"The value the last await... step produced."
	^result
!
result: anObject
	result := anObject
! !

!RemoteInputJob methodsFor: 'building'!
add: aStep
	"Append aStep; while a step runs (an action, a wait's done block), insert it right after that step instead (in order of the adds)."
	pending isNil ifTrue: [steps addLast: aStep] ifFalse: [pending addLast: aStep].
	^aStep
!
running: aBlock
	"Evaluate aBlock; the steps it adds go right after the step done last."
	pending := OrderedCollection new.
	[aBlock value] ensure: [
		pending reverseDo: [:each | steps add: each beforeIndex: index + 1].
		pending := nil]
!
do: aBlock
	"An action: aBlock value: me."
	^self add: (Array with: #action with: aBlock)
!
play: aPlan
	"Inject aPlan's events with their delays."
	aPlan do: [:delay :event | self add: (Array with: #inject with: event with: delay)]
!
waitFor: aBlock timeout: milliseconds then: doneBlock
	"Poll aBlock every 20 ms until it answers true (doneBlock value: true) or milliseconds passed (doneBlock value: false)."
	^self add: (Array with: #wait with: aBlock with: milliseconds with: doneBlock)
!
settle: milliseconds
	"Wait until the image settled (idle on two polls in a row), at most milliseconds; note it in the answer as settled."
	milliseconds <= 0 ifTrue: [^self do: [:job | answer at: 'settled' put: true]].
	^self add: (Array with: #settle with: milliseconds)
! !

!RemoteInputJob methodsFor: 'running'!
step
	"Run the steps that are due; answer the ms until I must be stepped again, or nil when I am done."
	| now s |
	[finished] whileFalse: [
		now := Time millisecondClockValue.
		index >= steps size ifTrue: [finished := true. ^nil].
		s := steps at: index + 1.
		s first == #action ifTrue: [
			index := index + 1.
			self running: [(s at: 2) value: self]]
		ifFalse: [
			s first == #inject ifTrue: [ | due |
				due := (lastInject ifNil: [now]) + (s at: 3).
				due > now ifTrue: [^due - now].
				device inject: (s at: 2).
				lastInject := now.
				index := index + 1]
			ifFalse: [
				s first == #settle ifTrue: [
					(self poll: [RemoteControl isIdle] timeout: (s at: 2) at: now) ifNotNil: [:wait | ^wait].
					answer at: 'settled' put: result]
				ifFalse: [
					(self poll: (s at: 2) timeout: (s at: 3) at: now) ifNotNil: [:wait | ^wait].
					self running: [(s at: 4) value: result]]]]].
	^nil
!
poll: aBlock timeout: milliseconds at: now
	"The current wait step: nil when it is over (result true if aBlock held on two polls in a row (settle) or once, false on timeout), else the ms to the next poll."
	| ok |
	started isNil ifTrue: [started := now. streak := 0].
	ok := aBlock value == true.
	ok ifTrue: [streak := streak + 1] ifFalse: [streak := 0].
	(streak >= 2 or: [ok and: [(steps at: index + 1) first == #wait]]) ifTrue: [^self endWait: true].
	now - started >= milliseconds ifTrue: [^self endWait: false].
	^20
!
endWait: aBoolean
	result := aBoolean.
	started := nil.
	index := index + 1.
	^nil
!
runBlocking
	"Run me to the end in the calling Process; answer my answer."
	| wait |
	[(wait := self step) notNil] whileTrue: [(Delay forMilliseconds: (wait max: 1)) wait].
	^answer
! !
