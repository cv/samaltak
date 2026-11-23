TestCase subclass: #LoadMetersTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools'!

LoadMetersTest comment: 'Tests the Process Browser''s load meters: the loads from known CPU, compile, background compiler and GPU times (ProcessBrowser>>loadsOver:processes:compile:background:gpu:), and LoadMeters drawing each track filled to its load, or empty with a dash when not measured.'!

!LoadMetersTest methodsFor: 'support'!
loads: percents compile: compileUs background: bgUs gpu: gpuUs
	"Over one second."
	^ProcessBrowser new loadsOver: 1000000 processes: percents compile: compileUs background: bgUs gpu: gpuUs
!
percents: anArray
	"Process -> percent from an Array of pairs."
	| d |
	d := IdentityDictionary new.
	anArray pairsDo: [:p :pct | d at: p put: pct].
	^d
!
render: meters extent: aPoint
	"meters drawn on white at device scale 2, read back."
	| canvas surface form |
	meters bounds: (0 @ 0 extent: aPoint).
	canvas := Canvas extent: aPoint scale: 2.
	canvas fillRect: (0 @ 0 extent: aPoint) color: Color white.
	meters drawOn: canvas.
	surface := Surface extent: aPoint scale: 2.
	[surface render: canvas displayList clear: Color white.
	 form := surface readback] ensure: [surface release].
	^form
!
isDark: aPoint in: aForm
	^((aForm pixelValueAt: (aPoint * 2) floor) bitAnd: 255) < 128
! !

!LoadMetersTest methodsFor: 'tests'!
testCpuIsTheProcessesButTheIdleOneAndTheCompiling
	| other loads |
	other := self fork: [Semaphore new wait].
	loads := self loads: (self percents: {Processor activeProcess. 30.0. other. 10.0. Processor idleProcess. 60.0})
		compile: 50000 background: 250000 gpu: 125000.
	self assert: loads equals: {'cpu' -> 45.0. 'jit' -> 25.0. 'gpu' -> 12.5}
!
testNoBackgroundCompilerNoGpu
	"No background job: no jit meter; no GPU time measured: gpu without a value."
	| loads |
	loads := self loads: (self percents: {Processor activeProcess. 12.5}) compile: 0 background: nil gpu: nil.
	self assert: loads size equals: 2.
	self assert: loads first equals: 'cpu' -> 12.5.
	self assert: loads last key equals: 'gpu'.
	self assert: loads last value isNil
!
testLoadsAreAtMostAWholeCore
	| loads |
	loads := self loads: (self percents: {Processor activeProcess. 100.0}) compile: 300000 background: 2000000 gpu: 1500000.
	self assert: (loads collect: [:each | each value]) equals: #(100.0 100.0 100.0)
!
testRemoteStateShowsEachLoad
	self assert: (LoadMeters new meters: {'cpu' -> 42.0. 'gpu' -> nil}; remoteState) equals: #('cpu=42.0' 'gpu=-')
!
testTrackIsFilledToTheLoad
	"Two meters of 200 points: a label of 32, then the track (116 points), filled to the load; nil leaves it empty."
	| meters form |
	meters := LoadMeters new meters: {'cpu' -> 50.0. 'gpu' -> nil}; yourself.
	form := self render: meters extent: 400 @ 20.
	self assert: (self isDark: 32 + 10 @ 10 in: form) description: 'the first tenth of a half full track'.
	self assert: (self isDark: 32 + 50 @ 10 in: form) description: 'below half of a half full track'.
	self deny: (self isDark: 32 + 70 @ 10 in: form) description: 'above half of a half full track'.
	self deny: (self isDark: 32 + 110 @ 10 in: form) description: 'the end of a half full track'.
	self deny: (self isDark: 200 + 32 + 10 @ 10 in: form) description: 'a track not measured'.
	self deny: (self isDark: 200 + 32 + 50 @ 10 in: form) description: 'a track not measured'
! !
