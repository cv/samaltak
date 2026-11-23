TestCase subclass: #IdleRedrawTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools'!

IdleRedrawTest comment: 'I check that the tools that refresh by themselves draw again only what changed visibly, so an idle World presents nothing (docs/remote.md, Measurements): the Process Browser''s readings move in visible steps, and LoadMeters draw again only when a meter looks different.'!

!IdleRedrawTest methodsFor: 'tests'!
testReadingsMoveInVisibleSteps
	| b d |
	b := ProcessBrowser new.
	d := Dictionary new.
	self assert: (b shown: 1.2 for: #p in: d) equals: 1.2.
	"jitter of less than a point stays still"
	self assert: (b shown: 1.9 for: #p in: d) equals: 1.2.
	self assert: (b shown: 0.5 for: #p in: d) equals: 1.2.
	self assert: (b shown: 2.3 for: #p in: d) equals: 2.3.
	self assert: (b shown: 90.0 for: #p in: d) equals: 90.0.
	"a large reading moves by a fifth of itself"
	self assert: (b shown: 80.0 for: #p in: d) equals: 90.0.
	self assert: (b shown: 70.0 for: #p in: d) equals: 70.0.
	"to zero at once, from zero by a point"
	self assert: (b shown: 0.0 for: #p in: d) equals: 0.0.
	self assert: (b shown: 0.6 for: #p in: d) equals: 0.0.
	self assert: (b shown: 1.0 for: #p in: d) equals: 1.0.
	self assert: (b shown: nil for: #p in: d) isNil.
	self assert: (b shown: 0.3 for: #q in: d) equals: 0.3
!
testLoadMetersDrawAgainOnlyWhenTheyLookDifferent
	| m |
	m := LoadMeters new.
	m bounds: (0 @ 0 extent: 300 @ 20).
	m meters: (Array with: 'cpu' -> 10.0 with: 'gpu' -> nil).
	m drawRetainedOn: (Canvas extent: 300 @ 20 scale: 1).
	self assert: m drawState isNil.
	"the same text (10.0%) and the same fill in whole points: kept, not drawn again"
	m meters: (Array with: 'cpu' -> 10.04 with: 'gpu' -> nil).
	self assert: m drawState isNil.
	self assert: m meters first value equals: 10.04.
	self assert: m remoteState first equals: 'cpu=10.0'.
	m meters: (Array with: 'cpu' -> 10.2 with: 'gpu' -> nil).
	self assert: m drawState equals: #stale.
	m drawRetainedOn: (Canvas extent: 300 @ 20 scale: 1).
	m meters: (Array with: 'cpu' -> 10.2 with: 'gpu' -> 3.0).
	self assert: m drawState equals: #stale
! !
