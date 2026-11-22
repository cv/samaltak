TestCase subclass: #DamageProbeTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-UI-Windows'!

DamageProbeTest comment: 'Tests DamageProbe''s damage from display lists (a quad moved, recolored or clipped differently damages its old and new bounds; a quad drawn the same does not, whatever its batch) and its tile count, and StageTimes'' counting.'!

!DamageProbeTest methodsFor: 'support'!
listWith: aBlock
	| c |
	c := Canvas extent: 200 @ 100 scale: 1.
	c fillRect: (0 @ 0 extent: 200 @ 100) color: Color white.
	aBlock value: c.
	^c displayList
!
damageFrom: aList to: anotherList
	| p damage |
	p := DamageProbe new.
	damage := OrderedCollection new.
	p diff: (p keysOf: aList) with: (p keysOf: anotherList) into: damage clip: (0 @ 0 extent: 200 @ 100) offset: 0 @ 0.
	^(damage asArray collect: [:r | r printString]) asSortedCollection asArray
! !

!DamageProbeTest methodsFor: 'tests'!
testMovedQuadDamagesOldAndNewBounds
	| a b |
	a := self listWith: [:c | c fillRect: (10 @ 10 extent: 20 @ 20) color: Color black].
	b := self listWith: [:c | c fillRect: (50 @ 10 extent: 20 @ 20) color: Color black].
	self assert: (self damageFrom: a to: b) equals: ((Array with: (10 @ 10 corner: 30 @ 30) printString with: (50 @ 10 corner: 70 @ 30) printString) asSortedCollection asArray)
!
testSameDrawingNoDamage
	| a b |
	a := self listWith: [:c | c fillRect: (10 @ 10 extent: 20 @ 20) color: Color black. c fillRect: (40 @ 10 extent: 5 @ 5) color: Color ultramarine].
	b := self listWith: [:c | c fillRect: (10 @ 10 extent: 20 @ 20) color: Color black. c fillRect: (40 @ 10 extent: 5 @ 5) color: Color ultramarine].
	self assert: (self damageFrom: a to: b) isEmpty
!
testRecoloredQuadDamagesItsBounds
	| a b |
	a := self listWith: [:c | c fillRect: (10 @ 10 extent: 20 @ 20) color: Color black].
	b := self listWith: [:c | c fillRect: (10 @ 10 extent: 20 @ 20) color: Color ultramarine].
	"Its old and its new quad."
	self assert: (self damageFrom: a to: b) equals: (Array with: (10 @ 10 corner: 30 @ 30) printString with: (10 @ 10 corner: 30 @ 30) printString)
!
testClipCountsByWhatItLeaves
	| a b |
	a := self listWith: [:c | c clip: (0 @ 0 extent: 100 @ 100) during: [c fillRect: (10 @ 10 extent: 20 @ 20) color: Color black]].
	b := self listWith: [:c | c clip: (0 @ 0 extent: 120 @ 100) during: [c fillRect: (10 @ 10 extent: 20 @ 20) color: Color black]].
	self assert: (self damageFrom: a to: b) isEmpty.
	b := self listWith: [:c | c clip: (0 @ 0 extent: 20 @ 100) during: [c fillRect: (10 @ 10 extent: 20 @ 20) color: Color black]].
	self assert: (self damageFrom: a to: b) notEmpty
!
testTileArea
	| p |
	p := DamageProbe new.
	self assert: (p tileAreaOf: #() in: (0 @ 0 extent: 64 @ 64)) equals: 0.
	self assert: (p tileAreaOf: (Array with: (1 @ 1 extent: 2 @ 2)) in: (0 @ 0 extent: 64 @ 64)) equals: 256.
	self assert: (p tileAreaOf: (Array with: (15 @ 15 extent: 2 @ 2) with: (0 @ 0 extent: 4 @ 4)) in: (0 @ 0 extent: 64 @ 64)) equals: 4 * 256.
	self assert: (p tileAreaOf: (Array with: (0 @ 0 extent: 100 @ 100)) in: (0 @ 0 extent: 64 @ 64)) equals: 64 * 64
!
testStageTimes
	| s t frame |
	self assert: StageTimes current isNil.
	s := StageTimes start.
	[t := Time microsecondClockValue.
	 t := s add: #copy since: t bytes: 100.
	 s add: #copy since: t bytes: 20.
	 frame := s takeFrame.
	 self assert: ((frame at: #copy) at: 1) equals: 2.
	 self assert: ((frame at: #copy) at: 3) equals: 120.
	 self assert: s takeFrame isEmpty.
	 self assert: ((s total at: #copy) at: 3) equals: 120]
		ensure: [StageTimes stop].
	self assert: StageTimes current isNil
! !
