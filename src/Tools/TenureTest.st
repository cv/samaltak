ToolPane subclass: #TenureTest
	instanceVariableNames: 'runs chart runButton status process timer current started'
	classVariableNames: ''
	package: 'Tools'!

TenureTest comment: 'I show what the scavenger''s TENURE_AGE does: Run allocates a million arrays of 80 slots, keeping only the last 3,000 (each dies before its second scavenge), and charts old space. Each run gets a lane headed with the TENURE_AGE the running VM reports, on the same axes as the others (the last two runs stay), and my lanes are saved with the image: after a Rebuild VM & reboot, a second Run puts the new VM''s next to the old one''s.

	TenureTest open'!

!TenureTest methodsFor: 'initialization'!
initialize
	| toolbar |
	super initialize.
	runs := OrderedCollection new.
	chart := TenureChart new name: 'chart'; yourself.
	chart runs: runs seconds: self class seconds.
	runButton := Button label: 'Run' action: [self run].
	runButton name: 'run'; tooltip: 'allocate a million arrays, keeping the last 3,000'.
	status := Label text: 'not run yet' font: #smallItalic.
	status color: #ink3; align: #right.
	toolbar := Row with: (Array with: (runButton sizeToContent; yourself) with: (status flex: 1; yourself)).
	toolbar spacing: 6; padding: (6 @ 4 corner: 8 @ 4); fixed: 29.
	self addAll: (Array with: toolbar with: chart)
!
minimumWindowExtent
	^480 @ 480
! !

!TenureTest methodsFor: 'accessing'!
chart
	^chart
!
runs
	^runs
!
isRunning
	^process notNil and: [process isTerminated not]
! !

!TenureTest methodsFor: 'running'!
run
	"The loop, in a Process below the windows' priority, sampled in my window's Process."
	self isRunning ifTrue: [^self].
	runs size = 2 ifTrue: [runs removeFirst].
	current := TenureRun new setAge: Smalltalk vm statistics tenureAge; yourself.
	runs addLast: current.
	started := Time millisecondClockValue.
	status text: 'allocating 1,000,000 arrays, keeping the last 3,000'.
	process := [self allocate] forkAt: Processor userBackgroundPriority named: 'Tenure Test'.
	timer := self every: 100 do: [self sample]
!
allocate
	"About 120,000 arrays a second: each is dropped 3,000 arrays later, before its second scavenge."
	| keep |
	keep := Array new: 3000.
	1 to: self class arrays do: [:i |
		keep at: i \\ 3000 + 1 put: (Array new: 80).
		i \\ 1200 = 0 ifTrue: [(Delay forMilliseconds: 10) wait]]
!
sample
	| s |
	s := Smalltalk vm statistics.
	current addSeconds: Time millisecondClockValue - started / 1000.0 old: s oldBytesUsed fullGCs: s fullGCs.
	chart invalidate.
	self isRunning ifFalse: [self stop. status text: 'done']
!
stop
	timer isNil ifFalse: [timer cancel. timer := nil]
!
windowClosed
	self stop.
	self isRunning ifTrue: [process terminate]
! !

!TenureTest class methodsFor: 'running'!
arrays
	^1000000
!
seconds
	"How long a run takes, near enough: its time axis."
	^self arrays / 120000.0
! !

!TenureTest class methodsFor: 'opening'!
open
	^self new openIn: (Tools placeAt: nil extent: 524 @ 700) title: 'Tenure Test'
! !
